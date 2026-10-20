import AppKit
import ApplicationServices
import Carbon
import Combine

struct KeyGuardDecision: Equatable, Sendable {
    var consume = false
    var flags: UInt64
}

@MainActor protocol InputGuardsBackend: AnyObject {
    func start(onMouse: @escaping @MainActor (ClickDebounceSample) -> Bool,
               onKey: @escaping @MainActor (KeyGuardSample) -> KeyGuardDecision,
               interrupted: @escaping @MainActor () -> Void) throws
    func stop()
}

@MainActor protocol SnippetExpanding: AnyObject {
    func expand(_ request: SnippetExpansionRequest) -> Bool
}

@MainActor final class NativeSnippetExpander: SnippetExpanding {
    func expand(_ request: SnippetExpansionRequest) -> Bool {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == request.pid,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        for _ in 0..<request.trigger.utf16.count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) else { return false }
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
        var utf16 = Array(request.replacement.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return false }
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}

@MainActor final class NativeInputGuardsBackend: InputGuardsBackend {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var onMouse: (@MainActor (ClickDebounceSample) -> Bool)?
    private var onKey: (@MainActor (KeyGuardSample) -> KeyGuardDecision)?
    private var interrupted: (@MainActor () -> Void)?

    func start(onMouse: @escaping @MainActor (ClickDebounceSample) -> Bool,
               onKey: @escaping @MainActor (KeyGuardSample) -> KeyGuardDecision,
               interrupted: @escaping @MainActor () -> Void) throws {
        stop()
        self.onMouse = onMouse; self.onKey = onKey; self.interrupted = interrupted
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let shouldPass: Bool = MainActor.assumeIsolated {
                    let backend = Unmanaged<NativeInputGuardsBackend>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        let recovery = backend.interrupted
                        DispatchQueue.main.async { recovery?() }
                        return true
                    }
                    return backend.receive(type: type, event: event)
                }
                return shouldPass ? Unmanaged.passUnretained(event) : nil
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            stop(); throw CocoaError(.featureUnsupported)
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func receive(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            guard let onMouse else { return true }
            let phase: MouseButtonPhase = (type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown) ? .down :
                ((type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp) ? .up : .dragged)
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let nowNs = DispatchTime.now().uptimeNanoseconds
            let sample = ClickDebounceSample(button: button, phase: phase, location: event.location, timestampNs: nowNs)
            return !onMouse(sample)
        case .keyDown, .keyUp, .flagsChanged:
            guard let onKey else { return true }
            let phase: KeyEventPhase = type == .keyDown ? .down : (type == .keyUp ? .up : .flagsChanged)
            let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
            let text = length > 0 ? String(utf16CodeUnits: chars, count: length) : ""
            let app = NSWorkspace.shared.frontmostApplication
            let pid = (app?.processIdentifier != ProcessInfo.processInfo.processIdentifier) ? (app?.processIdentifier ?? 0) : 0
            let sample = KeyGuardSample(keyCode: keyCode, phase: phase, isRepeat: isRepeat,
                                        flags: event.flags.rawValue, characters: text,
                                        timestampNs: DispatchTime.now().uptimeNanoseconds,
                                        frontmostPID: pid, frontmostAppName: app?.localizedName ?? "App")
            let decision = onKey(sample)
            if decision.consume { return false }
            if decision.flags != sample.flags { event.flags = CGEventFlags(rawValue: decision.flags) }
            return true
        default:
            return true
        }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        port = nil; source = nil; onMouse = nil; onKey = nil; interrupted = nil
    }
}

@MainActor final class InputGuardsController: ObservableObject {
    @Published var options: InputGuardsOptions {
        didSet { persist(); resetTransientStates(); if started { configure() } }
    }
    @Published private(set) var status = "Input guards and snippets are off."
    @Published private(set) var quitHint: String?
    @Published private(set) var snippetValidationMessage: String?
    var shortcutChords: () -> [ShortcutChord] = { [] }

