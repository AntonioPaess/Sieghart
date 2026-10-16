import Combine
import Foundation

enum AgentRoomPage { case room, chat }

@MainActor final class AgentRoomViewModel: ObservableObject {
    let localChat: LocalChatViewModel
    @Published private(set) var sessions: [CodingSession] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var connected = Set<AIProvider>()
    @Published private(set) var connecting = Set<AIProvider>()
    @Published private(set) var transcripts: [String: [CodingMessage]] = [:]
    @Published private(set) var approvals: [CodingApproval] = []
    @Published private(set) var sending = Set<String>()
    @Published private(set) var submitted: [String: UUID] = [:]
    @Published private(set) var sendFailures: [String: UUID] = [:]
    @Published private(set) var responding = Set<String>()
    @Published private(set) var loadingID: String?
    @Published private(set) var connectionErrors: [AIProvider: String] = [:]
    @Published var page: AgentRoomPage = .room
    @Published private(set) var workers: [String: CodingWorker] = [:]
    @Published private(set) var roomRootID: String?
    private var workerOrder: [String] = []
    private var observing = false
    private var lastObservation = Date.distantPast
    @Published var drafts: [String: String] = [:]
    @Published var notice: String?
    @Published var claudeNode = ""
    @Published var claudeSDK = ""
    // Memory only: never store API keys or chat transcripts in preferences.
    @Published var claudeKey = ""
    private let services: [AIProvider: any CodingAgentServing]
    private var versions: [AIProvider: Int] = [:]
    private var historyVersion = 0
    private var pendingDeltas: [String: [String: String]] = [:]
    private var deltaOrder: [(session: String, message: String)] = []
    private var deltaTask: Task<Void, Never>?
    private var pendingSubmissions: [String: CodingMessage] = [:]
    private let defaults: UserDefaults?

