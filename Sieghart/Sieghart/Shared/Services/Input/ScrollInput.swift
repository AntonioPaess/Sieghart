import AppKit
import ApplicationServices
import Combine

/// Values are copied from the scroll event only. Phase, momentum, timestamp,
/// location and all other event fields stay on the original CGEvent.
struct ScrollVector: Equatable, Sendable {
    var x: Int64 = 0
    var y: Int64 = 0
}
struct ScrollSample: Equatable, Sendable {
    var lines = ScrollVector()
    var points = ScrollVector()
    var fixed = ScrollVector()
    var continuous = false
    var flags: UInt64 = 0
}
enum ScrollModifier: String, CaseIterable, Sendable {
    case shift, option, control
    var flags: UInt64 {
        switch self {
        case .shift: CGEventFlags.maskShift.rawValue
        case .option: CGEventFlags.maskAlternate.rawValue
        case .control: CGEventFlags.maskControl.rawValue
        }
    }
    func conflicts(with chords: [ShortcutChord]) -> Bool {
        chords.contains { $0.isModifierOnly && UInt64($0.flags.rawValue) & flags != 0 }
    }
}
struct ScrollOptions: Equatable, Sendable {
    static let stepRange: ClosedRange<Int64> = 8...96
    var inverted = false
    var horizontal = false
    var affectsContinuous = false
    var modifier: ScrollModifier = .shift
    var linear = false
    var smooth = false
    var stepPixels: Int64 = 24
    var clampedStepPixels: Int64 { min(max(stepPixels, Self.stepRange.lowerBound), Self.stepRange.upperBound) }
    var directionalEnabled: Bool { inverted || horizontal }
    var wheelCurveEnabled: Bool { linear || smooth }
    var enabled: Bool { directionalEnabled || wheelCurveEnabled }
}
enum ScrollTransform {
    static func apply(_ input: ScrollSample, options: ScrollOptions) -> ScrollSample {
        guard options.enabled else { return input }
        if input.continuous && (!options.directionalEnabled || !options.affectsContinuous) { return input }
        var result = input
        let redirect = options.horizontal && input.flags & options.modifier.flags != 0 &&
            [input.lines.y, input.points.y, input.fixed.y].contains(where: { $0 != 0 })
        func transform(_ vector: ScrollVector) -> ScrollVector? {
            var value = vector
            if options.inverted {
                guard value.x != .min, value.y != .min else { return nil }
                value.x = -value.x; value.y = -value.y
            }
            if redirect {
                let sum = value.x.addingReportingOverflow(value.y)
                guard !sum.overflow else { return nil }
                value.x = sum.partialValue; value.y = 0
            }
            guard [value.x, value.y].allSatisfy({ Int64(Int32.min)...Int64(Int32.max) ~= $0 }) else { return nil }
            return value
        }
        guard let lines = transform(input.lines), let points = transform(input.points), let fixed = transform(input.fixed) else { return input }
        result.lines = lines; result.points = points; result.fixed = fixed
        if !input.continuous && options.wheelCurveEnabled {
            let step = options.clampedStepPixels
            func shapeAxis(line: Int64, point: Int64, fixedPoint: Int64) -> (Int64, Int64, Int64)? {
                let raw = line != 0 ? line : (point != 0 ? point : fixedPoint)
                guard raw != 0 else { return (0, 0, 0) }
                let sign: Int64 = raw > 0 ? 1 : -1
                if options.linear {
                    let pixels = options.smooth ? (sign * step * 5) / 4 : sign * step
                    let fixedVal = options.smooth ? sign * step * 81_920 : pixels * 65_536
                    guard Int64(Int32.min)...Int64(Int32.max) ~= pixels,
                          Int64(Int32.min)...Int64(Int32.max) ~= fixedVal else { return nil }
                    return (sign, pixels, fixedVal)
                }
                let boundedLines = line != 0 ? min(max(line, -6), 6) : sign
                let basePixels = boundedLines * step
                let blended = point != 0 ? (point + basePixels) / 2 : basePixels
                let finalPixels = blended != 0 ? blended : sign * step
                let fixedVal = finalPixels * 65_536
                guard Int64(Int32.min)...Int64(Int32.max) ~= finalPixels,
                      Int64(Int32.min)...Int64(Int32.max) ~= fixedVal else { return nil }
                return (boundedLines, finalPixels, fixedVal)
            }
            guard let shapedX = shapeAxis(line: result.lines.x, point: result.points.x, fixedPoint: result.fixed.x),
                  let shapedY = shapeAxis(line: result.lines.y, point: result.points.y, fixedPoint: result.fixed.y) else { return input }
            result.lines = ScrollVector(x: shapedX.0, y: shapedY.0)
            result.points = ScrollVector(x: shapedX.1, y: shapedY.1)
            result.fixed = ScrollVector(x: shapedX.2, y: shapedY.2)
        }
        if redirect { result.flags &= ~options.modifier.flags }
        return result
    }
}

