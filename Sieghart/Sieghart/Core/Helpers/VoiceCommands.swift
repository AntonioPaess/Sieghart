import Foundation
import AppKit

enum FocusVoiceCommand: Equatable {
    case start(minutes: Int?), resume, pause, finish, reset, startBreak, show, hide, configure, aiLimits
    case openApp(name: String)
    case search(query: String)
}

enum FocusVoiceParser {
    static func parse(_ transcript: String) -> FocusVoiceCommand? {
        // Parse search before interpreting words inside its query as actions.
        let original = SearchVoiceParser.requestText(transcript)
        if SearchVoiceParser.hasSearchIntent(original) {
            guard let query = SearchVoiceParser.query(in: original) else { return nil }
            return .search(query: query)
        }
        var text = transcript.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        text = text.replacingOccurrences(of: "’", with: "'")
        let negatedRequest = ["don't", "do not", "never", "nao", "not now"].contains(where: text.contains)
        let words = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        func has(_ options: [String]) -> Bool { !words.isDisjoint(with: options) }
        let personalUsage = has(["my", "meu", "minha", "meus", "minhas"])
            || text.range(of: #"^(?:show|mostre|mostrar|veja|exibir)\b"#, options: .regularExpression) != nil
            || text.range(of: #"^(?:(?:ai|ia|codex|claude)\s+(?:limits|limites|usage|consumo)|(?:limits|limites|usage|consumo)\s+(?:ai|ia|codex|claude))[.!?]?$"#, options: .regularExpression) != nil
        if personalUsage && has(["ai", "ia", "codex", "claude"]) && has(["limits", "limit", "limites", "limite", "usage", "consumo", "tokens", "cost", "costs", "gasto", "gastos"]) {
            guard !negatedRequest, !has(["pause", "stop", "start", "begin", "resume", "finish", "reset", "hide", "close", "focus", "pomodoro", "pausar", "iniciar", "retomar", "finalizar", "zerar", "esconder", "fechar", "focar"]) else { return nil }
            return .aiLimits
        }
        if SearchVoiceParser.hasQuestionIntent(original) {
            guard let query = SearchVoiceParser.question(in: original) else { return nil }
            return .search(query: query)
        }
        // Free topics are browser queries. Local verbs only act when the
        // sentence requests an action; words inside a topic are not commands.
        if !SearchVoiceParser.hasLocalIntent(text) {
            guard !SearchVoiceParser.hasNegatedIntent(original), !SearchVoiceParser.hasUnsupportedAction(text),
                  let query = SearchVoiceParser.freeQuery(in: original) else { return nil }
            return .search(query: query)
        }
        guard !negatedRequest else { return nil }
        if has(["open", "launch", "abrir", "abra", "abre"]) && !has(["sieghart", "companion", "widget", "companheiro"]) {
            guard !has(["and", "then", "search", "pesquisar", "pesquise", "depois", "tambem"]), !text.contains(" e ") else { return nil }
            let pattern = #"^(?:please\s+|por favor\s+)?(?:open|launch|abrir|abra|abre)\s+(?:(?:the|o|a|app|aplicativo)\s+)*([\p{L}\p{N} ._-]+)[.!?]?$"#
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            let name = String(text[range]).trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
            guard !name.isEmpty, name.count <= 80 else { return nil }
            return .openApp(name: name)
        }
        let pause = has(["pause", "pausar", "pausa", "stop", "parar"])
        let start = has(["start", "begin", "iniciar", "comecar", "comece", "focar", "focus", "pomodoro"])
        let resume = has(["resume", "continue", "retomar", "continuar"])
        let finish = has(["finish", "complete", "end", "finalizar", "terminar", "concluir"])
        let reset = has(["reset", "restart", "reiniciar", "zerar"])
        // Reject conflicting actions instead of choosing whichever substring wins.
        if [pause, resume, finish, reset].filter({ $0 }).count > 1 { return nil }
        if pause && has(["start", "begin", "iniciar", "comecar"]) { return nil }
        if has(["hide", "close", "esconder", "fechar"]) && has(["show", "open", "mostrar", "abrir"]) { return nil }
        if pause { return .pause }
        if reset { return .reset }
        if finish { return .finish }
        if resume { return .resume }
        if has(["configure", "settings", "adjust", "configurar", "ajustar"]) { return .configure }
        if has(["hide", "close", "esconder", "fechar", "recolher"]) { return .hide }
        if has(["show", "open", "mostrar", "abrir"]) {
            if has(["open", "abrir"]) && !has(["sieghart", "companion", "widget", "companheiro"]) { return nil }
            return .show
        }
        if (start || has(["take", "quero", "fazer", "preciso"])) && has(["break", "rest", "descanso", "intervalo"]) { return .startBreak }
        guard start else { return nil }
        guard !has(["hour", "hours", "hora", "horas", "seconds", "segundos"]) else { return nil }
        let numbers = ["twenty five": 25, "thirty five": 35, "forty five": 45, "fifty five": 55, "vinte e cinco": 25, "trinta e cinco": 35, "quarenta e cinco": 45, "cinquenta e cinco": 55, "fifteen": 15, "fifty": 50, "forty": 40, "thirty": 30, "twenty": 20, "sixty": 60, "ten": 10, "five": 5, "quinze": 15, "cinquenta": 50, "quarenta": 40, "trinta": 30, "vinte": 20, "sessenta": 60, "dez": 10, "cinco": 5]
        if text.range(of: "(?<![a-z])-[0-9]", options: .regularExpression) != nil { return nil }
        text = text.replacingOccurrences(of: "-", with: " ")
        for (phrase, value) in numbers.sorted(by: { $0.key.count > $1.key.count }) {
            text = text.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b", with: "\(value)", options: .regularExpression)
        }
        let leftover = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted))
        let unsupportedNumbers = ["zero", "one", "two", "three", "four", "six", "seven", "eight", "nine", "eleven", "twelve", "thirteen", "fourteen", "sixteen", "seventeen", "eighteen", "nineteen", "minus", "um", "dois", "tres", "quatro", "seis", "sete", "oito", "nove", "onze", "doze", "treze", "quatorze", "dezesseis", "dezessete", "dezoito", "dezenove", "menos"]
        if has(["minute", "minutes", "minuto", "minutos"]) && !leftover.isDisjoint(with: unsupportedNumbers) { return nil }
        let durations = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        guard durations.count <= 1 else { return nil }
        if durations.isEmpty && has(["minute", "minutes", "minuto", "minutos"]) { return nil }
        if let minutes = durations.first {
            guard (5...60).contains(minutes), minutes.isMultiple(of: 5), !has(["hour", "hours", "hora", "horas", "seconds", "segundos"]) else { return nil }
            return .start(minutes: minutes)
        }
        return .start(minutes: nil)
    }
}

