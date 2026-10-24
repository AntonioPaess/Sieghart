import Foundation

enum VoiceAddressNormalization {
    /// Only used for a request already recorded by Sieg. Never rewrites a
    /// mention inside a sentence or a question about Siri itself.
    static func request(_ text: String) -> String {
        text.replacingOccurrences(of: #"^(?:(?:hey|ei|oi)\s+)?siri(?:[, :]+(?=(?:qual|como|leia|le|traduz\w*|desenh\w*|faca|faz|mostr\w*|ativ\w*|abre|abra|me|what|how|read|draw|show|open|turn|can|could)\b))"#,
            with: "Sieg, ", options: [.regularExpression, .caseInsensitive])
    }
}