struct PointerAccelerationOptions: Equatable, Sendable {
    static let speedRange: ClosedRange<Double> = 0.25...3.0
    static let flatScaling: Double = -1.0
    var enabled = false
    var flatCurve = false
    var speed: Double = 1.0
    var clampedSpeed: Double {
        guard speed.isFinite else { return 1.0 }
        return min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
    }
    var targetScaling: Double { flatCurve ? Self.flatScaling : clampedSpeed }
}

@MainActor protocol PointerAccelerationBackend: AnyObject {
    func readScaling() -> Double?
    @discardableResult func writeScaling(_ value: Double) -> Bool
}

@MainActor final class NativePointerAccelerationBackend: PointerAccelerationBackend {
    private let key = "com.apple.mouse.scaling" as CFString
    func readScaling() -> Double? {
        guard let raw = CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication) as? NSNumber else { return nil }
        let value = raw.doubleValue
        return value.isFinite ? value : nil
    }
    @discardableResult func writeScaling(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        CFPreferencesSetValue(key, NSNumber(value: value), kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

@MainActor protocol ScrollInputBackend: AnyObject {
    func start(transform: @escaping @MainActor (ScrollSample) -> ScrollSample,
               interrupted: @escaping @MainActor () -> Void) throws
    func stop()
}

@MainActor final class NativeScrollInputBackend: ScrollInputBackend {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var transform: (@MainActor (ScrollSample) -> ScrollSample)?
    private var interrupted: (@MainActor () -> Void)?
    func start(transform: @escaping @MainActor (ScrollSample) -> ScrollSample,
               interrupted: @escaping @MainActor () -> Void) throws {
        stop()
        self.transform = transform; self.interrupted = interrupted
        port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                MainActor.assumeIsolated {
                    let backend = Unmanaged<NativeScrollInputBackend>.fromOpaque(context).takeUnretainedValue()
                    if type == .scrollWheel { backend.receive(event) }
                    else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        // Recovery leaves this callback before replacing its run-loop source.
                        let recovery = backend.interrupted
                        DispatchQueue.main.async { recovery?() }
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            stop(); throw CocoaError(.featureUnsupported)
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }
    private func receive(_ event: CGEvent) {
        guard let transform else { return }
        Self.apply(to: event, transform: transform)
    }
    static func apply(to event: CGEvent, transform: (ScrollSample) -> ScrollSample) {
        let fields: [(CGEventField, CGEventField)] = [(.scrollWheelEventDeltaAxis2, .scrollWheelEventDeltaAxis1),
            (.scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis1),
            (.scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis1)]
        func vector(_ index: Int) -> ScrollVector {
            ScrollVector(x: event.getIntegerValueField(fields[index].0), y: event.getIntegerValueField(fields[index].1))
        }
        let input = ScrollSample(lines: vector(0), points: vector(1), fixed: vector(2),
            continuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0, flags: event.flags.rawValue)
        let output = transform(input)
        guard output != input else { return }
        for (index, value) in [output.lines, output.points, output.fixed].enumerated() {
            event.setIntegerValueField(fields[index].0, value: value.x)
            event.setIntegerValueField(fields[index].1, value: value.y)
        }
        event.flags = CGEventFlags(rawValue: output.flags)
    }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        port = nil; source = nil; transform = nil; interrupted = nil
    }
}

@MainActor final class ScrollInputController: ObservableObject {
    @Published var options: ScrollOptions { didSet { persist(); if started { configure() } } }
    @Published var pointerAcceleration: PointerAccelerationOptions {
        didSet { persistAcceleration(); if started { configureAcceleration() } }
    }
    @Published private(set) var status = "Scroll utilities are off"
    @Published private(set) var accelerationStatus = "Mouse acceleration control is off"
    @Published private(set) var savedOriginalScaling: Double?
    @Published private(set) var inputHint: String?
    var shortcutChords: () -> [ShortcutChord] = { [] }
    private let defaults: UserDefaults
    private let backend: any ScrollInputBackend
    private let accelerationBackend: any PointerAccelerationBackend
    private let trusted: () -> Bool
    private let requestAccess: () -> Void
    private var lastAppliedScaling: Double?
    private var started = false
    private var asleep = false
    private var locked = false
    private var sessionActive = true
    private var generation = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var health: Task<Void, Never>?
    init(defaults: UserDefaults = .standard, backend: (any ScrollInputBackend)? = nil,
         accelerationBackend: (any PointerAccelerationBackend)? = nil,
         trusted: @escaping () -> Bool = AXIsProcessTrusted,
         requestAccess: @escaping () -> Void = { AccessibilityAccess.request() }) {
        lastAppliedScaling = defaults.object(forKey: "input.pointer.acceleration.lastApplied") as? Double
        self.defaults = defaults; self.backend = backend ?? NativeScrollInputBackend()
        self.accelerationBackend = accelerationBackend ?? NativePointerAccelerationBackend()
        self.trusted = trusted; self.requestAccess = requestAccess
        let storedStep = defaults.object(forKey: "input.scroll.stepPixels") as? Int64 ?? 24
        options = ScrollOptions(inverted: defaults.bool(forKey: "input.scroll.inverted"),
            horizontal: defaults.bool(forKey: "input.scroll.horizontal"),
            affectsContinuous: defaults.bool(forKey: "input.scroll.continuous"),
            modifier: ScrollModifier(rawValue: defaults.string(forKey: "input.scroll.modifier") ?? "") ?? .shift,
            linear: defaults.bool(forKey: "input.scroll.linear"),
            smooth: defaults.bool(forKey: "input.scroll.smooth"),
            stepPixels: min(max(storedStep, ScrollOptions.stepRange.lowerBound), ScrollOptions.stepRange.upperBound))
        let storedSpeed = defaults.object(forKey: "input.pointer.acceleration.speed") as? Double ?? 1.0
        pointerAcceleration = PointerAccelerationOptions(
            enabled: defaults.bool(forKey: "input.pointer.acceleration.enabled"),
            flatCurve: defaults.bool(forKey: "input.pointer.acceleration.flatCurve"),
            speed: storedSpeed.isFinite ? min(max(storedSpeed, PointerAccelerationOptions.speedRange.lowerBound), PointerAccelerationOptions.speedRange.upperBound) : 1.0)
        if defaults.bool(forKey: "input.pointer.acceleration.hasSavedOriginal"),
           let saved = defaults.object(forKey: "input.pointer.acceleration.savedOriginal") as? Double, saved.isFinite {
            savedOriginalScaling = saved
        }
    }
    private func persist() {
        defaults.set(options.inverted, forKey: "input.scroll.inverted")
        defaults.set(options.horizontal, forKey: "input.scroll.horizontal")
        defaults.set(options.affectsContinuous, forKey: "input.scroll.continuous")
        defaults.set(options.modifier.rawValue, forKey: "input.scroll.modifier")
        defaults.set(options.linear, forKey: "input.scroll.linear")
        defaults.set(options.smooth, forKey: "input.scroll.smooth")
        defaults.set(options.clampedStepPixels, forKey: "input.scroll.stepPixels")
    }
    private func persistAcceleration() {
        defaults.set(pointerAcceleration.enabled, forKey: "input.pointer.acceleration.enabled")
        defaults.set(pointerAcceleration.flatCurve, forKey: "input.pointer.acceleration.flatCurve")
        defaults.set(pointerAcceleration.clampedSpeed, forKey: "input.pointer.acceleration.speed")
    }
    private func saveOriginalScaling(_ value: Double?) {
        savedOriginalScaling = value
        if let value {
            defaults.set(true, forKey: "input.pointer.acceleration.hasSavedOriginal")
            defaults.set(value, forKey: "input.pointer.acceleration.savedOriginal")
        } else {
            defaults.removeObject(forKey: "input.pointer.acceleration.hasSavedOriginal")
            defaults.removeObject(forKey: "input.pointer.acceleration.savedOriginal")
        }
    }
    func start(observeSystem: Bool = true) {
        guard !started else { return }; started = true; configure(); configureAcceleration()
        guard observeSystem else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == NSWorkspace.willSleepNotification { self?.setSleeping(true) }
                    if name == NSWorkspace.didWakeNotification { self?.setSleeping(false) }
                    if name == NSWorkspace.sessionDidResignActiveNotification { self?.setSessionActive(false) }
                    if name == NSWorkspace.sessionDidBecomeActiveNotification { self?.setSessionActive(true) }
                }
            }))
        }
        // Session resign covers switching users; screen lock can occur without
        // a session switch. Observe both and keep the lock gate until unlock.
        let distributed = DistributedNotificationCenter.default()
        for name in [Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked")] {
            observers.append((distributed, distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(name.rawValue == "com.apple.screenIsLocked") }
            }))
        }
    }
    func setSleeping(_ value: Bool) { asleep = value; if started { configure(); configureAcceleration() } }
    func setLocked(_ value: Bool) { locked = value; if started { configure(); configureAcceleration() } }
    func setSessionActive(_ value: Bool) { sessionActive = value; if started { configure(); configureAcceleration() } }
    func allowAccess() { requestAccess(); if started { configure() } }
    var hasConflict: Bool { options.horizontal && options.modifier.conflicts(with: shortcutChords()) }
    private func setLastAppliedScaling(_ value: Double?) {
        lastAppliedScaling = value
        if let value { defaults.set(value, forKey: "input.pointer.acceleration.lastApplied") }
        else { defaults.removeObject(forKey: "input.pointer.acceleration.lastApplied") }
    }
    @discardableResult private func restoreOwnedAcceleration() -> Bool {
        guard let original = savedOriginalScaling else { return true }
        guard let current = accelerationBackend.readScaling(), current.isFinite else {
            accelerationStatus = "Could not read mouse acceleration; no setting was overwritten. Retry restore."; return false
        }
        guard let applied = lastAppliedScaling, abs(current - applied) < 0.000001 else {
            saveOriginalScaling(nil); setLastAppliedScaling(nil)
            accelerationStatus = "Preserved the mouse acceleration changed outside Sieghart."; return true
        }
        guard accelerationBackend.writeScaling(original) else {
            accelerationStatus = "Could not restore previous mouse acceleration. Click Restore original Mac acceleration to retry."; return false
        }
        saveOriginalScaling(nil); setLastAppliedScaling(nil)
        accelerationStatus = "Mouse acceleration control is off (restored previous Mac setting)."; return true
    }
    func configureAcceleration() {
        let active = started && !asleep && !locked && sessionActive
        guard active, pointerAcceleration.enabled else {
            if savedOriginalScaling != nil { _ = restoreOwnedAcceleration() }
            else { accelerationStatus = pointerAcceleration.enabled ? "Mouse acceleration paused while the Mac sleeps or is locked" : "Mouse acceleration control is off" }
            return
        }
        guard let current = accelerationBackend.readScaling(), current.isFinite else {
            accelerationStatus = "Could not read current macOS mouse acceleration; nothing was changed."; return
        }
        if savedOriginalScaling != nil, let applied = lastAppliedScaling, abs(current - applied) >= 0.000001 {
            saveOriginalScaling(nil); setLastAppliedScaling(nil); pointerAcceleration.enabled = false
            accelerationStatus = "Preserved mouse acceleration changed outside Sieghart. Re-enable to apply again."; return
        }
        if savedOriginalScaling == nil || lastAppliedScaling == nil { saveOriginalScaling(current) }
        if accelerationBackend.writeScaling(pointerAcceleration.targetScaling) {
            setLastAppliedScaling(pointerAcceleration.targetScaling)
            accelerationStatus = pointerAcceleration.flatCurve ?
                "Linear pointer curve active (acceleration off). Original setting saved for restore." :
                String(format: "Mouse acceleration set to %.2fx. Original setting saved for restore.", pointerAcceleration.clampedSpeed)
        } else { accelerationStatus = "Could not update mouse acceleration. Retry or restore original." }
    }
    func restoreOriginalAcceleration() {
        if pointerAcceleration.enabled { pointerAcceleration.enabled = false }
        else { _ = restoreOwnedAcceleration() }
    }
    func configure() {
        generation += 1; backend.stop(); health?.cancel(); health = nil; inputHint = nil
        guard started, options.enabled else { status = "Scroll utilities are off"; return }
        guard !asleep, !locked, sessionActive else { status = "Scroll paused while the Mac sleeps or is locked"; return }
        guard trusted() else { status = "Allow Accessibility, then retry"; return }
        guard !hasConflict else { status = "Modifier conflicts with a modifier-only shortcut. Choose another modifier or shortcut."; return }
        let current = generation
        do {
            try backend.start(transform: { [weak self] input in
                guard let self, self.started, self.generation == current else { return input }
                guard self.trusted(), !self.hasConflict else { self.configure(); return input }
                let hint: String?
                if input.continuous && self.options.directionalEnabled && !self.options.affectsContinuous {
                    hint = "This input is unchanged. Turn on Include trackpad and smooth-scroll mice to apply your scroll options."
                } else if input.continuous && !self.options.directionalEnabled && self.options.wheelCurveEnabled {
                    hint = "Linear and smooth wheel curves apply to discrete mouse wheels. Trackpad gestures keep their native curve."
                } else {
                    hint = nil
                }
                if self.inputHint != hint { self.inputHint = hint }
                return ScrollTransform.apply(input, options: self.options)
            }, interrupted: { [weak self] in
                guard let self, self.started, self.generation == current else { return }
                self.configure()
            })
            status = "Scroll utilities are ready"
            health = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self, self.generation == current else { return }
                    if !self.trusted() || self.hasConflict { self.configure(); return }
                }
            }
        } catch { generation += 1; backend.stop(); status = "Scroll unavailable. Retry after checking Accessibility." }
    }
    func stop() {
        started = false; generation += 1; health?.cancel(); health = nil; backend.stop()
        _ = restoreOwnedAcceleration()
        for (center, token) in observers { center.removeObserver(token) }; observers = []
        status = "Scroll utilities are off"; accelerationStatus = "Mouse acceleration control is off"; inputHint = nil
    }
}