// Search grammar describes the request, never a list of permitted topics.
// Query words remain data; they are not interpreted as actions or shell code.
enum SearchVoiceParser {
    private static let prefix = #"(?:(?:please|por favor)[, ]+|(?:(?:can|could) you|(?:voc[êe]\s+)?(?:pode|poderia)|(?:quero|gostaria)(?:\s+que\s+voc[êe])?)[, ]+|me\s+)*"#
    private static let verb = #"(?:search(?:\s+the\s+web)?|look\s+up|google|pesquis[ae]|pesquisar|bus(?:que|ca|car)|procur(?:e|a|ar)|(?:fa[çc]a|fazer)\s+uma\s+pesquisa)"#
    static func requestText(_ transcript: String) -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.replacingOccurrences(of: #"^(?:hey\s+|oi\s+)?(?:sig|sieghart)[, :]+"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
    static func hasNegatedIntent(_ text: String) -> Bool {
        text.range(of: #"^(?:please\s+|por favor\s+)?(?:n[ãa]o|don't|do not|never|not now)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func hasLocalIntent(_ text: String) -> Bool {
        let wrappers = #"(?:(?:please|por favor)[, ]+|(?:can|could) you\s+|(?:quero|preciso)(?:\s+que\s+voce)?\s+)*"#
        let actions = #"(?:open|launch|abrir|abra|abre|start|begin|iniciar|comecar|comece|focar|pause|pausar|pausa|stop|parar|resume|continue|retomar|continuar|finish|complete|end|finalizar|terminar|concluir|reset|restart|reiniciar|zerar|configure|settings|adjust|configurar|ajustar|hide|close|esconder|fechar|recolher|show|mostrar|take|fazer)\b"#
        return text.range(of: "^" + wrappers + actions, options: .regularExpression) != nil
            || text.range(of: #"^(?:focus|pomodoro)(?:$|\s+(?:for|por)\b)"#, options: .regularExpression) != nil
            || text.range(of: #"^(?:quero|preciso)\s+(?:um\s+)?(?:break|rest|descanso|intervalo)\b"#, options: .regularExpression) != nil
    }
    static func hasUnsupportedAction(_ text: String) -> Bool {
        text.range(of: #"^(?:please\s+|por favor\s+)?(?:send|enviar|envie|mande|delete|apague|exclua|create|crie|upload|fa[çc]a\s+upload)\b"#, options: .regularExpression) != nil
    }
    static func freeQuery(in text: String) -> String? {
        guard text.rangeOfCharacter(from: .alphanumerics) != nil,
              BrowserSearch.url(for: text) != nil else { return nil }
        return text
    }
    static func hasSearchIntent(_ transcript: String) -> Bool {
        transcript.range(of: "^" + prefix + verb + #"\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func hasQuestionIntent(_ transcript: String) -> Bool {
        let pattern = #"^(?:o que|como|qual|quais|quem|onde|aonde|quando|quanto|quantos|quantas|por que|por quê|porque|ser[áa] que|what|who|where|when|why|how|is|are|does|should)\b"#
        return transcript.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func question(in transcript: String) -> String? {
        guard hasQuestionIntent(transcript),
              transcript.split(whereSeparator: \.isWhitespace).count >= 2,
              BrowserSearch.url(for: transcript) != nil else { return nil }
        return transcript
    }
    static func query(in transcript: String) -> String? {
        let engine = #"(?:\s+(?:no|na|pelo|pela|on|using)\s+(?:google|web|internet))?"#
        let subject = #"(?:\s+(?:for|about|sobre|por))?"#
        let pattern = "^" + prefix + verb + #"(?:,)?"# + engine + subject + #"\s+(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)),
              let range = Range(match.range(at: 1), in: transcript) else { return nil }
        let query = String(transcript[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserSearch.url(for: query) == nil ? nil : query
    }
}

enum BrowserSearch {
    static func url(for query: String) -> URL? {
        guard !query.isEmpty, query.count <= 2_000,
              query.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        var parts = URLComponents(string: "https://www.google.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        // Google decodes form queries: a literal plus must not become a space.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
    @MainActor static func open(_ query: String) async throws -> String {
        guard let url = url(for: query), NSWorkspace.shared.open(url) else { throw BrowserSearchFailure() }
        return query
    }
}
private struct BrowserSearchFailure: LocalizedError {
    var errorDescription: String? { "Couldn't open your default browser. Try the search again." }
}

// Resolve exact installed app names/bundle aliases; transcripts are never
// evaluated as shell code, URLs, scripts, or search queries.
@MainActor enum LocalAppLauncher {
    static func open(_ spokenName: String) async throws -> String {
        let aliases = ["chatgpt": "com.openai.codex", "chat gpt": "com.openai.codex", "codex": "com.openai.codex", "whatsapp": "net.whatsapp.WhatsApp", "safari": "com.apple.Safari", "chrome": "com.google.Chrome", "google chrome": "com.google.Chrome", "finder": "com.apple.finder", "calendario": "com.apple.iCal", "calendar": "com.apple.iCal", "music": "com.apple.Music", "musica": "com.apple.Music"]
        func normalized(_ name: String) -> String { name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US")) }
        let name = normalized(spokenName)
        let manager = FileManager.default
        var matches: Set<URL> = []

        for root in ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
            for url in (try? manager.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let labels = [url.deletingPathExtension().lastPathComponent, bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String].compactMap { $0 }
                if labels.contains(where: { normalized($0) == name }) { matches.insert(url) }
            }
        }
        if matches.isEmpty, let id = aliases[name], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { matches.insert(url) }
        guard matches.count == 1, let url = matches.first else { throw AppLaunchFailure(name: spokenName, ambiguous: matches.count > 1) }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return app.localizedName ?? url.deletingPathExtension().lastPathComponent
    }
}
private struct AppLaunchFailure: LocalizedError {
    let name: String
    let ambiguous: Bool
    var errorDescription: String? { ambiguous ? "More than one app matches \(name). Say its full name." : "Couldn't find an installed app named \(name). Say its full name." }
}
