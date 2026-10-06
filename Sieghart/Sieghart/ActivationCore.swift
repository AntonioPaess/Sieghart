import AppKit
import AVFoundation
import Carbon
import Speech

@MainActor
final class ActivationController: ObservableObject {
    static var activeHotkeyOwner: ActivationController?
    @Published private(set) var companionShortcut: ShortcutChord?
    @Published private(set) var voiceShortcut: ShortcutChord?
    @Published var recordingShortcut: ShortcutAction? {
        didSet { modifierTracker.reset(); if registersShortcuts { registerHotkeys() } }
    }
    @Published private(set) var shortcutStatus = ""
    @Published private(set) var voiceShortcutStatus = ""
    @Published private(set) var needsShortcutPermission = false
    @Published private(set) var lastShortcutActivation: Date?
    @Published private(set) var voiceStatus = "Voice is off"
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isPreparing = false
    @Published private(set) var commandAcknowledged = false
    @Published var voiceLanguage: String {
        didSet { defaults.set(voiceLanguage, forKey: "activation.voiceLanguage"); cancelVoiceCommand() }
    }
    private var voiceRequestGeneration = 0
    private let defaults: UserDefaults
    private let registersShortcuts: Bool
    private let assistant: AssistantViewModel
    private let notch: NotchWidgetController
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var shortcutRecoveryTask: Task<Void, Never>?
    private var shortcutHealthTask: Task<Void, Never>?
    private var lastShortcutTrust = false
    private var lastSecureInput = false
    private var registrationNeedsRetry = false
    private var modifierTracker = ModifierShortcutTracker()
    private let audioEngine = AVAudioEngine()
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var audioFeed: SpeechAudioFeed?
    private var speechTask: SFSpeechRecognitionTask?
    private var stopTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?

    init(assistant: AssistantViewModel, notch: NotchWidgetController, defaults: UserDefaults = .standard, registersShortcuts: Bool = true, lifecycleNotifications: NotificationCenter? = nil) {
        self.assistant = assistant
        self.notch = notch
        self.defaults = defaults
        self.registersShortcuts = registersShortcuts
        func saved(_ action: ShortcutAction, fallback: ShortcutChord) -> ShortcutChord? {
            if defaults.bool(forKey: "activation.\(action.rawValue).disabled") { return nil }
            if let data = defaults.data(forKey: "activation.\(action.rawValue).chord"), let chord = try? JSONDecoder().decode(ShortcutChord.self, from: data) { return chord }
            if action == .companion, defaults.string(forKey: "activation.hotkey") == "Off" { return nil }
            if action == .companion, let legacy = defaults.string(forKey: "activation.hotkey") {
                let codes: [String: UInt32] = ["S": 1, "D": 2, "F": 3, "G": 5, "H": 4, "J": 38, "K": 40, "L": 37, "P": 35, "V": 9, "Space": 49]
                if let code = codes[legacy] { return ShortcutChord(keyCode: code, modifiers: ShortcutChord.companion.modifiers, keyLabel: legacy) }
            }
            return fallback
        }
        companionShortcut = saved(.companion, fallback: .companion)
        voiceShortcut = saved(.voice, fallback: .voice)
        voiceLanguage = defaults.string(forKey: "activation.voiceLanguage") ?? "en_US"
        if registersShortcuts {
            registerHotkeys()
        }
        if registersShortcuts || lifecycleNotifications != nil { observeShortcutLifecycle(workspace: lifecycleNotifications) }
    }

    func cancelShortcutRecording(for action: ShortcutAction) {
        guard recordingShortcut == action else { return }
        recordingShortcut = nil
    }

    // Leaving a recorder must restore activation even if no chord was captured.
    func recoverShortcuts() {
        modifierTracker.reset()
        if recordingShortcut != nil { recordingShortcut = nil }
        else if registersShortcuts { registerHotkeys() }
    }

