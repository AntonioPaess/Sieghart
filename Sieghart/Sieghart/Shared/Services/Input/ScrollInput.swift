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
    var inverted = false
    var horizontal = false
    var affectsContinuous = false
    var modifier: ScrollModifier = .shift
    var enabled: Bool { inverted || horizontal }
}
enum ScrollTransform {
    static func apply(_ input: ScrollSample, options: ScrollOptions) -> ScrollSample {
        guard options.enabled, !input.continuous || options.affectsContinuous else { return input }
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
        if redirect { result.flags &= ~options.modifier.flags }
        return result
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
    @Published private(set) var status = "Scroll utilities are off"
    @Published private(set) var inputHint: String?
    var shortcutChords: () -> [ShortcutChord] = { [] }
    private let defaults: UserDefaults
    private let backend: any ScrollInputBackend
    private let trusted: () -> Bool
    private let requestAccess: () -> Void
    private var started = false
    private var asleep = false
    private var locked = false
    private var sessionActive = true
    private var generation = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var health: Task<Void, Never>?
    init(defaults: UserDefaults = .standard, backend: (any ScrollInputBackend)? = nil,
         trusted: @escaping () -> Bool = AXIsProcessTrusted,
         requestAccess: @escaping () -> Void = { AccessibilityAccess.request() }) {
        self.defaults = defaults; self.backend = backend ?? NativeScrollInputBackend()
        self.trusted = trusted; self.requestAccess = requestAccess
        options = ScrollOptions(inverted: defaults.bool(forKey: "input.scroll.inverted"),
            horizontal: defaults.bool(forKey: "input.scroll.horizontal"),
            affectsContinuous: defaults.bool(forKey: "input.scroll.continuous"),
            modifier: ScrollModifier(rawValue: defaults.string(forKey: "input.scroll.modifier") ?? "") ?? .shift)
    }
    private func persist() {
        defaults.set(options.inverted, forKey: "input.scroll.inverted")
        defaults.set(options.horizontal, forKey: "input.scroll.horizontal")
        defaults.set(options.affectsContinuous, forKey: "input.scroll.continuous")
        defaults.set(options.modifier.rawValue, forKey: "input.scroll.modifier")
    }
    func start(observeSystem: Bool = true) {
        guard !started else { return }; started = true; configure()
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
    func setSleeping(_ value: Bool) { asleep = value; if started { configure() } }
    func setLocked(_ value: Bool) { locked = value; if started { configure() } }
    func setSessionActive(_ value: Bool) { sessionActive = value; if started { configure() } }
    func allowAccess() { requestAccess(); if started { configure() } }
    var hasConflict: Bool { options.horizontal && options.modifier.conflicts(with: shortcutChords()) }
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
                let hint: String? = input.continuous && !self.options.affectsContinuous ?
                    "This input is unchanged. Turn on Include trackpad and smooth-scroll mice to apply your scroll options." : nil
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
        for (center, token) in observers { center.removeObserver(token) }; observers = []
        status = "Scroll utilities are off"; inputHint = nil
    }
}