    private let defaults: UserDefaults
    private let backend: any InputGuardsBackend
    private let expander: any SnippetExpanding
    private let trusted: () -> Bool
    private let secureInput: () -> Bool
    private let requestAccess: () -> Void
    private var started = false
    private var asleep = false
    private var locked = false
    private var sessionActive = true
    private var installed = false
    private var generation = 0
    private var clickState = ClickDebounceState()
    private var keyState = KeyDebounceState()
    private var superKeyState = SuperKeyState()
    private var quitState = QuitProtectionState()
    private var snippetMatcher = SnippetMatcher()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(defaults: UserDefaults = .standard,
         backend: (any InputGuardsBackend)? = nil,
         expander: (any SnippetExpanding)? = nil,
         trusted: @escaping () -> Bool = AXIsProcessTrusted,
         secureInput: @escaping () -> Bool = IsSecureEventInputEnabled,
         requestAccess: @escaping () -> Void = { AccessibilityAccess.request() }) {
        self.defaults = defaults
        self.backend = backend ?? NativeInputGuardsBackend()
        self.expander = expander ?? NativeSnippetExpander()
        self.trusted = trusted
        self.secureInput = secureInput
        self.requestAccess = requestAccess
        let storedClickMs = defaults.object(forKey: "input.guards.clickDebounceMs") as? Int ?? 35
        let storedKeyMs = defaults.object(forKey: "input.guards.keyDebounceMs") as? Int ?? 30
        let decodedSnippets = (defaults.data(forKey: "input.guards.snippets"))
            .flatMap { try? JSONDecoder().decode([TextSnippet].self, from: $0) } ?? []
        options = InputGuardsOptions(
            clickDebounceEnabled: defaults.bool(forKey: "input.guards.clickDebounceEnabled"),
            clickDebounceMs: min(max(storedClickMs, ClickDebounceState.windowRange.lowerBound), ClickDebounceState.windowRange.upperBound),
            keyDebounceEnabled: defaults.bool(forKey: "input.guards.keyDebounceEnabled"),
            keyDebounceMs: min(max(storedKeyMs, KeyDebounceState.windowRange.lowerBound), KeyDebounceState.windowRange.upperBound),
            superKeyEnabled: defaults.bool(forKey: "input.guards.superKeyEnabled"),
            superKeyTrigger: SuperKeyTrigger(rawValue: defaults.string(forKey: "input.guards.superKeyTrigger") ?? "") ?? .f18,
            quitProtectionEnabled: defaults.bool(forKey: "input.guards.quitProtectionEnabled"),
            protectCloseWindow: defaults.bool(forKey: "input.guards.protectCloseWindow"),
            snippetsEnabled: defaults.bool(forKey: "input.guards.snippetsEnabled"),
            snippets: decodedSnippets
        )
    }

    private func persist() {
        defaults.set(options.clickDebounceEnabled, forKey: "input.guards.clickDebounceEnabled")
        defaults.set(min(max(options.clickDebounceMs, ClickDebounceState.windowRange.lowerBound), ClickDebounceState.windowRange.upperBound), forKey: "input.guards.clickDebounceMs")
        defaults.set(options.keyDebounceEnabled, forKey: "input.guards.keyDebounceEnabled")
        defaults.set(min(max(options.keyDebounceMs, KeyDebounceState.windowRange.lowerBound), KeyDebounceState.windowRange.upperBound), forKey: "input.guards.keyDebounceMs")
        defaults.set(options.superKeyEnabled, forKey: "input.guards.superKeyEnabled")
        defaults.set(options.superKeyTrigger.rawValue, forKey: "input.guards.superKeyTrigger")
        defaults.set(options.quitProtectionEnabled, forKey: "input.guards.quitProtectionEnabled")
        defaults.set(options.protectCloseWindow, forKey: "input.guards.protectCloseWindow")
        defaults.set(options.snippetsEnabled, forKey: "input.guards.snippetsEnabled")
        if let encoded = try? JSONEncoder().encode(options.snippets) {
            defaults.set(encoded, forKey: "input.guards.snippets")
        }
    }

    private var available: Bool { started && !asleep && !locked && sessionActive }
    var hasSuperKeyConflict: Bool {
        options.superKeyEnabled && options.superKeyTrigger.conflicts(with: shortcutChords())
    }

    private func resetTransientStates() {
        clickState.reset(); keyState.reset(); superKeyState.reset()
        quitState.reset(); snippetMatcher.reset(); quitHint = nil
    }

    func allowAccess() { requestAccess(); if started { configure() } }

    @discardableResult
    func addSnippet(trigger: String, replacement: String) -> Bool {
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReplacement = replacement.trimmingCharacters(in: .newlines)
        if let error = TextSnippet.validate(trigger: cleanTrigger, replacement: cleanReplacement, existing: options.snippets) {
            snippetValidationMessage = error
            return false
        }
        snippetValidationMessage = nil
        options.snippets.append(TextSnippet(trigger: cleanTrigger, replacement: cleanReplacement, enabled: true))
        return true
    }

    func removeSnippet(id: UUID) {
        options.snippets.removeAll { $0.id == id }
        snippetValidationMessage = nil
    }

    func toggleSnippet(id: UUID) {
        guard let index = options.snippets.firstIndex(where: { $0.id == id }) else { return }
        options.snippets[index].enabled.toggle()
    }

    private func stopBackend() {
        generation += 1; installed = false; backend.stop(); resetTransientStates()
    }

