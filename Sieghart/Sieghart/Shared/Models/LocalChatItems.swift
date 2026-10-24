import Foundation

enum LocalChatReadiness: Equatable, Sendable {
    case available
    case unavailable(String)

    var available: Bool {
        if case .available = self { return true }
        return false
    }

    var reason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

enum LocalChatPersona: String, Codable, CaseIterable, Sendable {
    case ada, sig, rita, gantt, elinor, toni

    var title: String { self == .sig ? "Sieg" : rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var avatar: CompanionAvatar { CompanionAvatar(rawValue: rawValue) ?? .sig }
}

struct LocalChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant, system }

    var id: String
    var role: Role
    var text: String
    var date: Date
    var attachedFiles: [String]? = nil
    var handoff: LocalChatHandoff? = nil
    var utilityReceipt: LocalChatUtilityReceipt? = nil

    init(id: String = UUID().uuidString, role: Role, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

struct LocalChatConversation: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var persona: LocalChatPersona
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [LocalChatMessage]
    var pinned: Bool? = nil
    var archived: Bool? = nil
    var sourceConversationID: String? = nil

    init(id: String = UUID().uuidString, persona: LocalChatPersona, title: String,
         createdAt: Date = Date(), updatedAt: Date = Date(), messages: [LocalChatMessage] = []) {
        self.id = id
        self.persona = persona
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

@MainActor protocol LocalChatGenerating: AnyObject {
    var readiness: LocalChatReadiness { get }
    var modelName: String { get }
    func configure(_ configuration: AppleChatConfiguration)
    func generateVoice(history: [LocalChatMessage], language: String,
                       onSnapshot: @escaping @MainActor (String) -> Void) async throws -> String
    /// Snapshots contain the complete response so far, rather than token deltas.
    func generate(history: [LocalChatMessage], persona: LocalChatPersona,
                  onSnapshot: @escaping @MainActor (String) -> Void) async throws -> String
}

extension LocalChatGenerating {
    func generateVoice(history: [LocalChatMessage], language: String,
                       onSnapshot: @escaping @MainActor (String) -> Void) async throws -> String {
        try await generate(history: history, persona: .sig, onSnapshot: onSnapshot)
    }

    var modelName: String { "Apple Foundation Models" }
    func configure(_ configuration: AppleChatConfiguration) {}
}

enum LocalChatError: Error, LocalizedError, Equatable {
    case unavailable(String), busy, emptyPrompt, inputTooLong, contextLimit, emptyResponse
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .busy: "An Apple model reply is already in progress. Wait for it or stop it first."
        case .emptyPrompt: "Write a message before sending."
        case .inputTooLong: "This message is too large for the Apple model. Try a shorter question or a smaller code excerpt."
        case .contextLimit: "This conversation exceeds the Apple model’s context. Start a new chat or send a shorter message."
        case .emptyResponse: "The Apple model returned an empty reply. Your message has been kept so you can retry."
        case .generationFailed(let reason): reason
        }
    }
}

/// Bounds only the model's context. The saved conversation keeps its full history.
/// Byte bounds control memory; token counts vary by language and are enforced by the model.
enum LocalChatContext {
    static let maximumPromptBytes = 8_000
    static let maximumHistoryBytes = 10_000
    static let maximumPastTurns = 6

    static func prepare(_ history: [LocalChatMessage]) throws -> (past: [LocalChatMessage], prompt: LocalChatMessage) {
        let dialogue = history.filter { $0.role != .system && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let prompt = dialogue.last, prompt.role == .user else { throw LocalChatError.emptyPrompt }
        guard prompt.text.utf8.count <= maximumPromptBytes else { throw LocalChatError.inputTooLong }

        var remaining = maximumHistoryBytes - prompt.text.utf8.count
        var past: [LocalChatMessage] = []
        let previous = Array(dialogue.dropLast())
        var end = previous.count
        var count = 0
        // Include complete user/assistant turns, without cutting messages or copying
        // a cancelled, unanswered prompt into a later request.
        while end >= 2, count < maximumPastTurns {
            let user = previous[end - 2]
            let assistant = previous[end - 1]
            guard user.role == .user, assistant.role == .assistant else { break }
            let bytes = user.text.utf8.count + assistant.text.utf8.count
            guard bytes <= remaining else { break }
            past.insert(contentsOf: [user, assistant], at: 0)
            remaining -= bytes
            end -= 2
            count += 1
        }
        return (past, prompt)
    }
}
