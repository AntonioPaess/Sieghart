import AppKit
import ApplicationServices
import Combine
import Darwin

struct TrackpadContact: Sendable { let id: Int32; let x: Double; let y: Double }
struct ThreeFingerTap: Sendable {
    private var began: Double?
    private var origins: [Int32: TrackpadContact] = [:]
    private var reachedThree = false
    private var rejected = false
    private var lastClick = -Double.infinity
    mutating func reset() { began = nil; origins = [:]; reachedThree = false; rejected = false }
    mutating func consume(_ contacts: [TrackpadContact], at time: Double) -> Bool {
        guard time.isFinite else { reset(); return false }
        if contacts.isEmpty {
            let click = reachedThree && !rejected && began.map { (0...0.3).contains(time - $0) } == true && time - lastClick > 0.2
            reset(); if click { lastClick = time }; return click
        }
        if began == nil { began = time }
        if contacts.count > 3 || time - (began ?? time) > 0.3 { rejected = true }
        for contact in contacts {
            guard contact.x.isFinite, contact.y.isFinite, (0...1).contains(contact.x), (0...1).contains(contact.y) else { rejected = true; continue }
            if let old = origins[contact.id] {
                if hypot(contact.x - old.x, contact.y - old.y) > 0.035 { rejected = true }
            } else { origins[contact.id] = contact }
        }
        if contacts.count == 3 { reachedThree = true }
        if origins.count > 3 { rejected = true }
        return false
    }
}

@MainActor protocol MiddleClickBackend: AnyObject {
    func start(onTap: @escaping @Sendable () -> Void) throws
    func stop()
}
private enum TouchBackendError: LocalizedError {
    case unavailable, noDevice
    var errorDescription: String? { self == .unavailable ? "Three-finger input is unavailable on this version of macOS." : "No supported trackpad was found." }
}
// No framework is opened until the user enables this optional Mac utility.
// Raw contact access is an undocumented macOS capability, excluded from the
// Student Challenge package. Fail closed when symbols or devices are absent.
private typealias ContactCallback = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, Int32, Double, Int32) -> Void
private final class TouchFrames: @unchecked Sendable {
    static let shared = TouchFrames()
    private let lock = NSLock()
    private var active = Set<UInt>()
    private var recognizers: [UInt: ThreeFingerTap] = [:]
    private var onTap: (@Sendable () -> Void)?
    func configure(devices: [UnsafeRawPointer], tap: @escaping @Sendable () -> Void) { lock.withLock { active = Set(devices.map { UInt(bitPattern: $0) }); recognizers = [:]; onTap = tap } }
    func clear() { lock.withLock { active = []; recognizers = [:]; onTap = nil } }
    func receive(device: UnsafeRawPointer?, data: UnsafeRawPointer?, count: Int32, time: Double) {
        guard let device, (0...8).contains(count), count == 0 || data != nil else { return }
        let key = UInt(bitPattern: device)
        let action: (@Sendable () -> Void)? = lock.withLock {
            guard active.contains(key) else { return nil }
            var contacts: [TrackpadContact] = []
            // macOS contact ABI: 96-byte record, ID at 16, stage at 20,
            // normalized x/y at 32/36. Copy scalars; never retain device memory.
            if let data { for index in 0..<Int(count) {
                let record = data.advanced(by: index * 96), stage = record.loadUnaligned(fromByteOffset: 20, as: Int32.self)
                if stage == 3 || stage == 4 {
                    contacts.append(TrackpadContact(id: record.loadUnaligned(fromByteOffset: 16, as: Int32.self), x: Double(record.loadUnaligned(fromByteOffset: 32, as: Float.self)), y: Double(record.loadUnaligned(fromByteOffset: 36, as: Float.self))))
                }
            } }
            var recognizer = recognizers[key] ?? ThreeFingerTap()
            let click = recognizer.consume(contacts, at: time); recognizers[key] = recognizer
            return click ? onTap : nil
        }
        action?()
    }
}
private let contactCallback: ContactCallback = { device, data, count, time, _ in TouchFrames.shared.receive(device: device, data: data, count: count, time: time) }

