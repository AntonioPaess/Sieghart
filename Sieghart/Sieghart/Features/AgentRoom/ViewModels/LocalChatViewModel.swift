import Combine
import Foundation

@MainActor final class LocalChatViewModel: ObservableObject {
    @Published private(set) var conversations: [LocalChatConversation] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var readiness: LocalChatReadiness = .unavailable("Checking the Apple model…")
    @Published private(set) var configuration: AppleChatConfiguration
    @Published private(set) var modelName: String
    let github: AdaGitHubViewModel
    @Published private(set) var loading = false
    @Published private(set) var generatingID: String?
    @Published private(set) var states: [String: CodingAgentState] = [:]
    @Published private(set) var submitted: [String: UUID] = [:]
    @Published private(set) var failures: [String: UUID] = [:]
    @Published var drafts: [String: String] = [:]
    @Published var notice: String?
    private let generator: any LocalChatGenerating
    private let store: any LocalChatStoring
    private let defaults: UserDefaults?
    private var loaded = false
    private var canPersist = false
    private var preparation: Task<Void, Never>?
    private var generation: Task<Void, Never>?
    private var runID: UUID?
    private var snapshotTask: Task<Void, Never>?
    private var pendingSnapshot: (chat: String, message: String, text: String)?

    init(generator: any LocalChatGenerating, store: any LocalChatStoring = MemoryLocalChatStore(),
         configuration: AppleChatConfiguration = .init(), github: AdaGitHubViewModel? = nil, defaults: UserDefaults? = nil) {
        self.generator = generator; self.store = store
        self.github = github ?? AdaGitHubViewModel(); self.defaults = defaults
        let mode = defaults?.string(forKey: "ada.apple.mode").flatMap(AppleChatMode.init(rawValue:)) ?? configuration.mode
        let reasoning = defaults?.string(forKey: "ada.apple.reasoning").flatMap(AppleChatReasoning.init(rawValue:)) ?? configuration.reasoning
        let selection = AppleChatConfiguration(mode: mode, reasoning: reasoning)
        self.configuration = selection
        generator.configure(selection); modelName = generator.modelName
    }
    static func production(defaults: UserDefaults = .standard) -> LocalChatViewModel {
        let service = AdaGitHubContext()
        return LocalChatViewModel(generator: AppleLocalChatEngine(github: service), store: JSONLocalChatStore(),
            github: AdaGitHubViewModel(service: service), defaults: defaults)
    }
    static func isolated() -> LocalChatViewModel { LocalChatViewModel(generator: UnavailableLocalChatEngine()) }
    var selected: LocalChatConversation? { conversations.first { $0.id == selectedID } }
    var state: CodingAgentState { selectedID.flatMap { states[$0] } ?? .ready }
    var draft: String {
        get { selectedID.flatMap { drafts[$0] } ?? "" }
        set { if let selectedID { drafts[selectedID] = newValue } }
    }
    var canSend: Bool { selectedID != nil && readiness.available && generatingID == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func prepare() async {
        readiness = generator.readiness; modelName = generator.modelName
        guard !loaded else { return }
        if let preparation { await preparation.value; return }
        loading = true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                conversations = try await store.load(); canPersist = true
                selectedID = conversations.first?.id
            } catch {
                notice = "Local history could not be read. The original file is preserved. " + error.localizedDescription
            }
            loaded = true; loading = false
        }
        preparation = task; await task.value; preparation = nil
        // Opening Ada restores only a previously saved Sieg connection. New
        // credentials still require the explicit GitHub settings action.
        await github.restore()
    }
    func configure(mode: AppleChatMode? = nil, reasoning: AppleChatReasoning? = nil) {
        guard generatingID == nil else { notice = "Stop the current reply before changing Ada's model."; return }
        var next = configuration
        if let mode { next.mode = mode }; if let reasoning { next.reasoning = reasoning }
        configuration = next; generator.configure(next)
        defaults?.set(next.mode.rawValue, forKey: "ada.apple.mode")
        defaults?.set(next.reasoning.rawValue, forKey: "ada.apple.reasoning")
        readiness = generator.readiness; modelName = generator.modelName
    }
    @discardableResult func create(_ persona: LocalChatPersona = .ada) async -> String? {
        await prepare()
        guard conversations.count < 20 else { notice = "You have 20 local chats. Delete a chat before creating another."; return nil }
        let chat = LocalChatConversation(persona: persona, title: "Chat with " + persona.title)
        conversations.insert(chat, at: 0); selectedID = chat.id; states[chat.id] = .ready
        await persist(); return chat.id
    }
    func select(_ id: String) { if conversations.contains(where: { $0.id == id }) { selectedID = id } }
    func delete(_ id: String) async {
        if generatingID == id { stop() }
        conversations.removeAll { $0.id == id }; drafts[id] = nil; submitted[id] = nil; failures[id] = nil; states[id] = nil
        if selectedID == id { selectedID = conversations.first?.id }
        await persist()
    }
    func send(to id: String) {
        guard id == selectedID, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        readiness = generator.readiness
        guard readiness.available else { notice = readiness.reason; return }
        guard generatingID == nil else { notice = LocalChatError.busy.localizedDescription; return }
        let text = (drafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.utf8.count <= LocalChatContext.maximumPromptBytes else { notice = LocalChatError.inputTooLong.localizedDescription; return }
        guard conversations[index].messages.count <= 58 else { notice = "This chat has reached its local history limit. Start a new chat to continue."; return }
        let user = LocalChatMessage(role: .user, text: text), reply = LocalChatMessage(role: .assistant, text: "")
        conversations[index].messages.append(user)
        let history = conversations[index].messages, persona = conversations[index].persona
        conversations[index].messages.append(reply); conversations[index].updatedAt = .now
        if history.count == 1 { conversations[index].title = String(text.prefix(70)) }
        drafts[id] = ""; notice = nil; submitted[id] = UUID(); states[id] = .working; generatingID = id
        let run = UUID(); runID = run
        generation = Task { [weak self] in
            guard let self else { return }
            defer { if runID == run { generatingID = nil; runID = nil; generation = nil } }
            do {
                let final = try await generator.generate(history: history, persona: persona) { [weak self] snapshot in
                    guard let self, runID == run, !Task.isCancelled, snapshot.utf8.count <= 16_384 else { return }
                    pendingSnapshot = (id, reply.id, snapshot)
                    if snapshotTask == nil { snapshotTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(67)); guard !Task.isCancelled else { return }; self?.flush()
                    } }
                }
                try Task.checkCancellation()
                guard runID == run else { return }
                guard !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, final.utf8.count <= 16_384 else { throw LocalChatError.emptyResponse }
                flush(); replace(reply.id, in: id, text: final); states[id] = .completed
            } catch {
                guard runID == run else { return }
                snapshotTask?.cancel(); snapshotTask = nil; pendingSnapshot = nil
                // Failed/cancelled output is not saved as a completed answer.
                if let index = conversations.firstIndex(where: { $0.id == id }) {
                    conversations[index].messages.removeAll { $0.id == reply.id || $0.id == user.id }
                    if (drafts[id] ?? "").isEmpty { drafts[id] = text }
                    states[id] = Task.isCancelled || error is CancellationError ? .interrupted : .failed
                    if states[id] == .failed { failures[id] = UUID() }
                    notice = states[id] == .interrupted ? "Reply stopped. Your message is back in the draft." : error.localizedDescription
                }
            }
            await persist()
        }
    }
    func stop() { generation?.cancel() }
    func shutdown() { generation?.cancel(); snapshotTask?.cancel(); snapshotTask = nil }
    private func replace(_ message: String, in chat: String, text: String) {
        guard let index = conversations.firstIndex(where: { $0.id == chat }), let item = conversations[index].messages.firstIndex(where: { $0.id == message }) else { return }
        conversations[index].messages[item].text = text
    }
    private func flush() {
        snapshotTask?.cancel(); snapshotTask = nil
        if let pendingSnapshot { replace(pendingSnapshot.message, in: pendingSnapshot.chat, text: pendingSnapshot.text) }
        pendingSnapshot = nil
    }
    private func persist() async {
        guard canPersist else { return }
        // Never write token snapshots or unfinished turns on each display tick.
        let snapshot = conversations.map { chat in
            var value = chat
            if states[chat.id] == .working, value.messages.last?.role == .assistant { value.messages.removeLast(); if value.messages.last?.role == .user { value.messages.removeLast() } }
            return value
        }
        do { try await store.save(snapshot) }
        catch { notice = "This chat is available in memory, but local history could not be saved. " + error.localizedDescription }
    }
}
