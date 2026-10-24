import AppKit
import Foundation
import SwiftUI
import Testing

extension LogicTests {
    @Suite(.tags(.logic, .interactions)) struct FocusVoiceParserTests {
        struct Example: Sendable {
            let phrase: String
            let minutes: Int?
        }
        static let starts: [Example] = [
            .init(phrase: "Start focus focus", minutes: nil),
            .init(phrase: "Please start focus for twenty five minutes", minutes: 25),
            .init(phrase: "Quero focar por cinquenta minutos", minutes: 50),
            .init(phrase: "inicia o foco", minutes: nil), .init(phrase: "inicia o pomodoro", minutes: nil),
            .init(phrase: "inicie o foco", minutes: nil), .init(phrase: "começa o pomodoro", minutes: nil),
            .init(phrase: "Sig, inicia o foco", minutes: nil), .init(phrase: "Você pode iniciar o foco?", minutes: nil),
            .init(phrase: "inicia o pomodoro em vinte e cinco minutos", minutes: 25),
            .init(phrase: "foco por 30 minutos", minutes: 30),
            .init(phrase: "Start focus for twenty-five minutes", minutes: 25)
        ]
        @Test("G04.01 · Natural EN/PT wording and durations", arguments: starts)
        func naturalStarts(_ example: Example) {
            #expect(FocusVoiceParser.parse(example.phrase) == .start(minutes: example.minutes))
        }

        static let portugueseMatrix = ["inicia", "inicie", "iniciar", "começa", "comece", "começar"].flatMap { verb in
            ["foco", "pomodoro", "pomodor"].flatMap { target in
                stride(from: 5, through: 60, by: 5).map { Example(phrase: "\(verb) o \(target) em \($0) minutos", minutes: $0) }
            }
        }
        @Test("G04.01 · Six verbs × three targets × twelve durations", arguments: portugueseMatrix)
        func portugueseCommands(_ example: Example) {
            #expect(FocusVoiceParser.parse(example.phrase) == .start(minutes: example.minutes))
        }

        @Test("G04.01 · Negation, conflicts and invalid duration never execute", arguments: [
            "Não inicia o foco", "inicia e pausa o pomodoro", "inicia o foco em 20 ou 25 minutos",
            "Don't start focus", "Não iniciar o pomodoro", "Start and pause the timer", "Start focus for 90 minutes",
            "Start focus for one hour", "Start focus for seven minutes", "Start focus for 20 or 25 minutes",
            "Start focus for fifty nine minutes", "Start focus for -5 minutes", "Show and hide"
        ])
        func rejectedCommands(_ phrase: String) { #expect(FocusVoiceParser.parse(phrase) == nil) }

        @Test("G04.01 · Pause and break intents") func pauseAndBreak() {
            #expect(FocusVoiceParser.parse("Can you pause my focus timer") == .pause)
            #expect(FocusVoiceParser.parse("Take a break") == .startBreak)
        }

        @Test("G04.01 · Keep Awake durations reach the app rather than focus or conversation", arguments: [
            ("Ativa o keep awake por 2 hrs", 120), ("Sig, ative o Keep Awake por duas horas", 120),
            ("Enable keep awake for 30 minutes", 30), ("Liga o keep awake por meia hora", 30),
            ("Você consegue ativar o Keep Awake por duas horas?", 120),
            ("Será que você pode ativar o modo Keep Awake por 2 hrs pra mim?", 120),
            ("Pode ativar o keep a wake por duas horas por favor?", 120),
            ("Tu consegue ativar o Keep Awake por duas horas?", 120)
        ])
        func awakeDurations(_ phrase: String, _ minutes: Int) {
            #expect(FocusVoiceParser.parse(phrase) == .appAction(.keepAwake(minutes: minutes)))
        }

        @Test("G04.01 · Invalid, negated and compound Keep Awake requests never activate", arguments: [
            "Não ativa o keep awake por 2 horas", "Ativa o keep awake por 0 horas", "Ativa o keep awake por 25 horas",
            "Ativa o keep awake por -2 horas", "Ativa o keep awake por 2 horas e abre Safari"
        ])
        func rejectedAwake(_ phrase: String) {
            guard case .appAction(.keepAwake) = FocusVoiceParser.parse(phrase) else { return }
            Issue.record("Invalid request activated Keep Awake")
        }

        @Test("G04.01 · Tool questions and explicit searches do not execute app controls") func awakeQuestionsAndTools() {
            #expect(FocusVoiceParser.parse("Desativa o Keep Awake") == .appAction(.stopKeepAwake))
            #expect(FocusVoiceParser.parse("Abra o monitor do sistema") == .appAction(.show(.system)))
            #expect(FocusVoiceParser.parse("Como ativar o keep awake por 2 horas?") == .ask(question: "Como ativar o keep awake por 2 horas?"))
            #expect(FocusVoiceParser.parse("Pesquise como ativar o keep awake") == .search(query: "como ativar o keep awake"))
        }
    }

    @Suite(.tags(.logic, .interactions)) struct VoiceIntentTests {
        struct SearchExample: Sendable { let spoken: String; let query: String; var browser = true }
        static let searches: [SearchExample] = [
            .init(spoken: "Como iniciar o pomodoro?", query: "Como iniciar o pomodoro?", browser: false),
            .init(spoken: "pesquise como inicia o foco", query: "como inicia o foco"),
            .init(spoken: "search for Open Safari and start focus", query: "Open Safari and start focus"),
            .init(spoken: "Pesquise receitas de pão & café", query: "receitas de pão & café"),
            .init(spoken: "pesquise por arquiteturas de mac", query: "arquiteturas de mac"),
            .init(spoken: "pesquisa github", query: "github"), .init(spoken: "procure receitas de pão", query: "receitas de pão"),
            .init(spoken: "procure arquitetura de processadores ARM", query: "arquitetura de processadores ARM"),
            .init(spoken: "Você pode pesquisar sobre astrofísica?", query: "astrofísica?"),
            .init(spoken: "Por favor, pesquisa no Google sobre música brasileira", query: "música brasileira"),
            .init(spoken: "Sig, pesquise por C++", query: "C++"), .init(spoken: "GitHub", query: "GitHub", browser: false),
            .init(spoken: "Como funcionam os tokens do Claude?", query: "Como funcionam os tokens do Claude?", browser: false),
            .init(spoken: "arquiteturas de Mac", query: "arquiteturas de Mac", browser: false), .init(spoken: "meu Mac não liga", query: "meu Mac não liga", browser: false),
            .init(spoken: "Quanto custa um Mac?", query: "Quanto custa um Mac?", browser: false),
            .init(spoken: "arquiteturas que pausam processos", query: "arquiteturas que pausam processos", browser: false),
            .init(spoken: "Quero que você pesquise sobre saúde e agenda", query: "saúde e agenda"),
            .init(spoken: "Can you search for como não parar o timer", query: "como não parar o timer"),
            .init(spoken: "look up notícias de Recife", query: "notícias de Recife"),
            .init(spoken: "Como pausar o timer no Mac?", query: "Como pausar o timer no Mac?", browser: false),
            .init(spoken: "Como não perder o foco?", query: "Como não perder o foco?", browser: false),
            .init(spoken: "Quem criou o Swift?", query: "Quem criou o Swift?", browser: false),
            .init(spoken: "What is new in Swift?", query: "What is new in Swift?", browser: false)
        ]
        @Test("G04.02 · Questions stay local and only explicit searches open a browser", arguments: searches)
        func searchTopics(_ example: SearchExample) {
            let expected: FocusVoiceCommand = example.browser ? .search(query: example.query) : .ask(question: example.query)
            #expect(FocusVoiceParser.parse(example.spoken) == expected)
        }
        @Test("G04.02 · Portuguese search verbs", arguments: ["pesquisa", "pesquise", "pesquisar", "procura", "procure", "buscar", "busca", "busque", "faça uma pesquisa"])
        func searchVerbs(_ verb: String) {
            #expect(FocusVoiceParser.parse(verb + " no Google sobre C++ & café") == .search(query: "C++ & café"))
        }
        @Test("G04.02 · Unsupported, negated, compound and unsafe input", arguments: [
            "envie um email", "...", "Não pesquise receitas", "Não quero que você pesquise no Google sobre saúde",
            "Don't search for music", "search for start focus\nbad", "Como iniciar foco\nbad",
            "pesquise start focus " + String(repeating: "a", count: 2_001), "Open Safari and search YouTube",
            "Open Safari; rm -rf something", "Não abra o WhatsApp", "Show AI limits and start focus", "Don't show my AI limits"
        ])
        func rejectedIntent(_ phrase: String) { #expect(FocusVoiceParser.parse(phrase) == nil) }

        @Test("G04.02 · App and AI limit intents") func localIntents() {
            #expect(FocusVoiceParser.parse("Open Warp") == .openApp(name: "warp"))
            #expect(FocusVoiceParser.parse("Abra o WhatsApp") == .openApp(name: "whatsapp"))
            #expect(FocusVoiceParser.parse("Open Safari") == .openApp(name: "safari"))
            #expect(FocusVoiceParser.parse("Open Sieghart") == .show)
            for phrase in ["What is my ai limits", "What are my AI limits?", "Mostre meus limites do Codex"] {
                #expect(FocusVoiceParser.parse(phrase) == .aiLimits)
            }
        }
        @Test("G04.02 · Search URL escapes literal text and rejects invalid bounds") func urlEncoding() throws {
            let query = "C++ & café #5; $(touch /tmp/nope)"
            let search = try #require(BrowserSearch.url(for: query))
            #expect(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == query)
            #expect(search.absoluteString.contains("C%2B%2B"))
            #expect(search.host == "www.google.com" && search.path == "/search" && search.scheme == "https")
            #expect(BrowserSearch.url(for: String(repeating: "á", count: 1_000)) != nil)
            #expect(BrowserSearch.url(for: String(repeating: "a", count: 2_001)) == nil)
            #expect(BrowserSearch.url(for: "a\nb") == nil)
        }
    }

    @Suite(.tags(.logic, .interactions)) struct ModifierShortcutTests {
        @Test("G04.03 · Modifier release fires once and typing suppresses activation") func releases() {
            var tracker = ModifierShortcutTracker()
            tracker.keyPressed()
            let accepted1 = tracker.update(.option) == nil
            #expect(accepted1)
            let accepted2 = tracker.update([.option, .command]) == nil
            #expect(accepted2)
            let accepted3 = tracker.update(.command) == nil
            #expect(accepted3)
            let accepted4 = tracker.update([]) == ShortcutChord.legacyVoice.modifiers
            #expect(accepted4)
            let accepted5 = tracker.update([]) == nil
            #expect(accepted5)
            _ = tracker.update([.option, .command]); tracker.keyPressed()
            let accepted6 = tracker.update([]) == nil
            #expect(accepted6)
            _ = tracker.update([.option, .command, .shift])
            let accepted7 = tracker.update([]) != ShortcutChord.legacyVoice.modifiers
            #expect(accepted7)
        }
    }
    @Suite(.tags(.logic, .interactions)) struct ShortcutDeliveryTests {
        @Test("G04.14 · Monitor/Carbon deduplicate regardless of timestamp order") func delivery() {
            var gate = ShortcutDeliveryGate()
            let accepted8 = gate.accept(.companion, source: .monitor, at: 90.01)
            #expect(accepted8)
            let accepted9 = !gate.accept(.companion, source: .carbon, at: 90)
            #expect(accepted9)
            let accepted10 = gate.accept(.voice, source: .monitor, at: 1)
            #expect(accepted10)
            let accepted11 = !gate.accept(.voice, source: .carbon, at: 1.01)
            #expect(accepted11)
            let accepted12 = gate.accept(.voice, source: .monitor, at: 1.1)
            #expect(accepted12)
            let accepted13 = gate.accept(.companion, source: .carbon, at: 1.1)
            #expect(accepted13)
            #expect(ShortcutChord.companion.matches(keyCode: 1, flags: [.control, .option]))
            #expect(!ShortcutChord.companion.matches(keyCode: 1, flags: [.control, .option, .command]))
        }
    }
    @Suite(.tags(.logic, .interactions)) struct IslandGeometryTests {
        @Test("G04.05 · Negative-origin display coverage and overlay level") func coverage() {
            let display = CGRect(x: -1440, y: 0, width: 1440, height: 900)
            #expect(NotchOverlayPolicy.coversDisplay(display, display: display))
            #expect(!NotchOverlayPolicy.coversDisplay(CGRect(x: 0, y: 0, width: 1440, height: 900), display: display))
            #expect(!NotchOverlayPolicy.coversDisplay(CGRect(x: -1440, y: 24, width: 1440, height: 876), display: display))
            #expect(!NotchOverlayPolicy.coversDisplay(.zero, display: display))
            #expect(NotchOverlayPolicy.level(fullScreen: true) == .screenSaver)
            #expect(NotchOverlayPolicy.level(fullScreen: false).rawValue > NSWindow.Level.statusBar.rawValue)
        }
        @Test("G04.05 · Compact notch height") func compactHeight() {
            let compact = NotchGeometry(width: 328, cutoutWidth: 180, cutoutHeight: 32, compact: true)
            #expect(compact.height == 32 && compact.contentTop == 0)
            #expect(compact.width > compact.cutoutWidth)
        }
        @MainActor @Test("G04.05 · Interrupted contour retains presentation size") func interruptedContour() {
            let contour = IslandWindowCanvas<Text>.path(size: CGSize(width: 357.2, height: 94.8), canvasWidth: 800)
            let current = IslandWindowCanvas<Text>.visibleSize(path: contour, fallback: CGSize(width: 760, height: 400))
            #expect(abs(current.width - 357.2) < 0.001 && abs(current.height - 94.8) < 0.001)
        }
    }
}
