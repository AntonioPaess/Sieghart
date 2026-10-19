import Foundation
import Testing

@MainActor final class IntegrationRoomBackend: CodingAgentServing {
    let provider: AIProvider
    var connected = false
    var onEvent: ((CodingAgentEvent) -> Void)?
    var listed: [CodingSession] = []
    var history: [String: [CodingMessage]] = [:]
    var connects = 0, sent: [String] = [], responses: [String] = []
    var failSend = false, queueReceipts = false
    var observedRoots: [String] = []
    var readGate: IntegrationGate?, sendGate: IntegrationGate?
    init(_ provider: AIProvider = .codex) { self.provider = provider }
    func connect() { connects += 1; connected = true }
    func disconnect() { connected = false }
    func sessions() -> [CodingSession] { listed }
    func messages(in session: CodingSession) async -> [CodingMessage] {
        if let gate = readGate { readGate = nil; await gate.suspend() }
        return history[session.id] ?? []
    }
    func create(in directory: String) -> CodingSession { CodingSession(provider: provider, providerID: "created", title: "Created", directory: directory, state: .ready, managed: true) }
    func send(_ text: String, to session: CodingSession) async throws {
        sent.append(text)
        if let gate = sendGate { sendGate = nil; await gate.suspend() }
        if failSend { throw CodingAgentError.unavailable("Fixture rejection") }
        if queueReceipts { onEvent?(.queued(sessionID: session.id, messageID: "queued:\(sent.count)")) }
    }
    func observeRoom(_ session: CodingSession) { observedRoots.append(session.id) }
    func interrupt(_ session: CodingSession) {}
    func respond(to approval: CodingApproval, allow: Bool, answers: [String: String]) { responses.append(approval.id); onEvent?(.resolved(approvalID: approval.id)) }
}

@MainActor final class IntegrationRoomFixture {
    let backend = IntegrationRoomBackend()
    let a = CodingSession(provider: .codex, providerID: "a", title: "A", directory: "/private/tmp", state: .ready)
    let b = CodingSession(provider: .codex, providerID: "b", title: "B", directory: "/private/tmp", state: .unknown)
    let room: AgentRoomViewModel
    init() {
        backend.listed = [a, b]
        backend.history[a.id] = [CodingMessage(id: "old", role: .user, text: "Saved question")]
        room = AgentRoomViewModel(services: [.codex: backend])
    }
    func cleanup() { backend.readGate?.release(); backend.sendGate?.release(); room.shutdown() }
}

@MainActor final class IntegrationCodexFixture {
    let directory: IntegrationDirectory
    let script: URL
    let rpc = AgentRPCProcess()
    let backend: CodexCodingAgent
    var workers: [CodingWorker] = []
    var states: [CodingSession] = []
    var approvals: [CodingApproval] = []
    var resolved: [String] = []
    var texts: [String] = []
    init() throws {
        directory = try IntegrationDirectory("codex-protocol")
        script = try directory.python(IntegrationProtocolFixtures.codex)
        let executable = script
        backend = CodexCodingAgent(rpc: rpc, executable: { executable }, desktopDirectory: directory.url)
        backend.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .session(let value): states.append(value)
            case .worker(let value): workers.append(value)
            case .approval(let value): approvals.append(value)
            case .resolved(let id): resolved.append(id)
            case .delta(_, _, let text): texts.append(text)
            default: break
            }
        }
    }
    func session() async throws -> CodingSession {
        try await backend.connect()
        return try #require(try await backend.sessions().first)
    }
    func cleanup() { backend.disconnect(); directory.cleanup() }
}

@MainActor final class IntegrationClaudeFixture {
    let directory: IntegrationDirectory
    let backend = ClaudeCodingAgent()
    var latest: CodingSession?
    var request: CodingApproval?
    var resolved = false
    var text = "", finalText = ""
    var liveIDs: [String] = []
    var childWorkers: [CodingWorker] = []
    init(apiKey: String = "owned-fixture-no-network") throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/node"), "Owned Claude SDK fixture requires /opt/homebrew/bin/node")
        directory = try IntegrationDirectory("claude-sdk")
        let package = directory.url.appendingPathComponent("node_modules/@anthropic-ai/claude-agent-sdk")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try #"{"name":"@anthropic-ai/claude-agent-sdk","type":"module","exports":"./index.mjs"}"#.write(to: package.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try IntegrationProtocolFixtures.claude.write(to: package.appendingPathComponent("index.mjs"), atomically: true, encoding: .utf8)
        backend.configure(node: "/opt/homebrew/bin/node", sdkDirectory: directory.url.path, apiKey: apiKey)
        backend.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .session(let value): latest = value
            case .worker(let value): childWorkers.append(value)
            case .approval(let value): request = value
            case .resolved: resolved = true
            case .delta(_, _, let value): text += value
            case .message(_, let value): liveIDs.append(value.id); if value.role == .assistant { finalText = value.text }
            default: break
            }
        }
    }
    func session() async throws -> CodingSession {
        try await backend.connect(); return try await backend.create(in: directory.url.path)
    }
    func cleanup() { backend.disconnect(); directory.cleanup() }
}

@MainActor final class IntegrationNewCodexFixture {
    let directory: IntegrationDirectory
    let service: CodexCodingAgent
    let room: AgentRoomViewModel
    init() throws {
        directory = try IntegrationDirectory("new-codex")
        let script = try directory.python(IntegrationNewChatFixture.fixture)
        service = CodexCodingAgent(executable: { script }, desktopDirectory: directory.url)
        room = AgentRoomViewModel(services: [.codex: service])
    }
    func create() async throws -> CodingSession {
        await room.connect(.codex)
        try #require(room.sessions.isEmpty && room.selectedID == nil)
        await room.create(.codex, directory: directory.url.path)
        return try #require(room.selected)
    }
    func requests() throws -> String { try String(contentsOf: directory.url.appendingPathComponent("requests.txt"), encoding: .utf8) }
    func cleanup() { room.shutdown(); service.disconnect(); directory.cleanup() }
}
