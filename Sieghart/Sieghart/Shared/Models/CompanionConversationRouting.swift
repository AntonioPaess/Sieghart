import Foundation

enum CompanionConversationRouting {
    static func isGeneralUtility(_ text: String) -> Bool {
        if VoiceWeatherQuery.parse(text) != nil { return true }
        if case .appAction = FocusVoiceParser.parse(text) { return true }
        return false
    }
    static func isAdaTopic(_ text: String) -> Bool {
        let value = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US"))
        guard !isGeneralUtility(text), !value.contains("codigo qr") else { return false }
        return value.range(of: #"\b(?:codig\w*|code|programa[crs]\w*|programming|debug\w*|bug\w*|algoritm\w*|algorithm\w*|two sum|swift\w*|carplay|cpmaptemplate|python|javascript|typescript|rust|sql|classe\w*|class|funcao|function|matemat\w*|math\w*|equac\w*|equation\w*|derivad\w*|derivative\w*|integral|teorema|theorem|hipotenusa|hypotenuse|pitagoras|pythagor\w*|circunferencia|pi)\b"#, options: .regularExpression) != nil
    }
    static func destination(for text: String, current: LocalChatPersona, history: [LocalChatMessage]) -> LocalChatPersona {
        if isGeneralUtility(text) { return .sig }
        if let explicit = CompanionSpecialistInstructions.requested(in: text) { return explicit }
        if isAdaTopic(text) { return .ada }
        if current == .ada, let previous = history.last(where: { $0.role == .user }), isGeneralUtility(previous.text) { return .sig }
        return current
    }
}

struct LocalChatHandoff: Codable, Equatable, Sendable {
    let conversationID: String
    let persona: LocalChatPersona
}
struct LocalChatUtilityReceipt: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case keepAwake }
    let kind: Kind
    let startedAt: Date
    let deadline: Date?
}
