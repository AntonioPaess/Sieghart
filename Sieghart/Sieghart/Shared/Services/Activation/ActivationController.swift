import AppKit
import AVFoundation
import Carbon
import Speech

@MainActor
final class ActivationController: ObservableObject {
    static var activeHotkeyOwner: ActivationController?
    @Published private(set) var companionShortcut: ShortcutChord?
    @Published private(set) var voiceShortcut: ShortcutChord?
    @Published private(set) var clipboardShortcut: ShortcutChord?
    @Published private(set) var audioShortcuts: [ShortcutAction: ShortcutChord] = [:]
    @Published private(set) var audioShortcutStatuses: [ShortcutAction: String] = [:]
    @Published private(set) var clipboardShortcutStatus = ""
    @Published var recordingShortcut: ShortcutAction? {
        didSet { modifierTracker.reset(); if registersShortcuts && shortcutsStarted { registerHotkeys() } }
    }
    @Published private(set) var shortcutStatus = ""
    @Published private(set) var voiceShortcutStatus = ""
    @Published private(set) var needsShortcutPermission = false
    @Published private(set) var lastShortcutActivation: Date?
    @Published private(set) var lastShortcutSource = ""
    @Published private(set) var voiceStatus = "Voice is off"
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var isExecutingVoiceCommand = false
    var isVoiceBusy: Bool { isListening || isPreparing || isFinalizing || isExecutingVoiceCommand }
    var companionVoicePhase: CompanionVoicePhase {
        if isPreparing { return .preparing }
        if isListening { return .listening }
        if isFinalizing { return .thinking }
        if isExecutingVoiceCommand { return .working }
        if commandAcknowledged { return .success }
        return voicePresented ? .failure : .inactive
    }
    @Published private(set) var commandAcknowledged = false
    @Published private(set) var voicePresented = false
    @Published var voiceLanguage: String {
        didSet { defaults.set(voiceLanguage, forKey: "activation.voiceLanguage"); cancelVoiceCommand() }
    }
    private var voiceRequestGeneration = 0
    private var voiceCaptureGeneration = 0
    private var voiceInputRecovery = VoiceInputRecovery()
    private var voiceRetryPending = false
    private let defaults: UserDefaults
    private let registersShortcuts: Bool
    private var shortcutsStarted = false
    private let openApplication: @MainActor (String) async throws -> String
    private let searchBrowser: @MainActor (String) async throws -> String
    private let assistant: AssistantViewModel
    private let notch: NotchWidgetViewModel
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var globalMonitor: Any?
    private var eventTap: ShortcutEventTap?
    private var fallbackActions = Set<ShortcutAction>()
    private var lastInputTrust = false
    private var localMonitor: Any?
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var shortcutRecoveryTask: Task<Void, Never>?
    private var shortcutHealthTask: Task<Void, Never>?
    private var lastShortcutTrust = false
    private var lastSecureInput = false
    private var registrationNeedsRetry = false
    private var modifierTracker = ModifierShortcutTracker()
    private var deliveryGate = ShortcutDeliveryGate()
    private let voiceCapture: any VoiceCapturing
    private let voiceNow: @MainActor () -> TimeInterval
    private var stopTask: Task<Void, Never>?
    private var voiceSession = VoiceCommandSession()
    private var feedbackTask: Task<Void, Never>?