@MainActor final class SystemMiddleClickBackend: MiddleClickBackend {
    private typealias List = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeRawPointer, ContactCallback) -> Bool
    private typealias Start = @convention(c) (UnsafeRawPointer, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeRawPointer) -> Void
    private var library: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var devices: [UnsafeRawPointer] = []
    private var unregister: Register?
    private var stopDevice: Stop?
    func start(onTap: @escaping @Sendable () -> Void) throws {
        stop()
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL) else { throw TouchBackendError.unavailable }
        library = handle
        guard let listSymbol = dlsym(handle, "MTDeviceCreateList"), let registerSymbol = dlsym(handle, "MTRegisterContactFrameCallback"), let startSymbol = dlsym(handle, "MTDeviceStart"), let stopSymbol = dlsym(handle, "MTDeviceStop"), let unregisterSymbol = dlsym(handle, "MTUnregisterContactFrameCallback") else { stop(); throw TouchBackendError.unavailable }
        let create = unsafeBitCast(listSymbol, to: List.self), register = unsafeBitCast(registerSymbol, to: Register.self), startDevice = unsafeBitCast(startSymbol, to: Start.self)
        stopDevice = unsafeBitCast(stopSymbol, to: Stop.self); unregister = unsafeBitCast(unregisterSymbol, to: Register.self)
        guard let list = create()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else { stop(); throw TouchBackendError.noDevice }
        deviceList = list
        let candidates = (0..<CFArrayGetCount(list)).compactMap { CFArrayGetValueAtIndex(list, $0) }
        TouchFrames.shared.configure(devices: candidates, tap: onTap)
        for device in candidates where register(device, contactCallback) { devices.append(device); startDevice(device, 0) }
        guard !devices.isEmpty else { stop(); throw TouchBackendError.noDevice }
    }
    func stop() {
        TouchFrames.shared.clear()
        for device in devices { stopDevice?(device); _ = unregister?(device, contactCallback) }
        devices = []; deviceList = nil; unregister = nil; stopDevice = nil
        if let library { dlclose(library); self.library = nil }
    }
}

@MainActor final class MiddleClickController: ObservableObject {
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "gestures.middleClick"); if started { configure() } } }
    @Published private(set) var status = "Three-finger middle click is off"
    private let defaults: UserDefaults
    private let backend: any MiddleClickBackend
    private let trusted: () -> Bool
    private let requestAccess: () -> Void
    private let emit: () -> Void
    private var started = false
    private var suspended = false
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    init(defaults: UserDefaults = .standard, backend: (any MiddleClickBackend)? = nil, trusted: @escaping () -> Bool = AXIsProcessTrusted, requestAccess: @escaping () -> Void = {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }, emit: @escaping () -> Void = {
        guard let location = CGEvent(source: nil)?.location else { return }
        let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: location, mouseButton: .center)
        let up = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: location, mouseButton: .center)
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }) {
        self.defaults = defaults; self.backend = backend ?? SystemMiddleClickBackend(); self.trusted = trusted; self.requestAccess = requestAccess; self.emit = emit
        isEnabled = defaults.bool(forKey: "gestures.middleClick")
    }
    func start(observeSystem: Bool = true) {
        guard !started else { return }; started = true; configure()
        guard observeSystem else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                self?.suspended = name == NSWorkspace.willSleepNotification || name == NSWorkspace.sessionDidResignActiveNotification; self?.configure()
            } })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.configure() } })
    }
    func allowAccess() { requestAccess(); configure() }
    func configure() {
        generation += 1; backend.stop()
        guard isEnabled else { status = "Three-finger middle click is off"; return }
        guard !suspended else { status = "Paused while the Mac sleeps or is locked"; return }
        guard trusted() else { status = "Allow Accessibility, then retry"; return }
        let current = generation
        do {
            try backend.start { [weak self] in Task { @MainActor in
                guard let self, self.isEnabled, !self.suspended, self.generation == current, self.trusted() else { return }
                self.emit()
            } }
            status = "Three-finger tap is ready"
        } catch { status = error.localizedDescription }
    }
}
