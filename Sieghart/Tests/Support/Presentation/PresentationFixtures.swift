import AppKit
import CoreAudio
import Foundation
import Testing

/// Conditions synchronize delivery; durations below are only an upper failure bound.
@MainActor enum PresentationWait {
    static func until(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(3),
                      sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        try #require(condition(), "Presentation did not reach the expected state before its deadline", sourceLocation: sourceLocation)
    }

    /// Used only for contracts that promise no transition during a grace interval.
    static func stays(_ condition: @MainActor () -> Bool, for duration: Duration,
                      sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: duration)
        repeat {
            try #require(condition(), "Presentation changed inside its protected interval", sourceLocation: sourceLocation)
            try await Task.sleep(for: .milliseconds(2))
        } while clock.now < deadline
        #expect(condition(), sourceLocation: sourceLocation)
    }
}

@MainActor final class PresentationClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    var voiceTime = 0.0
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor final class PresentationVoiceCapture: VoiceCapturing {
    private(set) var receivers: [@MainActor (VoiceCaptureEvent) -> Void] = []
    private(set) var finishCount = 0
    private(set) var cancelCount = 0
    var finishResult: String?
    var accessError: Error?
    var startError: Error?
    var holdsAccess = false
    private(set) var accessEntered = false
    private(set) var accessCompleted = false
    private var accessContinuation: CheckedContinuation<Void, any Error>?

    func prepareAccess() async throws {
        accessEntered = true
        if let accessError { throw accessError }
        if holdsAccess { try await withCheckedThrowingContinuation { accessContinuation = $0 } }
        accessCompleted = true
    }
    func releaseAccess() {
        let pending = accessContinuation; accessContinuation = nil
        pending?.resume()
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
    func emit(_ event: VoiceCaptureEvent, from index: Int? = nil) {
        guard let receiver = (index ?? receivers.indices.last).flatMap({ receivers.indices.contains($0) ? receivers[$0] : nil }) else {
            Issue.record("Synthetic voice event had no matching capture session")
            return
        }
        receiver(event)
    }
}

@MainActor private final class PresentationAudioBackend: AudioBackend {
    func snapshot() -> AudioSnapshot { AudioSnapshot() }
    func prepareApplicationAudio() async throws { Issue.record("Presentation fixture must not request audio access") }
    func setVolume(_ value: Float, device: AudioObjectID, input: Bool) throws { Issue.record("Unexpected audio write") }
    func setDefault(_ device: AudioObjectID, input: Bool) throws { Issue.record("Unexpected audio device write") }
    func setInputMuted(_ muted: Bool, device: AudioObjectID) throws { Issue.record("Unexpected microphone write") }
    func setApplication(_ app: AudioApplicationInfo, gain: Float, output: AudioDeviceInfo) throws { Issue.record("Unexpected audio route") }
    func retainApplications(_ ids: Set<String>) {}
    func stopApplications() {}
}
@MainActor private final class PresentationSampler: SystemSampling {
    func read() -> MonitorReading { Issue.record("Presentation fixture must not sample hardware"); return MonitorReading() }
}
@MainActor private final class PresentationAwakeBackend: AwakeBackend {
    func context() -> AwakeContext { AwakeContext() }
    func acquire(display: Bool) throws -> UInt32 { Issue.record("Unexpected power assertion"); return 1 }
    func release(_ token: UInt32) {}
}
@MainActor private final class PresentationDisplayBackend: DisplayPowerBackend {
    func displays() -> [DisplayInfo] { [] }
    func brightness(_ value: Double, display: CGDirectDisplayID) throws { Issue.record("Unexpected display brightness write") }
    func dim(_ value: Double, display: CGDirectDisplayID) throws { Issue.record("Unexpected display dimming") }
    func restore() {}
    func sleepDisplays() throws { Issue.record("Unexpected display sleep") }
    func connectedBluetooth() -> [String] { [] }
    func disconnectBluetooth(_ id: String) throws { Issue.record("Unexpected Bluetooth disconnection") }
    func reconnectBluetooth(_ id: String) throws { Issue.record("Unexpected Bluetooth reconnection") }
}
@MainActor private final class PresentationClipboard: ClipboardAccess {
    func read(after previous: Int?, includeMedia: Bool) async -> ClipboardRead? { Issue.record("Presentation fixture must not read clipboard"); return nil }
    func write(_ payload: ClipboardPayload) async -> Int? { Issue.record("Presentation fixture must not write clipboard"); return nil }
}
private actor PresentationClipboardStorage: ClipboardStorage {
    func load() -> [ClipboardEntry] { [] }
    func save(_ entries: [ClipboardEntry], revision: UInt64) {}
}

/// Each case owns all state and all adapters, including dependencies not directly exercised.
@MainActor final class PresentationFixture {
    let store: TestDefaults
    private let ownsStore: Bool
    var defaults: UserDefaults { store.value }
    let clock = PresentationClock()
    let capture = PresentationVoiceCapture()
    let lifecycle = NotificationCenter()
    let assistant: AssistantViewModel
    let preferences: CompanionPreferences
    let notch: NotchWidgetViewModel
    private(set) var controller: ActivationController?
    private(set) var queries: [String] = []
    private(set) var urls: [URL] = []
    private(set) var apps: [String] = []

    init(minimumProcessingDuration: Duration = .zero, announcementDelay: Duration = .milliseconds(90),
         pointerExitDelay: Duration = .milliseconds(40), keyboardRevealDelay: Duration = .milliseconds(100),
         observesShortcutLifecycle: Bool = false, defaultsFixture: TestDefaults? = nil,
         events: CompanionEventCenter? = nil, files: FilesViewModel? = nil, capture: CaptureViewModel? = nil,
         fileReception: FileReceptionViewModel? = nil, agentRoom: AgentRoomViewModel? = nil,
         createActivation: Bool = true) throws {
        store = try defaultsFixture ?? TestDefaults()
        ownsStore = defaultsFixture == nil
        let defaults = store.value, clock = self.clock
        assistant = AssistantViewModel(defaults: defaults, now: { clock.date }, schedulesTimer: false)
        preferences = CompanionPreferences(defaults: defaults)
        notch = NotchWidgetViewModel(assistant: assistant, preferences: preferences,
            audio: AudioViewModel(backend: PresentationAudioBackend(), defaults: defaults),
            monitor: SystemMonitorViewModel(backend: PresentationSampler()),
            keepAwake: KeepAwakeViewModel(backend: PresentationAwakeBackend(), defaults: defaults, now: { clock.date }),
            displayPower: DisplayPowerViewModel(backend: PresentationDisplayBackend(), defaults: defaults),
            clipboard: ClipboardViewModel(defaults: defaults, access: PresentationClipboard(), storage: PresentationClipboardStorage(),
                monitorsSystem: false, now: { clock.date }, bootTime: { 100 }),
            calendar: IsolatedCalendarFixture.make(defaults: defaults), events: events, files: files, capture: capture,
            fileReception: fileReception, agentRoom: agentRoom, managesWindows: false,
            announcementDelay: announcementDelay, pointerExitDelay: pointerExitDelay, keyboardRevealDelay: keyboardRevealDelay)
        guard createActivation else { return }
        controller = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false,
            lifecycleNotifications: observesShortcutLifecycle ? lifecycle : nil,
            openApplication: { [weak self] name in self?.apps.append(name); return "Fixture " + name },
            searchBrowser: { [weak self] query in
                let url = try #require(BrowserSearch.url(for: query))
                self?.queries.append(query); self?.urls.append(url); return "Fixture " + query
            }, voiceCapture: self.capture, voiceNow: { clock.voiceTime }, minimumVoiceProcessingDuration: minimumProcessingDuration,
            activeBundleID: { "fixture.frontmost" })
        notch.activation = controller
    }

    func activation() throws -> ActivationController { try #require(controller) }
    func startVoice() async throws {
        let controller = try activation()
        controller.toggleListening()
        try await PresentationWait.until { controller.isListening && !controller.isPreparing }
        #expect(controller.isVoiceBusy)
        #expect(notch.isVisible && notch.presentation == .home)
    }
    func level(_ decibels: Double, at time: Double) {
        clock.voiceTime = time
        capture.emit(.level(SpeechAudioLevel(decibels: decibels, duration: 0.1, time: time)))
    }
    func recognize(_ text: String, final: Bool = false) { capture.emit(.recognition(text: text, final: final)) }
    func speakAndFallQuiet(partial: String, base: Double = 0) {
        level(-65, at: base + 0.1); recognize(partial)
        for tick in 2...10 { level(-20, at: base + Double(tick) / 10) }
        for tick in 11...26 { level(-65, at: base + Double(tick) / 10) }
    }
    func cleanup() {
        controller?.shutdown()
        capture.releaseAccess()
        notch.activation = nil
        notch.hide()
        notch.stopUtilities()
        controller = nil
        assistant.resetPomodoro(); assistant.utilityClock.reset()
        if ownsStore { store.cleanup() }
    }
}
