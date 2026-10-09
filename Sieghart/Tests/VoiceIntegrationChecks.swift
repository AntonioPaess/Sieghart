import AppKit
import Foundation

@MainActor private final class FixtureVoiceCapture: VoiceCapturing {
    var receivers: [@MainActor (VoiceCaptureEvent) -> Void] = []
    var finishCount = 0
    var cancelCount = 0
    var finishResult: String?
    var accessError: Error?
    var startError: Error?
    var holdsAccess = false
    var accessContinuation: CheckedContinuation<Void, any Error>?
    func prepareAccess() async throws {
        if let accessError { throw accessError }
        if holdsAccess { try await withCheckedThrowingContinuation { accessContinuation = $0 } }
    }
    func start(language: String, receive: @escaping @MainActor (VoiceCaptureEvent) -> Void) throws {
        if let startError { throw startError }
        receivers.append(receive)
    }
    func finish() {
        finishCount += 1
        if let finishResult { emit(.recognition(text: finishResult, final: true)) }
    }
    func cancel() { cancelCount += 1 }
    func emit(_ event: VoiceCaptureEvent, from index: Int? = nil) { receivers[index ?? receivers.count - 1](event) }
}

@MainActor private final class VoiceFixture {
    let suite = "Sieghart.VoiceIntegration.\(UUID().uuidString)"
    let defaults: UserDefaults
    let capture = FixtureVoiceCapture()
    let assistant: AssistantViewModel
    let notch: NotchWidgetViewModel
    var controller: ActivationController!
    var time = 0.0
    var queries: [String] = []
    var urls: [URL] = []
    var apps: [String] = []
    init(minimumProcessingDuration: Duration = .zero) {
        defaults = UserDefaults(suiteName: suite)!
        assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let preferences = CompanionPreferences(defaults: defaults)
        notch = NotchWidgetViewModel(assistant: assistant, preferences: preferences, managesWindows: false,
                                    pointerExitDelay: .milliseconds(20), keyboardRevealDelay: .milliseconds(40))
        controller = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false,
            openApplication: { [weak self] name in self?.apps.append(name); return name },
            searchBrowser: { [weak self] query in
                guard let url = BrowserSearch.url(for: query) else { throw VoiceCaptureFailure.unavailable }
                self?.queries.append(query); self?.urls.append(url); return query
            }, voiceCapture: capture, voiceNow: { [weak self] in self?.time ?? 0 }, minimumVoiceProcessingDuration: minimumProcessingDuration)
        notch.activation = controller
    }
    func cleanup() { controller.cancelVoiceCommand(); defaults.removePersistentDomain(forName: suite) }
    func start() async throws {
        controller.toggleListening()
        try await Task.sleep(for: .milliseconds(10))
        precondition(controller.isListening && controller.isVoiceBusy && !controller.isPreparing)
        precondition(notch.isVisible && notch.presentation == .home)
    }
    func level(_ decibels: Double, at time: Double) {
        self.time = time
        capture.emit(.level(SpeechAudioLevel(decibels: decibels, duration: 0.1, time: time)))
    }
    func recognize(_ text: String, final: Bool = false) { capture.emit(.recognition(text: text, final: final)) }
}

