import Darwin
import Foundation

enum VoiceAppCommand: Equatable {
    case keepAwake(minutes: Int?, keepDisplay: Bool? = nil)
    case stopKeepAwake
    case show(Tool)
    enum Tool: String, Equatable { case keepAwake, system, audio, calendar, clipboard, files }

    private static let prefix = #"^(?:(?:por favor|please|(?:(?:voce|tu)\s+)?(?:pode|poderia|consegue|conseguiria)|can you|could you|quero que(?: voce)?|gostaria que(?: voce)?|sera que(?: voce)? pode)\s+)*"#
    private static let awake = #"(?:(?:o|modo)\s+)*(?:keep\s*(?:a\s*)?wake|manter\s+acordado|modo\s+acordado)"#
    static func normalizedToolName(_ text: String) -> String {
        // Observed pt-BR recognition of the product name; match whole words.
        text.replacingOccurrences(of: #"\bkepa\s*wake\b"#, with: "keep awake", options: [.regularExpression, .caseInsensitive])
    }
    static func targetsTool(_ text: String) -> Bool {
        normalizedToolName(text).range(of: prefix + #"(?:ativa[re]?|ative|ligar?|ligue|enable|start|turn on|desativa[re]?|desative|desligar?|desligue|disable|stop|turn off|abr[ae]|abrir|mostr[ae]|mostrar|open|show)\s+(?:(?:o|a|os|as|the|modo)\s+)*(?:keep\s*(?:a\s*)?wake|manter\s+acordado|modo\s+acordado|monitor(?:\s+do\s+sistema)?|system monitor|audio|calendario|calendar|clipboard|area de transferencia|arquivos|files)\b"#, options: .regularExpression) != nil
    }
    // Display intent is an independent option; it must survive natural phrasing
    // and the model tool bridge instead of being discarded as a second clause.
    static func displayQualifier(in text: String) -> (text: String, preference: Bool?) {
        let negative = #"(?:sem\s+(?:manter|deixar)\s+(?:a\s+)?(?:tela|ecran|monitor)\s+(?:ligad[ao]|aces[ao])|(?:deixe|deixa|deixar|permita)\s+(?:a\s+)?(?:tela|ecran|monitor)\s+(?:apagar|dormir)|(?:allow|let)\s+(?:the\s+)?(?:screen|display)\s+(?:to\s+)?sleep)"#
        let positive = #"(?:nao\s+(?:deixe|deixa|deixar)\s+(?:a\s+)?(?:tela|ecran|monitor)\s+apagar|(?:manter|mantenha|mantem|deixe|deixa|deixar)\s+(?:a\s+)?(?:tela|ecran|monitor)\s+(?:ligad[ao]|aces[ao]|acordad[ao]|ativ[ao])|com\s+(?:a\s+)?(?:tela|ecran|monitor)\s+(?:ligad[ao]|aces[ao])|(?:keep|keeping)\s+(?:the\s+)?(?:screen|display)\s+(?:on|awake))"#
        let pattern = #"(?:\s*[,;]?\s*(?:e|and)\s+|\s+)?(?:"# + "(" + negative + ")|(" + positive + "))"
        guard let regex = try? NSRegularExpression(pattern: pattern), !text.isEmpty else { return (text,nil) }
        let matches = regex.matches(in:text,range:NSRange(text.startIndex...,in:text))
        guard let last = matches.last else { return (text,nil) }
        let preference = last.range(at:2).location != NSNotFound
        let clean = regex.stringByReplacingMatches(in:text,range:NSRange(text.startIndex...,in:text),withTemplate:" ")
            .replacingOccurrences(of:#"\s+"#,with:" ",options:.regularExpression)
            .trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters))
        return (clean,preference)
    }
    static func resolvedChatRequest(_ text: String, history: [LocalChatMessage], now: Date = .now) -> String {
        let value = text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.init(identifier:"pt_BR"))
            .trimmingCharacters(in:.whitespacesAndNewlines.union(.punctuationCharacters))
        guard value.range(of:#"^(?:(?:por|e por) isso (?:eu )?(?:to|estou) pedindo (?:pra|para) (?:tu|voce) ativar|(?:entao )?(?:ativa|ative|ativar)(?: (?:agora|por favor))?|(?:entao )?pode ativar|(?:then )?(?:activate|enable) it(?: now)?)$"#,options:.regularExpression) != nil else { return text }
        // Only the immediately preceding user request can authorize a repair.
        // Never interpret assistant-produced tool/code text as an instruction.
        guard let previous = history.last(where:{$0.role == .user}), previous.text != text,
              (0...600).contains(now.timeIntervalSince(previous.date)), case .keepAwake? = parse(previous.text) else { return text }
        return previous.text
    }
    static func parse(_ text: String) -> Self? {
        let normalized = normalizedToolName(text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "pt_BR"))
        let qualifier = displayQualifier(in: normalized)
        let clean = qualifier.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "?!.,")))
            .replacingOccurrences(of: #"\s+(?:(?:para|pra) mim|por favor|please)$"#, with: "", options: .regularExpression)
        if clean.range(of: prefix + #"(?:desativa[re]?|desative|desligar?|desligue|disable|stop|turn off)\s+"# + awake + "$", options: .regularExpression) != nil { return .stopKeepAwake }
        let start = prefix + #"(?:ativa[re]?|ative|ligar?|ligue|enable|start|turn on)\s+"# + awake
        if clean.range(of: start + "$", options: .regularExpression) != nil { return .keepAwake(minutes: nil, keepDisplay: qualifier.preference) }
        let clockDuration = start + #"\s+(?:por|durante|for|com|em)\s+(\d{1,2})\s*h\s*(\d{2})$"#
        if let regex = try? NSRegularExpression(pattern: clockDuration),
           let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
           let hoursRange = Range(match.range(at: 1), in: clean), let minutesRange = Range(match.range(at: 2), in: clean),
           let hours = Int(clean[hoursRange]), let minutes = Int(clean[minutesRange]),
           minutes < 60, (1...1440).contains(hours * 60 + minutes) {
            return .keepAwake(minutes: hours * 60 + minutes, keepDisplay: qualifier.preference)
        }
        let duration = start + #"\s+(?:por|durante|for|com|em)\s+(\d+|uma?|duas?|dois|tres|quatro|meia|one|two|three|four|half)\s*(h|hr|hrs|hora|horas|hour|hours|min|minuto|minutos|minute|minutes)$"#
        if let regex = try? NSRegularExpression(pattern: duration), let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
           let amount = Range(match.range(at: 1), in: clean), let unit = Range(match.range(at: 2), in: clean) {
            let numbers: [String: Double] = ["um": 1, "uma": 1, "duas": 2, "dois": 2, "tres": 3, "quatro": 4, "meia": 0.5, "one": 1, "two": 2, "three": 3, "four": 4, "half": 0.5]
            let value = Double(clean[amount]) ?? numbers[String(clean[amount])] ?? 0
            let minutes = value * (clean[unit].hasPrefix("h") ? 60 : 1)
            guard (1...1440).contains(minutes), minutes.rounded() == minutes else { return nil }
            return .keepAwake(minutes: Int(minutes), keepDisplay: qualifier.preference)
        }
        let tools: [(String, Tool)] = [(#"keep\s*awake"#, .keepAwake), (#"monitor(?: do sistema)?|system monitor"#, .system),
            ("audio", .audio), ("calendario|calendar", .calendar), ("clipboard|area de transferencia", .clipboard), ("arquivos|files", .files)]
        for (name, tool) in tools where clean.range(of: prefix + #"(?:abr[ae]|abrir|mostr[ae]|mostrar|open|show)\s+(?:(?:o|a|os|as|the)\s+)?(?:"# + name + ")$", options: .regularExpression) != nil { return .show(tool) }
        return nil
    }
}

@MainActor enum VoiceAppTools {
    static func execute(_ command: VoiceAppCommand, in notch: NotchWidgetViewModel, language: String = "pt-BR") -> (reply: String, succeeded: Bool) {
        let en = language.hasPrefix("en")
        func l(_ pt: String, _ english: String) -> String { en ? english : pt }
        switch command {
        case .keepAwake(let minutes, let keepDisplay):
            if let keepDisplay { notch.keepAwake.request.keepDisplay = keepDisplay }
            if let minutes { notch.keepAwake.request.mode = .duration; notch.keepAwake.request.minutes = minutes }
            notch.keepAwake.start()
            if let error = notch.keepAwake.error { return (l("Não consegui ativar o Keep Awake. \(error)", "I couldn't enable Keep Awake. Please check its controls in the app."), false) }
            guard notch.keepAwake.enabled else { return (l("O Keep Awake não foi ativado.", "Keep Awake was not enabled."), false) }
            let duration = notch.keepAwake.remaining.map { l(" por \(Int(($0 / 60).rounded())) minutos", " for \(Int(($0 / 60).rounded())) minutes") } ?? l(" sem limite de tempo", " with no time limit")
            guard notch.keepAwake.holding else { return (l("Keep Awake configurado\(duration), aguardando as condições de energia, tela ou aplicativos que você definiu.", "Keep Awake configured\(duration), waiting for your power, display or app conditions."), true) }
            return ("\(l("Keep Awake ativado", "Keep Awake enabled"))\(duration). \(notch.keepAwake.request.keepDisplay ? l("O Mac e a tela vão permanecer acordados.", "Your Mac and display will stay awake.") : l("O Mac vai permanecer acordado; a tela pode apagar.", "Your Mac will stay awake; its display may sleep."))", true)
        case .stopKeepAwake:
            notch.keepAwake.stop()
            return (l("Keep Awake desativado. O Mac voltou às configurações normais de repouso.", "Keep Awake disabled. Your Mac is back to its normal sleep settings."), true)
        case .show(let tool):
            switch tool {
            case .keepAwake: notch.showKeepAwake()
            case .system: notch.showSystem()
            case .audio: notch.showAudio()
            case .calendar: notch.showCalendar()
            case .clipboard: notch.showClipboard()
            case .files: notch.showFiles()
            }
            return (l("Abri o controle no app.", "Opened the control in the app."), true)
        }
    }

    static func informationReply(to question: String, in notch: NotchWidgetViewModel, language: String = "pt-BR") -> String? {
        let en = language.hasPrefix("en")
        func l(_ pt: String, _ english: String) -> String { en ? english : pt }
        let text = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
        if text.range(of: #"\bkeep\s*awake\b"#, options: .regularExpression) != nil {
            if VoiceAppCommand.targetsTool(text) {
                return l("Não consegui interpretar esse comando. Diga, por exemplo: ative o Keep Awake por 2 horas com a tela ligada.", "I could not interpret that command. For example: enable Keep Awake for 2 hours and keep the screen on.")
            }
            guard text.range(of: #"^(?:como (?:usar|funciona)|o que e|how (?:to|does)|what is)\b"#, options: .regularExpression) == nil else { return nil }
            guard notch.keepAwake.enabled else { return l("O Keep Awake está desativado.", "Keep Awake is disabled.") }
            let duration = notch.keepAwake.remaining.map { l(" Faltam aproximadamente \(Int(ceil($0 / 60))) minutos.", " About \(Int(ceil($0 / 60))) minutes remaining.") } ?? l(" Está sem limite de tempo.", " It has no time limit.")
            return (notch.keepAwake.holding ? l("O Keep Awake está mantendo o Mac acordado.", "Keep Awake is keeping your Mac awake.") : l("O Keep Awake está configurado e aguardando as condições que você definiu.", "Keep Awake is configured and waiting for your conditions.")) + duration
        }
        let ownDevice = text.range(of: #"\b(?:meu|minha|my|deste|desse|neste|nesse|this)\b.*\b(?:mac|macos|pc|computador|computer|bateria|battery|memoria|memory|ram|disco|disk|storage|armazenamento|sistema|cpu|gpu|processor|processador|chip)\b"#, options: .regularExpression) != nil
            || text.range(of: #"\b(?:mac|pc|computador)\b.*\b(?:tenho|tem|possui|esta|ta)\b"#, options: .regularExpression) != nil
        guard ownDevice else { return nil }
        let overview = text.range(of: #"(?:informacoes|configuracao|especificacoes|specs|qual.*(?:mac|computador|pc) eu tenho)"#, options: .regularExpression) != nil
        let battery = text.contains("bateria") || text.contains("battery")
        let memory = text.contains("memoria") || text.contains("ram") || text.contains("memory")
        let disk = text.contains("disco") || text.contains("armazenamento") || text.contains("espaco") || text.contains("disk") || text.contains("storage")
        let cpu = text.contains("cpu") || text.contains("processador") || text.contains("chip")
        let thermal = text.contains("temperatura") || text.contains("termic") || text.contains("thermal") || text.contains("temperature")
        let os = text.contains("macos") || text.contains("versao") || text.contains("sistema operacional") || text.contains("operating system") || text.contains("version")
        guard overview || battery || memory || disk || cpu || thermal || os else { return nil }
        notch.monitor.refresh()
        let r = notch.monitor.reading
        func gb(_ bytes: UInt64) -> String { String(format: "%.1f", Double(bytes) / 1_073_741_824).replacingOccurrences(of: ".", with: en ? "." : ",") }
        var facts: [String] = []
        if overview || os { facts.append(l("Seu Mac usa \(ProcessInfo.processInfo.operatingSystemVersionString).", "Your Mac runs \(ProcessInfo.processInfo.operatingSystemVersionString).")) }
        if overview || cpu {
            var size = 0
            sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
            var buffer = [CChar](repeating: 0, count: max(1, size))
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                facts.append("\(l("O processador é", "The processor is")) \(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)), \(ProcessInfo.processInfo.processorCount) \(l("núcleos lógicos", "logical cores")).")
            }
            if let usage = r.cpu { facts.append(l("O uso de CPU medido pelo app é de \(Int((usage * 100).rounded())) por cento.", "The app measures CPU usage at \(Int((usage * 100).rounded())) percent.")) }
        }
        if overview || memory { facts.append(l("Há \(gb(r.memoryTotal > 0 ? r.memoryTotal : ProcessInfo.processInfo.physicalMemory)) gigabytes de memória, com \(gb(r.memoryUsed)) em uso segundo o app.", "Your Mac has \(gb(r.memoryTotal > 0 ? r.memoryTotal : ProcessInfo.processInfo.physicalMemory)) gigabytes of memory, with \(gb(r.memoryUsed)) in use according to the app.")) }
        if overview || disk {
            if let storage = r.disks.first(where: { $0.id == "/" }) ?? r.disks.first {
                facts.append(l("O disco principal tem \(gb(UInt64(max(0, storage.free)))) gigabytes livres de \(gb(UInt64(max(0, storage.total)))).", "The main disk has \(gb(UInt64(max(0, storage.free)))) gigabytes free out of \(gb(UInt64(max(0, storage.total))))."))
            } else { facts.append(l("O app não conseguiu ler o espaço em disco agora.", "The app couldn't read disk space right now.")) }
        }
        if overview || battery {
            if let level = r.battery { facts.append(l("A bateria está em \(Int((level * 100).rounded())) por cento\(r.onAC ? ", com alimentação externa" : "").", "Battery is at \(Int((level * 100).rounded())) percent\(r.onAC ? ", connected to power" : "").")) }
            else if battery { facts.append(l("O app não tem uma leitura de bateria disponível.", "A battery reading is unavailable.")) }
        }
        if thermal {
            if let temperature = r.temperature { facts.append(l("A temperatura medida é de \(Int(temperature.rounded())) graus Celsius.", "The measured temperature is \(Int(temperature.rounded())) degrees Celsius.")) }
            else { facts.append(l("O macOS não disponibilizou uma temperatura em graus para o app. O estado térmico informado é \(r.thermalState).", "macOS did not provide a temperature reading. The reported thermal state is \(r.thermalState).")) }
        }
        return facts.joined(separator: " ")
    }
}
