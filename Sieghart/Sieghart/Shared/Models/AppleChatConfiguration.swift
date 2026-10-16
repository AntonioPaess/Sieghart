import Foundation

enum AppleChatMode: String, Codable, CaseIterable, Sendable {
    case privateCloudThinking, onDevice
    var title: String { self == .privateCloudThinking ? "Apple Cloud · Thinking" : "Apple Intelligence · On this Mac" }
    var shortTitle: String { self == .privateCloudThinking ? "Apple Cloud" : "On this Mac" }
    var requiresNetwork: Bool { self == .privateCloudThinking }
    var explanation: String {
        self == .privateCloudThinking
            ? "Uses Apple Private Cloud Compute for reasoning. Your messages, recent context and requested tool results are processed online by Apple. Requires macOS 27 and Apple’s app entitlement."
            : "Uses the new AFM 3 model supplied by macOS 27 on this Mac. No cloud model fallback. Official thinking is not supported in this mode. GitHub requests are online only when you connect GitHub."
    }
}

enum AppleChatReasoning: String, Codable, CaseIterable, Sendable {
    case light, moderate, deep
    var title: String { rawValue.capitalized }
}

struct AppleChatConfiguration: Equatable, Sendable {
    var mode: AppleChatMode = .privateCloudThinking
    var reasoning: AppleChatReasoning = .deep
    var label: String { mode == .privateCloudThinking ? "Apple Cloud · Thinking " + reasoning.title.lowercased() : "AFM 3 · On this Mac" }
}