    init(assistant: AssistantViewModel, notch: NotchWidgetViewModel, defaults: UserDefaults = .standard, registersShortcuts: Bool = true, lifecycleNotifications: NotificationCenter? = nil, openApplication: @escaping @MainActor (String) async throws -> String = LocalAppLauncher.open, searchBrowser: @escaping @MainActor (String) async throws -> String = BrowserSearch.open, voiceCapture: (any VoiceCapturing)? = nil, voiceNow: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.assistant = assistant
        self.notch = notch
        self.defaults = defaults
        self.registersShortcuts = registersShortcuts
        self.openApplication = openApplication
        self.searchBrowser = searchBrowser
        self.voiceCapture = voiceCapture ?? NativeVoiceCapture()
        self.voiceNow = voiceNow
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
        clipboardShortcut = saved(.clipboard, fallback: .clipboard)
        voiceLanguage = defaults.string(forKey: "activation.voiceLanguage") ?? "en_US"
        for action in [ShortcutAction.nextOutput, .muteMicrophone] {
            if let data = defaults.data(forKey: "activation.\(action.rawValue).chord"), !defaults.bool(forKey: "activation.\(action.rawValue).disabled"), let chord = try? JSONDecoder().decode(ShortcutChord.self, from: data) { audioShortcuts[action] = chord }
        }
        clipboardShortcutStatus = clipboardShortcut.map { "\($0.label) · Starting global shortcut…" } ?? "Shortcut off"
        shortcutStatus = companionShortcut.map { "\($0.label) · Starting global shortcut…" } ?? "Shortcut off"
        voiceShortcutStatus = voiceShortcut.map { "\($0.label) · Starting global shortcut…" } ?? "Shortcut off"
        if registersShortcuts || lifecycleNotifications != nil { observeShortcutLifecycle(workspace: lifecycleNotifications) }
    }

