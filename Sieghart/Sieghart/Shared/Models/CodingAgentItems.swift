import Foundation

enum CodingAgentState: String, Codable, CaseIterable, Sendable {
    case unknown, ready, working, waiting, blocked, completed, interrupted, failed
    var title: String {
        switch self {
        case .unknown: "Not attached"
        case .ready: "Ready"
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .blocked: "Blocked"
        case .completed: "Completed"
        case .interrupted: "Interrupted"
        case .failed: "Failed"
        }
    }
    var busy: Bool { self == .working || self == .waiting }
}

struct CodingSession: Identifiable, Equatable, Sendable {
    var provider: AIProvider
    var providerID: String
    var title: String
    var directory: String
    var state: CodingAgentState = .unknown
    var turnID: String?
    var updatedAt: Date?
    var managed = false
    var detail = ""
    var parentID: String?
    var agentName: String?
    var historyPath: String?
    var observed = false
    var externalOwner = false
    var id: String { provider.rawValue + ":" + providerID }
}

struct CodingMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant, tool, system }
    var id: String
    var role: Role
    var text: String
}

struct CodingWorker: Identifiable, Equatable, Sendable {
    var id: String
    var rootID: String
    var parentID: String
    var provider: AIProvider
    var name: String
    var task: String
    var state: CodingAgentState = .unknown
    var detail = ""
    var live = false
    var threadID: String?
    var runID: String?
}

struct CodingQuestion: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var prompt: String
    var options: [String] = []
}

struct CodingApproval: Identifiable, Equatable, Sendable {
    var id: String
    var sessionID: String
    var title: String
    var detail: String
    var questions: [CodingQuestion] = []
    var canAllow = true
}

enum CodingAgentEvent: Sendable {
    case session(CodingSession)
    case worker(CodingWorker)
    case message(sessionID: String, CodingMessage)
    case delta(sessionID: String, messageID: String, text: String)
    case queued(sessionID: String, messageID: String)
    case approval(CodingApproval)
    case resolved(approvalID: String)
    case disconnected(String)
}

enum CodingAgentError: Error, LocalizedError {
    case unavailable(String), invalidResponse, timedOut, disconnected
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .invalidResponse: "The coding runtime returned an unsupported response."
        case .timedOut: "The coding runtime took too long to respond. Retry the connection."
        case .disconnected: "The coding runtime disconnected. Reconnect before continuing."
        }
    }
}

@MainActor protocol CodingAgentServing: AnyObject {
    var provider: AIProvider { get }
    var connected: Bool { get }
    var onEvent: ((CodingAgentEvent) -> Void)? { get set }
    func connect() async throws
    func disconnect()
    func sessions() async throws -> [CodingSession]
    func messages(in session: CodingSession) async throws -> [CodingMessage]
    func create(in directory: String) async throws -> CodingSession
    func send(_ text: String, to session: CodingSession) async throws
    func interrupt(_ session: CodingSession) async throws
    func respond(to approval: CodingApproval, allow: Bool, answers: [String: String]) async throws
    func observeRoom(_ session: CodingSession) async throws
}

extension CodingAgentServing {
    func observeRoom(_ session: CodingSession) async throws {}
}

@MainActor final class UnavailableCodingAgent: CodingAgentServing {
    let provider: AIProvider
    var connected = false
    var onEvent: ((CodingAgentEvent) -> Void)?
    init(_ provider: AIProvider) { self.provider = provider }
    func connect() throws { throw CodingAgentError.unavailable("Connect a coding runtime to use Ada’s room.") }
    func disconnect() {}
    func sessions() throws -> [CodingSession] { [] }
    func messages(in session: CodingSession) throws -> [CodingMessage] { [] }
    func create(in directory: String) throws -> CodingSession { throw CodingAgentError.disconnected }
    func send(_ text: String, to session: CodingSession) throws { throw CodingAgentError.disconnected }
    func interrupt(_ session: CodingSession) throws { throw CodingAgentError.disconnected }
    func respond(to approval: CodingApproval, allow: Bool, answers: [String: String]) throws { throw CodingAgentError.disconnected }
}

// Typed JSON keeps process messages Sendable; command output is displayed as data.
enum AgentJSON: Codable, Equatable, Sendable {
    case object([String: AgentJSON]), array([AgentJSON]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([AgentJSON].self) { self = .array(item) }
        else { self = .object(try value.decode([String: AgentJSON].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }
    subscript(_ key: String) -> AgentJSON { if case .object(let value) = self { return value[key] ?? .null }; return .null }
    var string: String? { if case .string(let value) = self { return value }; return nil }
    var array: [AgentJSON] { if case .array(let value) = self { return value }; return [] }
    var object: [String: AgentJSON] { if case .object(let value) = self { return value }; return [:] }
    var number: Double? { if case .number(let value) = self { return value }; return nil }
    var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
}