    func configure() {
        resetTransientStates()
        guard started else { stopBackend(); status = "Input guards and snippets are off."; return }
        guard options.enabled else { stopBackend(); status = "Input guards and snippets are off."; return }
        guard available else { stopBackend(); status = "Input guards are paused while the Mac sleeps or is locked."; return }
        guard trusted() else { stopBackend(); status = "Allow Accessibility, then retry input guards."; return }
        guard !hasSuperKeyConflict else {
            stopBackend()
            status = "Hyper key trigger conflicts with a registered shortcut. Choose another trigger or shortcut."
            return
        }
        if installed {
            status = "Input guards are active."
            return
        }
        generation += 1
        let current = generation
        do {
            try backend.start(onMouse: { [weak self] sample in
                guard let self, self.started, self.installed, self.generation == current else { return false }
                guard self.available, self.trusted() else { self.configure(); return false }
                if sample.phase == .down { self.snippetMatcher.reset() }
                return self.clickState.shouldSuppress(sample, enabled: self.options.clickDebounceEnabled, windowMs: self.options.clickDebounceMs)
            }, onKey: { [weak self] sample in
                guard let self, self.started, self.installed, self.generation == current else {
                    return KeyGuardDecision(consume: false, flags: sample.flags)
                }
                guard self.available, self.trusted(), !self.hasSuperKeyConflict else {
                    self.configure()
                    return KeyGuardDecision(consume: false, flags: sample.flags)
                }
                if self.secureInput() {
                    self.keyState.reset(); self.superKeyState.reset(); self.quitState.reset(); self.snippetMatcher.reset()
                    self.status = "Keyboard guards paused during Secure Input."
                    return KeyGuardDecision(consume: false, flags: sample.flags)
                }
                if self.keyState.shouldSuppress(sample, enabled: self.options.keyDebounceEnabled, windowMs: self.options.keyDebounceMs) {
                    return KeyGuardDecision(consume: true, flags: sample.flags)
                }
                let superDecision = self.superKeyState.process(sample, enabled: self.options.superKeyEnabled, trigger: self.options.superKeyTrigger)
                if superDecision.consume {
                    return KeyGuardDecision(consume: true, flags: superDecision.flags)
                }
                var modifiedSample = sample
                modifiedSample.flags = superDecision.flags
                let quitDecision = self.quitState.evaluate(modifiedSample, enabled: self.options.quitProtectionEnabled, protectClose: self.options.protectCloseWindow)
                if let hint = quitDecision.hint { self.quitHint = hint }
                if quitDecision.intercepted {
                    return KeyGuardDecision(consume: true, flags: superDecision.flags)
                }
                if let request = self.snippetMatcher.feed(modifiedSample, enabled: self.options.snippetsEnabled, snippets: self.options.snippets) {
                    if self.expander.expand(request) {
                        self.status = "Expanded snippet \(request.trigger)."
                    }
                }
                return KeyGuardDecision(consume: false, flags: superDecision.flags)
            }, interrupted: { [weak self] in
                guard let self, self.started, self.generation == current else { return }
                self.stopBackend()
                self.configure()
            })
            installed = true
            status = "Input guards are active."
        } catch {
            generation += 1; installed = false; backend.stop()
            status = "Input guards unavailable. Check Accessibility and retry."
        }
    }

    func start(observeSystem: Bool = true) {
        guard !started else { return }; started = true; configure()
        guard observeSystem else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == NSWorkspace.willSleepNotification { self?.setSleeping(true) }
                    if name == NSWorkspace.didWakeNotification { self?.setSleeping(false) }
                    if name == NSWorkspace.sessionDidResignActiveNotification { self?.setSessionActive(false) }
                    if name == NSWorkspace.sessionDidBecomeActiveNotification { self?.setSessionActive(true) }
                    if name == NSWorkspace.didActivateApplicationNotification { self?.resetAppContext() }
                }
            }))
        }
        let distributed = DistributedNotificationCenter.default()
        for name in [Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked")] {
            observers.append((distributed, distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(name.rawValue == "com.apple.screenIsLocked") }
            }))
        }
    }

    func resetAppContext() {
        snippetMatcher.reset(); quitState.reset(); superKeyState.reset(); quitHint = nil
    }
    func setSleeping(_ value: Bool) { asleep = value; if started { configure() } }
    func setLocked(_ value: Bool) { locked = value; if started { configure() } }
    func setSessionActive(_ value: Bool) { sessionActive = value; if started { configure() } }

    func stop() {
        started = false; generation += 1; installed = false; backend.stop(); resetTransientStates()
        for (center, token) in observers { center.removeObserver(token) }; observers = []
        status = "Input guards and snippets are off."
    }
}
