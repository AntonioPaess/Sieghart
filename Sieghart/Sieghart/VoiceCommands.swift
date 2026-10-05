import Foundation

enum FocusVoiceCommand: Equatable {
    case start(minutes: Int?), resume, pause, finish, reset, startBreak, show, hide, configure
}

enum FocusVoiceParser {
    static func parse(_ transcript: String) -> FocusVoiceCommand? {
        var text = transcript.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        text = text.replacingOccurrences(of: "’", with: "'")
        guard !["don't", "do not", "never", "nao", "not now"].contains(where: text.contains) else { return nil }
        let words = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        func has(_ options: [String]) -> Bool { !words.isDisjoint(with: options) }
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
        if has(["show", "open", "mostrar", "abrir"]) { return .show }
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