@main struct VoiceIntegrationChecks {
    @MainActor static func main() async throws {
        let f = VoiceFixture()
        defer { f.cleanup() }
        try await f.start()
        f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
        try await Task.sleep(for: .milliseconds(80)) // Exceeds both approach/exit allowances.
        precondition(f.notch.isVisible && f.notch.presentation == .home && f.controller.isListening,
                     "The expanded Companion must stay visible while listening, with the mouse elsewhere")
        for tick in 1...10 { f.level(-42, at: Double(tick) / 10) }
        f.recognize("Pesquise por ChatGPT no Google")
        for tick in 11...25 { f.level(-20, at: Double(tick) / 10) }
        for tick in 26...41 { f.level(-42, at: Double(tick) / 10) }
        precondition(!f.controller.isListening && f.controller.isFinalizing && f.capture.finishCount == 1)
        precondition(f.queries.isEmpty, "A partial must not execute before the recognizer drains")
        f.notch.collapseAfterPointerExit()
        precondition(f.notch.presentation == .home && f.notch.isVisible, "Finalization also stays visible")
        // Last words arrive after capture stops. The real parser and URL builder
        // run, but the browser launch itself is injected and never opens a tab.
        let final = "Pesquise no Google por ChatGPT API + Swift"
        f.recognize(final, final: true)
        f.recognize(final, final: true) // Duplicate/stale callback.
        try await Task.sleep(for: .milliseconds(10))
        precondition(!f.controller.isVoiceBusy && f.controller.commandAcknowledged)
        precondition(f.controller.companionVoicePhase == .success)
        precondition(f.queries == ["ChatGPT API + Swift"] && f.urls.count == 1)
        let parts = URLComponents(url: f.urls[0], resolvingAgainstBaseURL: false)!
        precondition(parts.host == "www.google.com" && parts.queryItems?.first?.value == "ChatGPT API + Swift")
        // Once listening is complete, ordinary pointer departure resumes.
        f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
        try await Task.sleep(for: .milliseconds(60))
        precondition(f.notch.presentation == .island)
        f.controller.cancelVoiceCommand()

        // Authoritative isFinal arrives while the microphone is still loud.
        f.time = 10; try await f.start()
        f.level(-20, at: 10.1)
        f.recognize("Open Safari", final: true)
        precondition(f.controller.isExecutingVoiceCommand && f.controller.companionVoicePhase == .working)
        try await Task.sleep(for: .milliseconds(10))
        precondition(f.apps == ["safari"] && !f.controller.isVoiceBusy)
        precondition(f.capture.finishCount == 2)
        f.controller.cancelVoiceCommand()

        // A capture adapter can deliver final recognition from finish itself.
        // This must not overwrite the action's acknowledgement or double-run it.
        f.time = 20; try await f.start()
        f.capture.finishResult = "Search for café & Swift"
        f.recognize("Search for café")
        f.controller.finishListening()
        try await Task.sleep(for: .milliseconds(10))
        precondition(f.controller.voiceStatus == "Search opened · café & Swift")
        precondition(f.queries == ["ChatGPT API + Swift", "café & Swift"])
        f.capture.finishResult = nil
        f.controller.cancelVoiceCommand()

        // Cancel during finalization; a delayed old final may not execute or
        // change the replacement's text/state, even after the next start.
        f.time = 30; try await f.start()
        f.recognize("Search for cancelled command")
        f.controller.finishListening()
        let oldIndex = f.capture.receivers.count - 1
        f.controller.cancelVoiceCommand()
        f.time = 40; try await f.start()
        f.capture.emit(.recognition(text: "Search for cancelled command", final: true), from: oldIndex)
        precondition(f.controller.isListening && f.controller.transcript.isEmpty)
        f.recognize("Start focus for 20 minutes", final: true)
        precondition(f.assistant.focusMinutes == 20 && f.assistant.hasActiveSession)
        precondition(f.queries.count == 2)
        f.controller.cancelVoiceCommand()
        f.assistant.resetPomodoro()

        f.time = 50; try await f.start()
        f.recognize("Start focus for 40 minutes")
        f.controller.finishListening()
        f.time = 54.1
        try await Task.sleep(for: .milliseconds(120)) // Poll tests the real final-drain timeout.
        precondition(!f.controller.isVoiceBusy && !f.controller.commandAcknowledged && f.queries.count == 2)
        precondition(f.controller.voiceStatus.contains("nothing was run"))
        f.controller.cancelVoiceCommand()

        f.time = 60; try await f.start()
        f.recognize("Search for interrupted command")
        f.capture.emit(.inputChanged)
        precondition(!f.controller.isVoiceBusy && f.controller.voiceStatus.contains("Microphone changed"))
        f.capture.emit(.recognition(text: "Search for interrupted command", final: true))
        precondition(f.queries.count == 2)
        f.controller.cancelVoiceCommand()

        // A denied permission and a cancelled outstanding permission request
        // must never start capture. Pin covers permission preparation too.
        f.capture.accessError = VoiceCaptureFailure.microphoneAccess
        let starts = f.capture.receivers.count
        f.controller.toggleListening()
        try await Task.sleep(for: .milliseconds(10))
        precondition(!f.controller.isVoiceBusy && f.controller.voiceStatus.contains("Allow microphone"))
        precondition(f.capture.receivers.count == starts)
        f.controller.cancelVoiceCommand(); f.capture.accessError = nil
        f.capture.holdsAccess = true
        f.controller.toggleListening()
        try await Task.sleep(for: .milliseconds(80))
        precondition(f.controller.isPreparing && f.notch.isVisible && f.notch.presentation == .home)
        f.controller.cancelVoiceCommand()
        f.capture.accessContinuation?.resume()
        try await Task.sleep(for: .milliseconds(10))
        precondition(f.capture.receivers.count == starts && !f.controller.isVoiceBusy)
        f.capture.holdsAccess = false
        f.controller.cancelVoiceCommand()
        // Exact user reproductions, through audio endpoint and production
        // dispatch. Also cover the framework stopping without isFinal.
        for (index, pair) in [
            ("pesquise por arquiteturas de mac", "arquiteturas de mac"),
            ("pesquisa github", "github"),
            ("GitHub", "GitHub"),
            ("meu Mac não liga", "meu Mac não liga"),
            ("procure astrofísica e buracos negros", "astrofísica e buracos negros")
        ].enumerated() {
            let base = 100.0 + Double(index) * 10
            f.time = base; try await f.start()
            precondition(f.controller.companionVoicePhase == .listening)
            f.level(-65, at: base + 0.1)
            f.recognize(pair.0)
            for tick in 2...10 { f.level(-20, at: base + Double(tick) / 10) }
            for tick in 11...26 { f.level(-65, at: base + Double(tick) / 10) }
            precondition(f.controller.isFinalizing && f.controller.companionVoicePhase == .thinking)
            let count = f.queries.count
            if index == 1 {
                f.capture.emit(.failure("fixture: recognizer stopped without final result"))
                precondition(f.controller.isFinalizing && f.queries.count == count)
                f.time = base + 6.5
                try await Task.sleep(for: .milliseconds(120))
            } else { f.recognize(pair.0, final: true); try await Task.sleep(for: .milliseconds(10)) }
            precondition(f.queries.count == count + 1 && f.queries.last == pair.1, pair.0)
            precondition(f.controller.commandAcknowledged && !f.controller.isVoiceBusy)
            f.controller.cancelVoiceCommand()
        }
        // Spoken Portuguese timer verbs must execute a timer, never a search.
        // Duration is the session length; wait for the recognizer's final text
        // so a partial default-duration command cannot start prematurely.
        for (index, pair) in [
            ("inicia o foco", 25),
            ("inicia o pomodoro", 25),
            ("inicia o pomodor em 20 minutos", 20),
            ("inicia o pomodoro em vinte e cinco minutos", 25),
            ("Sig, inicie o foco por 40 minutos", 40)
        ].enumerated() {
            f.assistant.resetPomodoro()
            f.assistant.setFocusMinutes(25)
            let base = 200.0 + Double(index) * 10
            f.time = base; try await f.start()
            let queryCount = f.queries.count
            let completed = f.assistant.completedSessions
            f.level(-65, at: base + 0.1)
            f.recognize("inicia o foco")
            for tick in 2...10 { f.level(-20, at: base + Double(tick) / 10) }
            for tick in 11...26 { f.level(-65, at: base + Double(tick) / 10) }
            precondition(f.controller.isFinalizing && !f.assistant.hasActiveSession)
            f.recognize(pair.0, final: true)
            f.recognize(pair.0, final: true)
            precondition(f.assistant.isRunning && f.assistant.focusMinutes == pair.1, pair.0)
            precondition(f.assistant.activeTimerMode == .pomodoro && f.assistant.interval == .focus)
            precondition(f.assistant.remainingSeconds == Double(pair.1 * 60))
            precondition(f.assistant.completedSessions == completed && f.queries.count == queryCount)
            precondition(f.controller.commandAcknowledged && !f.controller.isVoiceBusy)
            f.controller.cancelVoiceCommand()
        }
        f.assistant.resetPomodoro()
        // Production timing: even instant commands have a visible cue. The
        // operation itself is not delayed, and idle never reports loading.
        let paced = VoiceFixture(minimumProcessingDuration: .milliseconds(700))
        defer { paced.cleanup() }
        precondition(paced.controller.companionVoicePhase == .inactive && !paced.controller.isVoiceBusy)
        paced.controller.executeVoiceCommand("inicia o foco em 20 minutos")
        precondition(paced.assistant.isRunning && paced.assistant.focusMinutes == 20)
        precondition(!paced.controller.isExecutingVoiceCommand && paced.controller.isPresentingVoiceProcessing)
        precondition(paced.controller.companionVoicePhase == .working && !paced.controller.commandAcknowledged)
        paced.notch.setPointerInsidePanel(true); paced.notch.setPointerInsidePanel(false)
        try await Task.sleep(for: .milliseconds(100))
        precondition(paced.controller.companionVoicePhase == .working && paced.notch.presentation == .home)
        try await Task.sleep(for: .milliseconds(660))
        precondition(paced.controller.companionVoicePhase == .success && !paced.controller.isVoiceBusy)
        paced.controller.cancelVoiceCommand()
        precondition(paced.controller.companionVoicePhase == .inactive && !paced.controller.isPresentingVoiceProcessing)
        paced.assistant.resetPomodoro()

        paced.controller.executeVoiceCommand("pesquisa github")
        try await Task.sleep(for: .milliseconds(30))
        precondition(paced.queries == ["github"] && paced.controller.isPresentingVoiceProcessing,
                     "The browser action happens immediately while visual acknowledgement is paced")
        paced.controller.cancelVoiceCommand()
        try await Task.sleep(for: .milliseconds(730))
        precondition(paced.controller.companionVoicePhase == .inactive && !paced.controller.commandAcknowledged)
        precondition(!paced.notch.isVisible && paced.queries.count == 1)

        paced.controller.executeVoiceCommand("inicia o foco")
        try await Task.sleep(for: .milliseconds(100))
        paced.controller.executeVoiceCommand("pause the timer")
        try await Task.sleep(for: .milliseconds(350))
        precondition(paced.controller.companionVoicePhase == .working && !paced.controller.commandAcknowledged,
                     "An old completion must not interrupt the replacement's cue")
        try await Task.sleep(for: .milliseconds(400))
        precondition(paced.controller.companionVoicePhase == .success && paced.controller.voiceStatus == "Timer paused")
        paced.controller.cancelVoiceCommand()
        print("PASS: capture → quiet/final drain → parser → Google/app/timer; Portuguese focus/Pomodoro verbs and duration; minimum visible processing without delayed actions; idle/cancel/replacement; pinned voice UI; exact-once/trailing words; search topics and missing-final search recovery; strict tool finalization; voice phases; timeout/input loss; permission cancellation")
    }
}