    init(services: [AIProvider: any CodingAgentServing], defaults: UserDefaults? = nil, localChat: LocalChatViewModel? = nil) {
        self.services = services; self.defaults = defaults
        self.localChat = localChat ?? .isolated()
        claudeNode = defaults?.string(forKey: "ada.claude.node") ?? ""
        claudeSDK = defaults?.string(forKey: "ada.claude.sdk") ?? ""
        for (provider, service) in services {
            service.onEvent = { [weak self] event in self?.receive(event, provider: provider) }
        }
    }
    var selected: CodingSession? { sessions.first { $0.id == selectedID } }
    var rootSessions: [CodingSession] { sessions.filter { $0.parentID == nil } }
    var roomRoot: CodingSession? { sessions.first { $0.id == roomRootID } }
    var roomWorkers: [CodingWorker] {
        guard let root = roomRoot else { return [] }
        return workers(in: root)
    }
    func workers(in root: CodingSession) -> [CodingWorker] {
        let latest = transcripts[root.id]?.last(where: { $0.role == .tool || $0.role == .assistant })?.text
        let online = connected.contains(root.provider)
        let coordinator = CodingWorker(id: root.id, rootID: root.id, parentID: root.id, provider: root.provider, name: "Ada", task: root.title, state: root.state, detail: root.observed ? root.detail : latest ?? root.detail, live: (root.managed || root.observed) && online, threadID: root.id)
        return [coordinator] + workerOrder.compactMap { workers[$0] }.filter { $0.rootID == root.id && $0.id != root.id }.map { worker in
            var value = worker; value.live = value.live && online; return value
        }
    }
    var messages: [CodingMessage] { selectedID.flatMap { transcripts[$0] } ?? [] }
    var requests: [CodingApproval] { approvals.filter { $0.sessionID == selectedID } }
    var activeCount: Int { sessions.filter { $0.state.busy }.count }
    var draft: String {
        get { selectedID.flatMap { drafts[$0] } ?? "" }
        set { if let selectedID { drafts[selectedID] = newValue } }
    }
    var canSend: Bool {
        guard let selected else { return false }
        return submissionBlockReason(for: selected) == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func submissionBlockReason(for session: CodingSession) -> String? {
        if sending.contains(session.id) { return "Your message is being sent." }
        if approvals.contains(where: { $0.sessionID == session.id }) || (session.managed && session.state == .waiting) {
            return "Answer the pending request before sending another message."
        }
        if session.managed && session.state == .working && session.provider != .codex {
            return "This conversation is still working. Wait for its reply or interrupt it before sending another message."
        }
        // Saved or externally observed state is not an owned turn. Let the
        // provider contact the writer and check its authoritative state. Codex
        // can also steer a working turn already owned by this runtime.
        return nil
    }
    func connect(_ provider: AIProvider) async {
        guard let service = services[provider], !connecting.contains(provider), !connected.contains(provider) else { return }
        connecting.insert(provider); notice = nil
        let version = versions[provider, default: 0]
        if let claude = service as? ClaudeCodingAgent {
            if claudeNode.isEmpty { claudeNode = ClaudeCodingAgent.nodeExecutable() }
            claude.configure(node: claudeNode, sdkDirectory: claudeSDK, apiKey: claudeKey)
            defaults?.set(claudeNode, forKey: "ada.claude.node"); defaults?.set(claudeSDK, forKey: "ada.claude.sdk")
        }
        do {
            try await service.connect()
            guard versions[provider, default: 0] == version else { return }
            connected.insert(provider)
            connectionErrors[provider] = nil
            await refresh(provider)
        } catch { if versions[provider, default: 0] == version { notice = error.localizedDescription; connectionErrors[provider] = error.localizedDescription } }
        if versions[provider, default: 0] == version { connecting.remove(provider) }
    }
    func disconnect(_ provider: AIProvider) {
        versions[provider, default: 0] += 1
        services[provider]?.disconnect(); connected.remove(provider); connecting.remove(provider)
        flushDeltas()
        let ids = Set(sessions.filter { $0.provider == provider }.map(\.id))
        if let loadingID, ids.contains(loadingID) { self.loadingID = nil }
        for index in sessions.indices where sessions[index].provider == provider {
            if sessions[index].state.busy { sessions[index].state = .blocked; sessions[index].detail = "Runtime disconnected. Reconnect to read the latest result." }
            else if sessions[index].state == .ready { sessions[index].state = .unknown }
            sessions[index].managed = false; sessions[index].turnID = nil
        }
        approvals.removeAll { ids.contains($0.sessionID) }
        for id in workers.keys where workers[id]?.provider == provider {
            workers[id]?.live = false
            workers[id]?.detail = "Disconnected. This is the last reported state."
        }
        if provider == .claude { claudeKey = "" }
    }
    func shutdown() { localChat.shutdown(); for provider in services.keys { disconnect(provider) }; deltaTask?.cancel(); deltaTask = nil }
    func openChat(_ id: String) async { page = .chat; await select(id) }
    func observeRoom() async { await observeRooms(roomRootID.map { [$0] } ?? []) }
    func observeRooms(_ ids: [String]) async {
        var visited = Set<String>()
        let roots = ids.compactMap { id -> CodingSession? in
            guard visited.insert(id).inserted, let root = sessions.first(where: { $0.id == id }),
                  connected.contains(root.provider), services[root.provider] != nil else { return nil }
            return root
        }.prefix(5)
        guard !observing, Date().timeIntervalSince(lastObservation) >= 2, !roots.isEmpty else { return }
        observing = true; lastObservation = .now
        defer { observing = false }
        for root in roots {
            guard !Task.isCancelled, connected.contains(root.provider), let service = services[root.provider] else { continue }
            let version = versions[root.provider, default: 0]
            do { try await service.observeRoom(root) }
            catch { if versions[root.provider, default: 0] == version { notice = error.localizedDescription } }
            guard !Task.isCancelled else { return }
        }
    }
    func refresh(_ provider: AIProvider) async {
        guard connected.contains(provider), let service = services[provider] else { return }
        let version = versions[provider, default: 0]
        do {
            let values = try await service.sessions()
            guard versions[provider, default: 0] == version, connected.contains(provider) else { return }
            for value in values { upsert(value) }
            if selectedID == nil, let first = rootSessions.first { await select(first.id) }
        } catch { if versions[provider, default: 0] == version { notice = error.localizedDescription } }
    }
    func select(_ id: String) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        selectedID = id; historyVersion += 1
        var root = session, visited = Set<String>()
        while let parent = root.parentID, visited.insert(root.id).inserted, let value = sessions.first(where: { $0.id == parent }) { root = value }
        roomRootID = root.id
        let version = historyVersion, connection = versions[session.provider, default: 0]
        guard connected.contains(session.provider), let service = services[session.provider] else { return }
        loadingID = id
        // Preserve new stream events delivered while the saved history is being read.
        let before = transcripts[id] ?? []
        do {
            let stored = try await service.messages(in: session)
            guard versions[session.provider, default: 0] == connection, connected.contains(session.provider) else { return }
            flushDeltas()
            var merged = Array(stored.suffix(100))
            for message in transcripts[id] ?? [] {
                if let index = merged.firstIndex(where: { $0.id == message.id }) {
                    // Keep only messages changed during this read; otherwise saved text wins.
                    if before.first(where: { $0.id == message.id }) != message { merged[index] = message }
                } else { merged.append(message) }
            }
            transcripts[id] = bounded(merged)
        } catch { if historyVersion == version { notice = error.localizedDescription } }
        if historyVersion == version { loadingID = nil }
    }
    func create(_ provider: AIProvider, directory: String) async {
        guard let service = services[provider] else { notice = "This provider is unavailable. Choose another provider."; return }
        guard connected.contains(provider), service.connected else { notice = "Connect \(provider.title) before creating a conversation."; return }
        var folder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &folder), folder.boolValue else { notice = "Choose an existing project folder."; return }
        let version = versions[provider, default: 0]
        do {
            let session = try await service.create(in: directory)
            guard versions[provider, default: 0] == version else { return }
            upsert(session); await openChat(session.id)
        } catch { if versions[provider, default: 0] == version { notice = error.localizedDescription } }
    }
    func send(to id: String? = nil) async {
        let targetID = id ?? selectedID
        guard targetID == selectedID else { notice = "The selected conversation changed. Your draft has been kept."; return }
        guard let session = sessions.first(where: { $0.id == targetID }), let service = services[session.provider] else { notice = "Choose a conversation first."; return }
        if let reason = submissionBlockReason(for: session) { notice = reason; return }
        let draft = drafts[session.id] ?? ""
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { notice = "Write a message first."; return }
        guard draft.utf8.count <= 16_384 else { notice = "Keep each message under 16 KB. Your draft has been kept."; return }
        // Coucou's send lifecycle: clear the field and show the user's words
        // immediately. Provider events replace this provisional bubble by ID.
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = CodingMessage(id: "pending:" + UUID().uuidString, role: .user, text: text)
        submitted[session.id] = UUID()
        pendingSubmissions[session.id] = pending
        put(pending, in: session.id); drafts[session.id] = ""; sending.insert(session.id); notice = nil
        defer { sending.remove(session.id) }
        func restore(_ reason: String) {
            sendFailures[session.id] = UUID()
            if pendingSubmissions[session.id]?.id == pending.id {
                transcripts[session.id]?.removeAll { $0.id == pending.id }
                pendingSubmissions[session.id] = nil
            }
            if (drafts[session.id] ?? "").isEmpty { drafts[session.id] = text }
            notice = reason
        }
        if !connected.contains(session.provider) || !service.connected {
            if connected.contains(session.provider) && !service.connected { disconnect(session.provider) }
            await connect(session.provider)
            guard connected.contains(session.provider), service.connected else { restore(connectionErrors[session.provider] ?? "Reconnect the provider before sending. Your draft has been kept."); return }
        }
        guard selectedID == session.id else { restore("The selected conversation changed. Your draft has been kept."); return }
        guard let target = selected else { restore("Choose a conversation first. Your draft has been kept."); return }
        // This operation owns the sending flag; check only turn/request gates
        // after reconnecting, because refreshed saved metadata may be busy.
        if approvals.contains(where: { $0.sessionID == target.id }) || (target.managed && target.state == .waiting) || (target.managed && target.state == .working && target.provider != .codex) {
            restore("The provider is waiting for a decision or a reply. Your draft has been kept."); return
        }
        do { try await service.send(text, to: target) }
        catch {
            // Never replace words typed while a rejected send was in flight.
            restore(error.localizedDescription)
        }
    }
    func interrupt() async {
        guard let session = selected, session.managed, session.state.busy, let service = services[session.provider] else { return }
        do { try await service.interrupt(session) } catch { notice = error.localizedDescription }
    }
    func respond(_ request: CodingApproval, allow: Bool, answers: [String: String]) async {
        guard approvals.contains(request), !responding.contains(request.id), let session = sessions.first(where: { $0.id == request.sessionID }), let service = services[session.provider] else { return }
        if allow && (!request.canAllow || request.questions.contains(where: { (answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })) { notice = "Answer each question before submitting."; return }
        responding.insert(request.id)
        do { try await service.respond(to: request, allow: allow, answers: answers) } catch { notice = error.localizedDescription }
        responding.remove(request.id)
    }
    private func upsert(_ session: CodingSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            guard sessions[index] != session else { return }
            sessions[index] = session
        }
        else { sessions.append(session) }
        sessions.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        // Keep the selected and running sessions even if the saved-session list is large.
        if sessions.count > 100 {
            let keep = Array(sessions.filter { $0.id == selectedID || $0.state.busy }.prefix(100))
            sessions = keep + Array(sessions.filter { item in !keep.contains(where: { $0.id == item.id }) }.prefix(100 - keep.count))
            let retained = Set(sessions.map(\.id)); transcripts = transcripts.filter { retained.contains($0.key) }; drafts = drafts.filter { retained.contains($0.key) }
            submitted = submitted.filter { retained.contains($0.key) }
            sendFailures = sendFailures.filter { retained.contains($0.key) }
        }
    }
    private func receive(_ event: CodingAgentEvent, provider: AIProvider) {
        switch event {
        case .worker(let worker):
            guard workers[worker.id] != worker else { return }
            if workers[worker.id] == nil { workerOrder.append(worker.id) }
            workers[worker.id] = worker
            if workerOrder.count > 200 {
                let removed = workerOrder.removeFirst(); workers[removed] = nil
            }
        case .session(let session):
            upsert(session)
            if !session.state.busy { flushDeltas() }
        case .message(let id, let message):
            flushDeltas(); put(message, in: id)
        case .queued(let id, let messageID):
            // The durable queue receipt identifies the eventual user message.
            // Replace the provisional bubble without claiming a turn started.
            if var pending = pendingSubmissions[id] {
                pending.id = messageID; put(pending, in: id)
                pendingSubmissions[id] = nil
            }
            if selectedID == id { notice = "Queued in Codex. It starts when the current turn finishes." }
        case .delta(let id, let message, let text):
            // Update SwiftUI at most ~15 times/sec, not once for every token.
            let existing = pendingDeltas[id]?[message] ?? ""
            if pendingDeltas[id]?[message] == nil { deltaOrder.append((id, message)) }
            pendingDeltas[id, default: [:]][message] = String((existing + text).prefix(32_768))
            if deltaTask == nil { deltaTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(67)); guard !Task.isCancelled else { return }; self?.flushDeltas()
            } }
        case .approval(let request): approvals.removeAll { $0.id == request.id }; approvals.append(request)
        case .resolved(let id): approvals.removeAll { $0.id == id }
        case .disconnected(let reason): disconnect(provider); connectionErrors[provider] = reason; notice = reason
        }
    }
    func flushDeltas() {
        deltaTask?.cancel(); deltaTask = nil
        let deltas = pendingDeltas, order = deltaOrder
        pendingDeltas.removeAll(); deltaOrder.removeAll()
        for (session, id) in order {
            guard let text = deltas[session]?[id] else { continue }
            let old = transcripts[session]?.first(where: { $0.id == id })?.text ?? ""
            put(CodingMessage(id: id, role: .assistant, text: String((old + text).prefix(32_768))), in: session)
        }
    }
    private func put(_ message: CodingMessage, in session: String) {
        var messages = transcripts[session] ?? []
        if message.role == .user, let pending = pendingSubmissions[session], message.id != pending.id, message.text == pending.text {
            if let index = messages.firstIndex(where: { $0.id == pending.id }) { messages[index] = message }
            pendingSubmissions[session] = nil
        }
        if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
        else { messages.append(message) }
        transcripts[session] = bounded(messages)
    }
    private func bounded(_ messages: [CodingMessage]) -> [CodingMessage] {
        var size = 0, result: [CodingMessage] = []
        for var message in messages.reversed().prefix(100) {
            message.text = String(message.text.prefix(32_768)); size += message.text.utf8.count
            if size > 512 * 1024 { break }
            result.append(message)
        }
        return result.reversed()
    }
}