    private func observeShortcutLifecycle(workspace suppliedWorkspace: NotificationCenter?) {
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            appObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleShortcutRecovery() }
            })
        }
        let workspace = suppliedWorkspace ?? NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleShortcutRecovery() }
            })
        }
        guard registersShortcuts else { return }
        shortcutHealthTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.checkShortcutHealth()
            }
        }
    }

    private func scheduleShortcutRecovery() {
        modifierTracker.reset()
        if recordingShortcut != nil { recordingShortcut = nil }
        shortcutRecoveryTask?.cancel()
        shortcutRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.recordingShortcut == nil else { return }
            self.recoverShortcuts()
        }
    }

    private func checkShortcutHealth() {
        guard recordingShortcut == nil else { return }
        let trusted = AXIsProcessTrusted()
        let secureInput = IsSecureEventInputEnabled()
        // A release can be lost while the system protects keyboard input.
        if NSEvent.modifierFlags.intersection(ShortcutChord.allowedModifiers).isEmpty { modifierTracker.reset() }
        if trusted != lastShortcutTrust || secureInput != lastSecureInput || registrationNeedsRetry {
            registerHotkeys()
        }
    }

    func shortcut(for action: ShortcutAction) -> ShortcutChord? { action == .voice ? voiceShortcut : companionShortcut }

    func setShortcut(_ chord: ShortcutChord?, for action: ShortcutAction) {
        recordingShortcut = nil
        if let chord, let other = shortcut(for: action == .voice ? .companion : .voice), chord.keyCode == other.keyCode, chord.modifiers == other.modifiers {
            if action == .voice { voiceShortcutStatus = "Already used to reveal the companion" }
            else { shortcutStatus = "Already used for voice" }
            return
        }
        if action == .voice { voiceShortcut = chord } else { companionShortcut = chord }
        defaults.set(chord == nil, forKey: "activation.\(action.rawValue).disabled")
        if let chord, let data = try? JSONEncoder().encode(chord) { defaults.set(data, forKey: "activation.\(action.rawValue).chord") }
        else { defaults.removeObject(forKey: "activation.\(action.rawValue).chord") }
        if registersShortcuts { registerHotkeys() }
    }

    func enableModifierShortcuts() {
        // The C framework exports this immutable key as a mutable global.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        registerHotkeys()
    }

    private func registerHotkeys() {
        hotkeys.forEach { UnregisterEventHotKey($0) }; hotkeys = []
        if let handler { RemoveEventHandler(handler) }; handler = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        modifierTracker.reset()
        registrationNeedsRetry = false
        guard recordingShortcut == nil else { return }
        Self.activeHotkeyOwner = self
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let id = identifier.id
            if status == noErr, identifier.signature == 0x53494748, id == 1 || id == 2 {
                Task { @MainActor in ActivationController.activeHotkeyOwner?.performShortcut(id == 2 ? .voice : .companion) }
            }
            return noErr
        }, 1, &eventType, nil, &handler)
        let trusted = AXIsProcessTrusted()
        lastShortcutTrust = trusted
        lastSecureInput = IsSecureEventInputEnabled()
        needsShortcutPermission = !trusted && (voiceShortcut?.isModifierOnly == true || companionShortcut?.isModifierOnly == true)
        for (action, id) in [(ShortcutAction.companion, UInt32(1)), (.voice, UInt32(2))] {
            var statusText = "Shortcut off"
            if let chord = shortcut(for: action) {
                if let code = chord.keyCode {
                    var reference: EventHotKeyRef?
                    let status = installed == noErr ? RegisterEventHotKey(code, chord.carbonModifiers, EventHotKeyID(signature: 0x53494748, id: id), GetApplicationEventTarget(), 0, &reference) : installed
                    if status == noErr, let reference { hotkeys.append(reference); statusText = "\(chord.label) · Works in other apps" }
                    else { registrationNeedsRetry = true; statusText = "Shortcut unavailable; record another combination" }
                } else {
                    statusText = !trusted ? "\(chord.label) · Allow Accessibility to use in other apps" : lastSecureInput ? "\(chord.label) · Secure keyboard input is active" : "\(chord.label) · Press and release to activate"
                }
            }
            if action == .voice { voiceShortcutStatus = statusText } else { shortcutStatus = statusText }
        }
        guard voiceShortcut?.isModifierOnly == true || companionShortcut?.isModifierOnly == true else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.observeModifiers(event) }
            return event
        }
        if trusted {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.observeModifiers(event) }
            }
        }
        if localMonitor == nil || (trusted && globalMonitor == nil) {
            registrationNeedsRetry = true
            let status = "Keyboard monitoring unavailable; retrying automatically"
            if companionShortcut?.isModifierOnly == true { shortcutStatus = status }
            if voiceShortcut?.isModifierOnly == true { voiceShortcutStatus = status }
        }
    }

    private func observeModifiers(_ event: NSEvent) {
        guard recordingShortcut == nil else { modifierTracker.reset(); return }
        if event.type == .keyDown { modifierTracker.keyPressed(); return }
        if let modifiers = modifierTracker.update(event.modifierFlags) {
            for action in ShortcutAction.allCases {
                if let chord = shortcut(for: action), chord.isModifierOnly, chord.modifiers == modifiers { performShortcut(action) }
            }
        }
    }

    func performShortcut(_ action: ShortcutAction) {
        guard recordingShortcut == nil else { return }
        lastShortcutActivation = Date()
        if action == .voice { toggleListening() } else { notch.toggle() }
    }

    func toggleListening() {
        if isListening { finishListening(); return }
        if isPreparing { cancelVoiceCommand(); return }
        feedbackTask?.cancel()
        voiceRequestGeneration += 1
        let generation = voiceRequestGeneration
        isPreparing = true
        commandAcknowledged = false
        transcript = ""
        voiceStatus = "Checking microphone and speech access…"
        notch.showVoice()
        Task { await startListening(generation: generation) }
    }

    private func startListening(generation: Int) async {
        guard !isListening, generation == voiceRequestGeneration else { return }
        defer { if generation == voiceRequestGeneration { isPreparing = false } }
        let speechAccess = await SpeechAuthorizationBridge.request()
        guard generation == voiceRequestGeneration else { return }
        guard speechAccess == .authorized else { voiceStatus = "Allow speech recognition in System Settings"; return }
        let microphoneAccess = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == voiceRequestGeneration else { return }
        guard microphoneAccess else { voiceStatus = "Allow microphone access in System Settings"; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: voiceLanguage)), recognizer.isAvailable else { voiceStatus = "Speech recognition is unavailable"; return }
        speechTask?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer the local recognizer where supported, keeping the core timer independent of speech availability.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        speechRequest = request
        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { speechRequest = nil; voiceStatus = "No microphone input is available"; return }
        let feed = SpeechAudioFeed(request)
        audioFeed = feed
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in feed.append(buffer) }
        do { audioEngine.prepare(); try audioEngine.start() }
        catch {
            audioEngine.inputNode.removeTap(onBus: 0); feed.finish(); audioFeed = nil; speechRequest = nil
            voiceStatus = "Could not start microphone: \(error.localizedDescription)"
            return
        }
        isListening = true
        voiceStatus = "Listening — your command runs when you finish speaking"
        notch.showVoice()
        speechTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorMessage = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.isListening, generation == self.voiceRequestGeneration else { return }
                if let text {
                    let changed = text != self.transcript
                    self.transcript = text
                    if isFinal { self.finishListening() }
                    else if changed { self.scheduleSpeechEnd(generation: generation) }
                } else if let errorMessage {
                    if !self.transcript.isEmpty { self.finishListening() }
                    else { self.stopListening(); self.voiceStatus = "Speech recognition stopped: \(errorMessage)" }
                }
            }
        }
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.isListening, generation == self.voiceRequestGeneration else { return }
            self.finishListening()
        }
    }

    private func scheduleSpeechEnd(generation: Int) {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let self, self.isListening, generation == self.voiceRequestGeneration else { return }
            self.finishListening()
        }
    }

    func finishListening() {
        guard isListening else { return }
        let text = transcript
        stopListening()
        executeVoiceCommand(text)
    }

    func cancelVoiceCommand() {
        voiceRequestGeneration += 1
        isPreparing = false
        commandAcknowledged = false
        feedbackTask?.cancel()
        stopListening()
        voiceStatus = "Voice is off"
        notch.hide()
    }

    func stopListening() {
        settleTask?.cancel(); settleTask = nil
        stopTask?.cancel(); stopTask = nil
        guard isListening else { return }
        isListening = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFeed?.finish(); audioFeed = nil; speechRequest = nil
        speechTask?.cancel(); speechTask = nil
    }

    // Only local, reversible commands are executed by this intent parser.
    // Recognition text is never evaluated as code or an external instruction.
    func executeVoiceCommand(_ text: String) {
        feedbackTask?.cancel()
        commandAcknowledged = false
        guard let command = FocusVoiceParser.parse(text) else {
            voiceStatus = text.isEmpty ? "No speech heard. Try again." : "Try one focus command, such as “start focus for 25 minutes”."
            notch.showVoice()
            return
        }
        var succeeded = true
        switch command {
        case .start(let minutes):
            if let minutes { assistant.startFocusSession(minutes: minutes) }
            else if assistant.interval != .focus { assistant.startFocusSession() }
            else { assistant.startPomodoroFromGesture() }
            voiceStatus = "Focus started · \(assistant.focusMinutes) minutes"
        case .resume:
            if assistant.hasActiveSession { assistant.startPomodoroFromGesture(); voiceStatus = "Timer resumed" }
            else { voiceStatus = "No paused session to resume"; succeeded = false }
        case .pause:
            assistant.pausePomodoroFromGesture(); voiceStatus = assistant.hasActiveSession ? "Timer paused" : "No active timer to pause"
            succeeded = assistant.hasActiveSession
        case .finish:
            if assistant.hasActiveSession { assistant.finishPomodoroFromWidget(); voiceStatus = "Session finished"; commandAcknowledged = true; scheduleFeedback(closeWidget: false); return }
            voiceStatus = "No active session to finish"
            succeeded = false
        case .reset:
            assistant.resetPomodoro(); voiceStatus = "Timer reset"
        case .startBreak:
            assistant.startBreak(); voiceStatus = assistant.interval == .focus ? "Finish a focus session before starting its break" : "Break started"
            succeeded = assistant.interval != .focus
        case .show:
            voiceStatus = "Sieghart shown"; commandAcknowledged = true; notch.show(); scheduleFeedback(closeWidget: false); return
        case .hide:
            voiceStatus = "Sieghart tucked away"; notch.hide(); return
        case .configure:
            voiceStatus = "Choose your focus settings"; commandAcknowledged = true; notch.showFocusSetup(); scheduleFeedback(closeWidget: false); return
        case .aiLimits:
            voiceStatus = "Here are your AI limits"; commandAcknowledged = true; notch.showAILimits(); scheduleFeedback(closeWidget: false); return
        }
        commandAcknowledged = succeeded
        notch.showVoice()
        scheduleFeedback(closeWidget: true)
    }

    private func scheduleFeedback(closeWidget: Bool) {
        let generation = voiceRequestGeneration
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, generation == self.voiceRequestGeneration else { return }
            self.commandAcknowledged = false
            if closeWidget { self.notch.hide() }
        }
    }
}
