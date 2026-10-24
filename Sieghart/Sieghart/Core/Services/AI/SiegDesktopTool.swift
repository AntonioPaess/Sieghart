import Foundation
import FoundationModels

enum SiegDesktopToolAuthorization {
    static func command(operation: String, minutes: Int, original: String) -> VoiceAppCommand? {
        guard (0...1440).contains(minutes) else { return nil }
        let value = SearchVoiceParser.requestText(original).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US"))
        guard !SearchVoiceParser.hasSearchIntent(value) else { return nil }
        guard value.range(of: #"^(?:me\s+)?(?:como|how|explique|explain|repita|repeat|traduza|translate|imagine|suponha|suppose|simule|simulate|diga a frase|say the phrase)\b"#, options: .regularExpression) == nil else { return nil }
        let preventSleep = value.range(of: #"\bnao\s+(?:deixe|deixa)\b.*\bdormir\b"#, options: .regularExpression) != nil
        guard !SearchVoiceParser.hasNegatedIntent(value) || preventSleep else { return nil }
        if let parsed = VoiceAppCommand.parse(value) {
            switch (operation, parsed) {
            case ("keep_awake", .keepAwake), ("stop_keep_awake", .stopKeepAwake): return parsed
            default: return nil
            }
        }
        func withDisplay(_ command: VoiceAppCommand) -> VoiceAppCommand {
            if case .keepAwake(let duration, let display) = command {
                return .keepAwake(minutes: duration, keepDisplay: VoiceAppCommand.displayQualifier(in: value).preference ?? display)
            }
            return command
        }
        let clauses = value.components(separatedBy: " e ").flatMap { $0.components(separatedBy: " and ") }
        for clause in clauses {
            guard let parsed = VoiceAppCommand.parse(clause) else { continue }
            switch (operation, parsed) {
            case ("keep_awake", .keepAwake), ("stop_keep_awake", .stopKeepAwake): return withDisplay(parsed)
            default: continue
            }
        }
        let awake = value.range(of: #"\b(?:keep\s*awake|acordado|acordada)\b"#, options: .regularExpression) != nil || preventSleep
        guard awake else { return nil }
        let lead = value.replacingOccurrences(of: #"^(?:(?:por favor|please|(?:(?:voce|tu)\s+)?(?:pode|poderia|consegue|conseguiria)|can you|could you|quero que(?: voce)?|gostaria que(?: voce)?)\s+)*"#, with: "", options: .regularExpression)
        let stop = lead.range(of: #"^(?:desativ\w*|deslig\w*|pare|parar|disable|stop|turn off)\b"#, options: .regularExpression) != nil
        let keepDevice = lead.range(of: #"^keep\s+(?:(?:my|the|this)\s+)?(?:mac|computer|pc|device)\b.*\bawake\b"#, options: .regularExpression) != nil
        let start = preventSleep || keepDevice || lead.range(of: #"^(?:ativ\w*|lig\w*|manter|mantenha|deixe|deixa|enable|turn on)\b"#, options: .regularExpression) != nil
        if operation == "stop_keep_awake", stop { return .stopKeepAwake }
        if operation == "keep_awake", start, !stop {
            if let durationStart = value.range(of: #"\b(?:por|durante|for|com|em)\s+"#, options: .regularExpression) {
                let tail = String(value[durationStart.upperBound...]).components(separatedBy: " e ")[0].components(separatedBy: " and ")[0]
                guard case .keepAwake(let requested, _)? = VoiceAppCommand.parse("ative o keep awake por " + tail) else { return nil }
                return withDisplay(.keepAwake(minutes: requested))
            }
            return withDisplay(.keepAwake(minutes: nil))
        }
        return nil
    }
}

@MainActor final class SiegDesktopBridge {
    let execute: @MainActor (String, String, Int, String) async -> String
    init(execute: @escaping @MainActor (String, String, Int, String) async -> String) { self.execute = execute }
}

@available(macOS 27.0, *) private actor SiegToolBudget {
    private var remaining = 3
    func consume() -> Bool { guard remaining > 0 else { return false }; remaining -= 1; return true }
}

@available(macOS 27.0, *) struct SiegDesktopTool: Tool {
    let name = "sieg_desktop"
    let description = "Real Sieghart tools: app_info reads Mac/app facts; keep_awake/stop_keep_awake; weather; read_screen; draw; specialist_context (query: ada/rita/gantt/elinor/toni/sig) reads actual role-specific app data; ask_ada/ask_rita/ask_gantt/ask_elinor/ask_toni delegate; start_break and add_reminder execute explicit user requests; capabilities lists functions. Use separate calls for multiple requested operations. Do not guess state or claim success before a verified receipt."
    let bridge: SiegDesktopBridge
    let originalRequest: String
    private let budget = SiegToolBudget()
    init(bridge: SiegDesktopBridge, originalRequest: String) { self.bridge = bridge; self.originalRequest = originalRequest }
    @Generable struct Arguments {
        @Guide(description: "One of: app_info, keep_awake, stop_keep_awake, weather, read_screen, read_file, screen_controls, screen_action, draw, specialist_context, ask_ada, ask_rita, ask_gantt, ask_elinor, ask_toni, start_break, add_reminder, capabilities. read_file requires query=exact chosen filename requested by the user. screen_controls returns actual ids; screen_action requires query=one of those ids and an explicit matching user request. Never invent ids.") var operation: String
        @Guide(description: "Specific app information requested, or the weather city including any state/country qualifiers. Never drop qualifiers.") var query: String
        @Guide(description: "Keep Awake duration in minutes, 1 to 1440, or 0 for the user's saved duration.") var minutes: Int
    }
    func call(arguments: Arguments) async throws -> String {
        try Task.checkCancellation()
        guard await budget.consume() else { return "Tool budget reached. Answer using the verified results already returned." }
        let result = await bridge.execute(arguments.operation, String(arguments.query.prefix(300)), arguments.minutes, originalRequest)
        try Task.checkCancellation()
        return String(result.prefix(5000))
    }
}