    // AppKit must finish launching before installing dispatcher hotkeys.
    func startGlobalShortcuts() {
        guard registersShortcuts, !shortcutsStarted else { return }
        shortcutsStarted = true
        registerHotkeys()
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
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSWindow.willCloseNotification] {
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
            if self.registersShortcuts { self.checkShortcutHealth() }
        }
    }

    private func checkShortcutHealth() {
        guard shortcutsStarted, recordingShortcut == nil else { return }
        let trusted = AXIsProcessTrusted()
        let secureInput = IsSecureEventInputEnabled()
        // A release can be lost while the system protects keyboard input.
        if NSEvent.modifierFlags.intersection(ShortcutChord.allowedModifiers).isEmpty { modifierTracker.reset() }
        eventTap?.ensureEnabled()
        if eventTap?.isValid == false { registrationNeedsRetry = true }
        if trusted != lastShortcutTrust || CGPreflightListenEventAccess() != lastInputTrust || secureInput != lastSecureInput || registrationNeedsRetry {
            registerHotkeys()
        }
    }

    func shortcut(for action: ShortcutAction) -> ShortcutChord? {
        switch action { case .companion: companionShortcut; case .voice: voiceShortcut; case .clipboard: clipboardShortcut; case .nextOutput, .muteMicrophone: audioShortcuts[action] }
    }
    private func setStatus(_ text: String, for action: ShortcutAction) {
        switch action { case .companion: shortcutStatus = text; case .voice: voiceShortcutStatus = text; case .clipboard: clipboardShortcutStatus = text; case .nextOutput, .muteMicrophone: audioShortcutStatuses[action] = text }
    }

    func setShortcut(_ chord: ShortcutChord?, for action: ShortcutAction) {
        recordingShortcut = nil
        if let chord, let otherAction = ShortcutAction.allCases.first(where: { $0 != action && shortcut(for: $0)?.keyCode == chord.keyCode && shortcut(for: $0)?.modifiers == chord.modifiers }) {
            setStatus("Already used for \(otherAction.title.lowercased())", for: action)
            return
        }
        switch action { case .companion: companionShortcut = chord; case .voice: voiceShortcut = chord; case .clipboard: clipboardShortcut = chord; case .nextOutput, .muteMicrophone: audioShortcuts[action] = chord }
        defaults.set(chord == nil, forKey: "activation.\(action.rawValue).disabled")
        if let chord, let data = try? JSONEncoder().encode(chord) { defaults.set(data, forKey: "activation.\(action.rawValue).chord") }
        else { defaults.removeObject(forKey: "activation.\(action.rawValue).chord") }
        if registersShortcuts { registerHotkeys() }
    }

    func enableModifierShortcuts() {
        // Permission is requested only by this explicit user action. Ordinary
        // Carbon key shortcuts work globally without keyboard monitoring.
        if !AXIsProcessTrusted() && !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        registerHotkeys()
    }

    private func registerHotkeys() {
        guard shortcutsStarted else { return }
        hotkeys.forEach { UnregisterEventHotKey($0) }; hotkeys = []
        if let handler { RemoveEventHandler(handler) }; handler = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        eventTap?.stop(); eventTap = nil
        fallbackActions = []
        modifierTracker.reset()
        deliveryGate = ShortcutDeliveryGate()
        registrationNeedsRetry = false
        guard recordingShortcut == nil else { return }
        Self.activeHotkeyOwner = self
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let target = GetEventDispatcherTarget()
        let installed = InstallEventHandler(target, { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let id = identifier.id
            if status == noErr, identifier.signature == 0x53494748, (1...UInt32(ShortcutAction.allCases.count)).contains(id) {
                let timestamp = GetEventTime(event)
                Task { @MainActor in ActivationController.activeHotkeyOwner?.receiveHotkey(ShortcutAction.allCases[Int(id) - 1], eventTime: timestamp) }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &eventType, nil, &handler)
        let trusted = AXIsProcessTrusted()
        lastInputTrust = CGPreflightListenEventAccess()
        lastShortcutTrust = trusted
        lastSecureInput = IsSecureEventInputEnabled()
        needsShortcutPermission = !trusted && !lastInputTrust && ShortcutAction.allCases.contains { shortcut(for: $0)?.isModifierOnly == true }
        for (index, action) in ShortcutAction.allCases.enumerated() {
            let id = UInt32(index + 1)
            var statusText = "Shortcut off"
            if let chord = shortcut(for: action) {
                if let code = chord.keyCode {
                    var reference: EventHotKeyRef?
                    let status = installed == noErr ? RegisterEventHotKey(code, chord.carbonModifiers, EventHotKeyID(signature: 0x53494748, id: id), target, 0, &reference) : installed
                    if status == noErr, let reference { hotkeys.append(reference); statusText = "\(chord.label) · Global shortcut registered" }
                    else { fallbackActions.insert(action); registrationNeedsRetry = true; statusText = "Shortcut unavailable; record another combination" }
                } else {
                    statusText = !trusted && !lastInputTrust ? "\(chord.label) · Allow keyboard access to use in other apps" : lastSecureInput ? "\(chord.label) · Secure keyboard input is active" : "\(chord.label) · Press and release to activate"
                }
            }
            setStatus(statusText, for: action)
        }
        guard ShortcutAction.allCases.contains(where: { shortcut(for: $0) != nil }) else { return }
        guard lastInputTrust || trusted || ShortcutAction.allCases.contains(where: { shortcut(for: $0)?.isModifierOnly == true }) || !fallbackActions.isEmpty else { return }
        if lastInputTrust || trusted {
            let tap = ShortcutEventTap { [weak self] key, flags, repeated, timestamp in
                self?.receiveShortcutEvent(keyCode: key, flags: flags, isRepeat: repeated, eventTime: timestamp)
            }
            if tap.start() {
                eventTap = tap
                for action in fallbackActions {
                    let text = "\(shortcut(for: action)?.label ?? "") · Global keyboard monitor active"
                    setStatus(text, for: action)
                }
                registrationNeedsRetry = false
                return
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.observeModifiers(event) }
            return event
        }
        if trusted {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.observeModifiers(event) }
            }
        }
        for action in ShortcutAction.allCases where shortcut(for: action)?.isModifierOnly == true {
            if globalMonitor == nil {
                let message = "\(shortcut(for: action)?.label ?? "") · Foreground only. Allow keyboard access or use a shortcut with a key."
                setStatus(message, for: action)
                if trusted || lastInputTrust { registrationNeedsRetry = true }
            }
        }
        if localMonitor == nil || (trusted && globalMonitor == nil) {
            registrationNeedsRetry = true
            let status = "Keyboard monitoring unavailable; retrying automatically"
            if companionShortcut?.isModifierOnly == true { shortcutStatus = status }
            if voiceShortcut?.isModifierOnly == true { voiceShortcutStatus = status }
            if clipboardShortcut?.isModifierOnly == true { clipboardShortcutStatus = status }
        }
    }

    private func observeModifiers(_ event: NSEvent) {
        receiveShortcutEvent(keyCode: event.type == .keyDown ? UInt32(event.keyCode) : nil, flags: event.modifierFlags, isRepeat: event.type == .keyDown && event.isARepeat, eventTime: event.timestamp)
    }

    // The same routing handles foreground, background and headless fixtures.
    // It consumes key codes/modifiers only, never typed text.
    func receiveShortcutEvent(keyCode: UInt32?, flags: NSEvent.ModifierFlags, isRepeat: Bool = false, eventTime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard recordingShortcut == nil else { modifierTracker.reset(); return }
        if let keyCode {
            modifierTracker.keyPressed()
            guard !isRepeat else { return }
            // When a keyboard grant exists, the session monitor is a live
            // fallback even when Carbon registered successfully. Some Space
            // transitions can interrupt one delivery path without unregistering it.
            for action in ShortcutAction.allCases where shortcut(for: action)?.matches(keyCode: keyCode, flags: flags) == true {
                deliverShortcut(action, source: .monitor, eventTime: eventTime)
            }
        } else if let modifiers = modifierTracker.update(flags) {
            for action in ShortcutAction.allCases {
                if let chord = shortcut(for: action), chord.isModifierOnly, chord.modifiers == modifiers { deliverShortcut(action, source: .monitor, eventTime: eventTime) }
            }
        }
    }

    func receiveHotkey(_ action: ShortcutAction, eventTime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard shortcut(for: action)?.keyCode != nil else { return }
        deliverShortcut(action, source: .carbon, eventTime: eventTime)
    }

    private func deliverShortcut(_ action: ShortcutAction, source: ShortcutDeliverySource, eventTime: TimeInterval) {
        guard recordingShortcut == nil, deliveryGate.accept(action, source: source, at: eventTime) else { return }
        lastShortcutSource = source == .carbon ? "System hotkey" : "Keyboard monitor"
        performShortcut(action)
    }

    func performShortcut(_ action: ShortcutAction) {
        guard recordingShortcut == nil else { return }
        lastShortcutActivation = Date()
        switch action { case .voice: toggleListening(); case .companion: notch.toggle(); case .clipboard: notch.toggleClipboard(); case .nextOutput: notch.audio.cycleOutput(); case .muteMicrophone: notch.audio.toggleMicrophoneMute() }
    }

    // Onboarding can request access without starting recognition or audio.
    func prepareVoiceAccess() async -> String {
        do { try await voiceCapture.prepareAccess(); return "Voice access is ready" }
        catch { return error.localizedDescription }
    }

    func toggleListening() {
        if isVoiceBusy { cancelVoiceCommand(); return }
        feedbackTask?.cancel()
        voiceRequestGeneration += 1
        let generation = voiceRequestGeneration
        voiceInputRecovery = VoiceInputRecovery()
        isPreparing = true
        voicePresented = true
        commandAcknowledged = false
        transcript = ""
        voiceStatus = "Checking microphone and speech access…"
        notch.showVoice(resetCollapse: true)
        Task { await startListening(generation: generation) }
    }

    private func startListening(generation: Int) async {
        guard !isListening, generation == voiceRequestGeneration else { return }
        voiceRetryPending = false
        isPreparing = true
        defer {
            if generation == voiceRequestGeneration, !voiceRetryPending {
                isPreparing = false
                notch.voiceActivityDidChange()
            }
        }
        do { try await voiceCapture.prepareAccess() }
        catch {
            guard generation == voiceRequestGeneration else { return }
            voiceStatus = error.localizedDescription
            return
        }
        guard generation == voiceRequestGeneration else { return }
        voiceCaptureGeneration += 1
        let captureGeneration = voiceCaptureGeneration
        voiceSession.start(at: voiceNow())
        isListening = true
        voiceStatus = "Listening — your command runs when you finish speaking"
        notch.showVoice()
        do {
            try voiceCapture.start(language: voiceLanguage) { [weak self] event in
                guard let self, self.isListening || self.isFinalizing,
                      generation == self.voiceRequestGeneration,
                      captureGeneration == self.voiceCaptureGeneration else { return }
                switch event {
                case .level(let level):
                    self.voiceSession.observe(decibels: level.decibels, duration: level.duration, at: level.time)
                    self.checkVoiceEndpoint()
                case .recognition(let text, let final):
                    self.transcript = text
                    self.voiceSession.recognize(text, final: final, at: self.voiceNow())
                    // isFinal completes the request, even if capture has not
                    // already seen quiet. Don't wait for silence after a final.
                    if final && self.isListening { self.finishListening() }
                    else if self.isFinalizing { self.dispatchFinalVoiceCommand() }
                case .inputChanged:
                    guard self.isListening else { return }
                    self.recoverVoiceInput(generation: generation)
                case .failure(let message):
                    if self.isFinalizing, case .search = FocusVoiceParser.parse(self.transcript) {
                        // Keep draining the settled search text. Local app/timer
                        // actions still require an authoritative final result.
                        self.voiceStatus = "Finishing your search…"
                        return
                    }
                    self.stopListening()
                    self.voiceStatus = "Speech recognition stopped. Please try again. \(message)"
                }
            }
        } catch {
            if let failure = error as? VoiceCaptureFailure, !failure.permitsInputRetry {
                stopListening(); voiceStatus = failure.localizedDescription
            } else { recoverVoiceInput(generation: generation, error: error.localizedDescription) }
            return
        }
        guard captureGeneration == voiceCaptureGeneration else { return }
        stopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, generation == self.voiceRequestGeneration,
                      captureGeneration == self.voiceCaptureGeneration else { return }
                self.checkVoiceEndpoint()
            }
        }
    }

    private func checkVoiceEndpoint() {
        let decision = voiceSession.decision(at: voiceNow())
        if decision == .endAudio { finishListening() }
        else if decision != .wait {
            if decision == .finalResultTimedOut,
               case .search = FocusVoiceParser.parse(voiceSession.transcript),
               let text = voiceSession.takeSettledSearchText(at: voiceNow()) {
                stopListening()
                executeVoiceCommand(text)
                return
            }
            stopListening()
            switch decision {
            case .noSpeech: voiceStatus = "No speech heard. Try again."
            case .limitReached: voiceStatus = "That command was too long. Try a shorter command; nothing was run."
            case .inputLost: voiceStatus = "Microphone input stopped. Try again."
            default: voiceStatus = "Couldn't finish recognizing your command. Try again; nothing was run."
            }
        }
    }

    private func recoverVoiceInput(generation: Int, error: String? = nil) {
        let shouldRetry = voiceInputRecovery.retry(hasSpeech: voiceSession.hasDetectedSpeech || !transcript.isEmpty)
        stopListening()
        guard shouldRetry else {
            voiceStatus = error.map { "Could not start microphone: \($0). Check Audio → Microphone and retry." }
                ?? "Microphone changed. Speak again to use the new input; nothing was run."
            return
        }
        voiceRetryPending = true
        isPreparing = true
        voiceStatus = "Preparing the microphone…"
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, generation == self.voiceRequestGeneration else { return }
            await self.startListening(generation: generation)
        }
    }

    func finishListening() {
        guard isListening else { return }
        voiceSession.endAudio(at: voiceNow())
        isListening = false; isFinalizing = true
        voiceStatus = "Finishing your command…"
        notch.voiceActivityDidChange()
        voiceCapture.finish()
        dispatchFinalVoiceCommand()
    }

    private func dispatchFinalVoiceCommand() {
        guard let text = voiceSession.takeFinalCommand() else { return }
        stopListening()
        executeVoiceCommand(text)
    }

    func cancelVoiceCommand(keepCompanionVisible: Bool = false) {
        voiceRequestGeneration += 1
        voiceRetryPending = false
        isPreparing = false
        commandAcknowledged = false
        voicePresented = false
        transcript = ""
        feedbackTask?.cancel()
        stopListening()
        voiceStatus = "Voice is off"
        if keepCompanionVisible { notch.show() } else { notch.hide() }
    }

    func stopListening() {
        voiceCaptureGeneration += 1
        stopTask?.cancel(); stopTask = nil
        isListening = false; isFinalizing = false; isPreparing = false; isExecutingVoiceCommand = false
        voiceSession.cancel()
        voiceCapture.cancel()
        notch.voiceActivityDidChange()
    }

    // Only local, reversible commands are executed by this intent parser.
    // Recognition text is never evaluated as code or an external instruction.
    func executeVoiceCommand(_ text: String) {
        feedbackTask?.cancel()
        isExecutingVoiceCommand = false
        voicePresented = true
        transcript = text
        commandAcknowledged = false
        guard let command = FocusVoiceParser.parse(text) else {
            voiceStatus = text.isEmpty ? "No speech heard. Try again." : "That action is not available. Say a search topic, or use an app or timer command."
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
            voiceStatus = "Sieghart tucked away"; voicePresented = false; transcript = ""; notch.hide(); return
        case .configure:
            voiceStatus = "Choose your focus settings"; commandAcknowledged = true; notch.showFocusSetup(); scheduleFeedback(closeWidget: false); return
        case .aiLimits:
            voiceStatus = "Here are your AI limits"; commandAcknowledged = true; notch.showAILimits(); scheduleFeedback(closeWidget: false); return
        case .openApp(let name):
            isExecutingVoiceCommand = true
            let generation = voiceRequestGeneration
            voiceStatus = "Opening \(name)…"; notch.showVoice()
            Task { @MainActor [weak self] in
                guard let self, generation == self.voiceRequestGeneration, !Task.isCancelled else { return }
                do {
                    let app = try await self.openApplication(name)
                    guard generation == self.voiceRequestGeneration else { return }
                    self.voiceStatus = "Opened \(app)"; self.commandAcknowledged = true
                } catch {
                    guard generation == self.voiceRequestGeneration else { return }
                    self.voiceStatus = error.localizedDescription; self.commandAcknowledged = false
                }
                self.isExecutingVoiceCommand = false
                self.notch.voiceActivityDidChange()
                self.scheduleFeedback(closeWidget: true)
            }
            return
        case .search(let query):
            isExecutingVoiceCommand = true
            let generation = voiceRequestGeneration
            voiceStatus = "Opening your search…"; notch.showVoice()
            Task { @MainActor [weak self] in
                guard let self, generation == self.voiceRequestGeneration, !Task.isCancelled else { return }
                do {
                    let result = try await self.searchBrowser(query)
                    guard generation == self.voiceRequestGeneration else { return }
                    self.voiceStatus = "Search opened · \(result)"; self.commandAcknowledged = true
                } catch {
                    guard generation == self.voiceRequestGeneration else { return }
                    self.voiceStatus = error.localizedDescription; self.commandAcknowledged = false
                }
                self.isExecutingVoiceCommand = false
                self.notch.voiceActivityDidChange()
                self.scheduleFeedback(closeWidget: true)
            }
            return
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
            self.voicePresented = false
            if closeWidget { self.notch.hide() }
        }
    }
}

