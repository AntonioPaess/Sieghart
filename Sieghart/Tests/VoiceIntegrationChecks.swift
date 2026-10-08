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
    init() {
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
            }, voiceCapture: capture, voiceNow: { [weak self] in self?.time ?? 0 })
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
        f.recognize("Search for incomplete command")
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
        print("PASS: capture → quiet/final drain → parser → Google/app/timer; pinned voice UI; exact-once/trailing words; cancellation/replacement; timeout/input loss; permission cancellation")
    }
}
