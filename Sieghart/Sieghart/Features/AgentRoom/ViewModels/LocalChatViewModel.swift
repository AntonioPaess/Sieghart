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
    @Published private(set) var generationStartedAt: Date?
    @Published private(set) var states: [String: CodingAgentState] = [:]
    @Published private(set) var submitted: [String: UUID] = [:]
    @Published private(set) var failures: [String: UUID] = [:]
    @Published private(set) var attachments: [String: [CompanionDocument]] = [:]
    private let documentEngine: any DocumentAnswering = AppleDocumentAnswerService()
    @Published var drafts: [String: String] = [:]
    @Published var notice: String?
    private let generator: any LocalChatGenerating
    private let store: any LocalChatStoring
    private let defaults: UserDefaults?
    private var loaded = false
    private var canPersist = false
    private var preparation: Task<Void, Never>?
    private var generation: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private let responseTimeout: Duration
    private var pendingTurn: (chat: String, user: LocalChatMessage, reply: LocalChatMessage)?
    var awakeStatusProvider: (@MainActor () -> KeepAwakeViewModel?)?
    private var runID: UUID?
    private var snapshotTask: Task<Void, Never>?
    private var pendingSnapshot: (chat: String, message: String, text: String)?

    init(generator: any LocalChatGenerating, store: any LocalChatStoring = MemoryLocalChatStore(),
         configuration: AppleChatConfiguration = .init(), github: AdaGitHubViewModel? = nil, defaults: UserDefaults? = nil,
         responseTimeout: Duration = .seconds(45)) {
        self.generator = generator; self.store = store
        self.responseTimeout = responseTimeout
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
                // Older builds put all requests in Ada's room. Preserve those
                // histories while correcting chats started with a Sieg utility.
                for index in conversations.indices where conversations[index].persona == .ada {
                    let questions = conversations[index].messages.filter { $0.role == .user }
                    if let first = questions.first, CompanionConversationRouting.isGeneralUtility(first.text) {
                        conversations[index].persona = .sig
                    }
                }
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
    @discardableResult func create(_ persona: LocalChatPersona = .sig) async -> String? {
        await prepare()
        guard conversations.count < 20 else { notice = "You have 20 local chats. Delete a chat before creating another."; return nil }
        let chat = LocalChatConversation(persona: persona, title: "Chat with " + persona.title)
        conversations.insert(chat, at: 0); selectedID = chat.id; states[chat.id] = .ready
        await persist(); return chat.id
    }
    func select(_ id: String) { if conversations.contains(where: { $0.id == id }) { selectedID = id } }
    func matchingConversations(_ query: String = "", archived: Bool = false, persona: LocalChatPersona? = nil) -> [LocalChatConversation] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return conversations.filter { chat in
            (chat.archived == true) == archived && (persona == nil || chat.persona == persona) &&
            (term.isEmpty || ([chat.title] + chat.messages.map(\.text)).contains { $0.localizedStandardContains(term) })
        }.sorted { a, b in
            if (a.pinned == true) != (b.pinned == true) { return a.pinned == true }
            return a.updatedAt > b.updatedAt
        }
    }
    func setPinned(_ id: String, _ value: Bool) async {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].pinned = value; await persist()
    }
    func setArchived(_ id: String, _ value: Bool) async {
        guard generatingID != id, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].archived = value; await persist()
    }
    @discardableResult func openPersona(_ persona: LocalChatPersona) async -> String? {
        await prepare()
        if let chat = matchingConversations(persona: persona).first { select(chat.id); return chat.id }
        return await create(persona)
    }
    func delete(_ id: String) async {
        if generatingID == id { stop() }
        conversations.removeAll { $0.id == id }; drafts[id] = nil; attachments[id] = nil; submitted[id] = nil; failures[id] = nil; states[id] = nil
        if selectedID == id { selectedID = conversations.first?.id }
        await persist()
    }
    func attach(_ url: URL, to id: String) async {
        guard generatingID != id, conversations.contains(where: { $0.id == id }), (attachments[id]?.count ?? 0) < 2 else { return }
        do {
            let document = try await Task.detached(priority: .userInitiated) { try CompanionDocument.read(url) }.value
            guard conversations.contains(where: { $0.id == id }), (attachments[id]?.count ?? 0) < 2 else { return }
            attachments[id, default: []].append(document)
            SpatialAssistantCoordinator.activeInstance?.artifacts.saveDocument(document)
        } catch { notice = "Não consegui ler esse documento: " + error.localizedDescription }
    }
    func removeAttachment(at index: Int, from id: String) {
        guard attachments[id]?.indices.contains(index) == true else { return }
        attachments[id]?.remove(at: index)
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
        let destination = CompanionConversationRouting.destination(for: text, current: conversations[index].persona, history: conversations[index].messages)
        if destination != conversations[index].persona {
            route(text, from: id, to: destination)
            return
        }
        let documents = attachments[id] ?? []
        var user = LocalChatMessage(role: .user, text: text)
        user.attachedFiles = documents.isEmpty ? nil : documents.map(\.name)
        let reply = LocalChatMessage(role: .assistant, text: "")
        SpatialAssistantCoordinator.activeInstance?.registerResearchChat(self, id: id)
        conversations[index].messages.append(user)
        let history = conversations[index].messages, persona = conversations[index].persona
        conversations[index].messages.append(reply); conversations[index].updatedAt = .now
        if history.count == 1 { conversations[index].title = String(text.prefix(70)) }
        drafts[id] = ""; notice = nil; submitted[id] = UUID(); states[id] = .working; generatingID = id
        let run = UUID(); runID = run
        generationStartedAt = .now; pendingTurn = (id, user, reply)
        deadlineTask?.cancel()
        deadlineTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: responseTimeout) } catch { return }
            guard runID == run else { return }
            abortGeneration(timedOut: true)
        }
        generation = Task { [weak self] in
            guard let self else { return }
            defer { if runID == run { generatingID = nil; runID = nil; generation = nil; generationStartedAt = nil; pendingTurn = nil; deadlineTask?.cancel(); deadlineTask = nil } }
            do {
                let final: String
                if documents.isEmpty {
                final = try await generator.generate(history: history, persona: persona) { [weak self] snapshot in
                    guard let self, runID == run, !Task.isCancelled, snapshot.utf8.count <= 16_384 else { return }
                    pendingSnapshot = (id, reply.id, snapshot)
                    if snapshotTask == nil { snapshotTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(67)); guard !Task.isCancelled else { return }; self?.flush()
                    } }
                }
                } else {
                    final = try await documentEngine.answer(question: text, documents: documents, persona: persona,
                        language: SpatialAssistantCoordinator.activeInstance?.responseLanguage ?? "pt-BR")
                }
                try Task.checkCancellation()
                guard runID == run else { return }
                attachments[id] = nil
                guard !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, final.utf8.count <= 16_384 else { throw LocalChatError.emptyResponse }
                flush(); replace(reply.id, in: id, text: final); states[id] = .completed
                if case .appAction(.keepAwake) = FocusVoiceParser.parse(VoiceAppCommand.resolvedChatRequest(text, history: Array(history.dropLast()))), let awake = awakeStatusProvider?(), awake.enabled,
                   let chatIndex = conversations.firstIndex(where: { $0.id == id }), let messageIndex = conversations[chatIndex].messages.firstIndex(where: { $0.id == reply.id }) {
                    conversations[chatIndex].messages[messageIndex].utilityReceipt = .init(kind: .keepAwake, startedAt: .now, deadline: awake.request.end)
                }
                SpatialAssistantCoordinator.activeInstance?.remember(prompt: text, reply: AdaThoughtDisclosure.parse(final).visibleReply)
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
    private func route(_ text: String, from sourceID: String, to persona: LocalChatPersona) {
        guard let source = conversations.firstIndex(where: { $0.id == sourceID }) else { return }
        var destination = conversations.first { $0.persona == persona && $0.sourceConversationID == sourceID && $0.archived != true }
        if destination == nil {
            if conversations.count >= 20 { destination = matchingConversations(persona: persona).first }
            else {
                var chat = LocalChatConversation(persona: persona, title: String(text.prefix(70)))
                chat.sourceConversationID = sourceID; conversations.append(chat); destination = chat
            }
        }
        guard let destination else { notice = "Não há espaço para abrir a conversa do especialista. Remova uma conversa e tente novamente."; return }
        let en = SpatialAssistantCoordinator.activeInstance?.responseLanguage.hasPrefix("en") == true
        var receipt = LocalChatMessage(role: .assistant, text: en ? "Continuing with \(persona.title)." : "Vamos continuar com \(persona.title).")
        receipt.handoff = .init(conversationID: destination.id, persona: persona)
        conversations[source].messages += [.init(role: .user, text: text), receipt]
        conversations[source].updatedAt = .now
        drafts[sourceID] = nil; attachments[destination.id] = attachments.removeValue(forKey: sourceID)
        selectedID = destination.id; drafts[destination.id] = text
        send(to: destination.id)
    }
    private func abortGeneration(timedOut: Bool) {
        guard let turn = pendingTurn else { generation?.cancel(); return }
        runID = nil; generation?.cancel(); generation = nil; deadlineTask?.cancel(); deadlineTask = nil
        snapshotTask?.cancel(); snapshotTask = nil; pendingSnapshot = nil
        generatingID = nil; generationStartedAt = nil; pendingTurn = nil
        if let index = conversations.firstIndex(where: { $0.id == turn.chat }) {
            conversations[index].messages.removeAll { $0.id == turn.user.id || $0.id == turn.reply.id }
            if (drafts[turn.chat] ?? "").isEmpty { drafts[turn.chat] = turn.user.text }
            states[turn.chat] = timedOut ? .failed : .interrupted
            if timedOut { failures[turn.chat] = UUID() }
        }
        notice = timedOut ? "A resposta demorou além do limite. Seu pedido foi preservado; você pode tentar novamente." : "Resposta interrompida. Seu pedido voltou para o campo de mensagem."
        Task { [weak self] in await self?.persist() }
    }
    func stop() { abortGeneration(timedOut: false) }
    func appendExternalReply(_ text: String, to id: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.append(.init(role: .assistant, text: String(text.prefix(16_000))))
        conversations[index].updatedAt = .now
        Task { [weak self] in await self?.persist() }
    }
    func recordVoiceExchange(question: String, reply: String, persona: LocalChatPersona) async {
        await prepare()
        let previousSelection = selectedID
        let existing = matchingConversations(persona: persona).first { $0.id != generatingID && $0.messages.count <= 56 }
        let id: String?
        if let existing { id = existing.id }
        else { id = await create(persona); selectedID = previousSelection }
        guard let id, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        if conversations[index].messages.count >= 2, conversations[index].messages[conversations[index].messages.count-2].text == question { return }
        conversations[index].messages += [.init(role: .user, text: question), .init(role: .assistant, text: String(reply.prefix(16000)))]
        if conversations[index].messages.count == 2 { conversations[index].title = String(question.prefix(70)) }
        conversations[index].updatedAt = .now; await persist()
    }
    func shutdown() { stop(); deadlineTask?.cancel(); snapshotTask?.cancel(); snapshotTask = nil }
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