// Listen-only session events survive changes of foreground app. They are
// delivered on the main run loop and never suppress or alter another app's input.
@MainActor private final class ShortcutEventTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private let receive: (UInt32?, NSEvent.ModifierFlags, Bool, TimeInterval) -> Void
    init(receive: @escaping (UInt32?, NSEvent.ModifierFlags, Bool, TimeInterval) -> Void) { self.receive = receive }
    func start() -> Bool {
        guard CGPreflightListenEventAccess() || AXIsProcessTrusted() else { return false }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue) | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            MainActor.assumeIsolated {
                let monitor = Unmanaged<ShortcutEventTap>.fromOpaque(pointer).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { monitor.ensureEnabled() }
                else {
                    let key = type == .keyDown ? UInt32(event.getIntegerValueField(.keyboardEventKeycode)) : nil
                    let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                    let repeated = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    let timestamp = Double(event.timestamp) / 1_000_000_000
                    // Keep the tap callback short; AppKit layout and speech
                    // preparation must not block the keyboard event stream.
                    DispatchQueue.main.async { [weak monitor] in monitor?.receive(key, flags, repeated, timestamp) }
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { stop(); return false }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
    var isValid: Bool { port.map { CFMachPortIsValid($0) } ?? false }
    func ensureEnabled() { if let port, !CGEvent.tapIsEnabled(tap: port) { CGEvent.tapEnable(tap: port, enable: true) } }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        source = nil; port = nil
    }
}
