import AppKit
import ApplicationServices

enum MouseButtonPhase { case down, up, dragged }
struct MouseButtonSample {
    let button: Int
    let phase: MouseButtonPhase
    var modifiers: UInt64 = 0
    var hasModifiers: Bool {
        modifiers & (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue |
                     CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskSecondaryFn.rawValue) != 0
    }
}
@MainActor protocol MouseButtonMonitoring: AnyObject {
    func start(handle: @escaping @MainActor (MouseButtonSample) -> Bool, interrupted: @escaping @MainActor () -> Void) throws
    func stop()
    func isPressed(_ button: Int) -> Bool
}
@MainActor final class NativeMouseButtonMonitor: MouseButtonMonitoring {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var handle: (@MainActor (MouseButtonSample) -> Bool)?
    private var interrupted: (@MainActor () -> Void)?
    static func sample(_ event: CGEvent, type: CGEventType) -> MouseButtonSample? {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        guard (3...31).contains(button) else { return nil }
        let phase: MouseButtonPhase
        switch type {
        case .otherMouseDown: phase = .down
        case .otherMouseUp: phase = .up
        case .otherMouseDragged: phase = .dragged
        default: return nil
        }
        return MouseButtonSample(button: Int(button), phase: phase, modifiers: event.flags.rawValue)
    }
    func start(handle: @escaping @MainActor (MouseButtonSample) -> Bool, interrupted: @escaping @MainActor () -> Void) throws {
        stop(); self.handle = handle; self.interrupted = interrupted
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consumed = MainActor.assumeIsolated { () -> Bool in
                    let monitor = Unmanaged<NativeMouseButtonMonitor>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        let recover = monitor.interrupted
                        DispatchQueue.main.async { recover?() }
                    }
                    guard let sample = NativeMouseButtonMonitor.sample(event, type: type) else { return false }
                    return monitor.handle?(sample) ?? false
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { stop(); throw CocoaError(.featureUnsupported) }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        source = nil; port = nil; handle = nil; interrupted = nil
    }
    func isPressed(_ button: Int) -> Bool {
        guard (3...31).contains(button), let value = CGMouseButton(rawValue: UInt32(button)) else { return false }
        return CGEventSource.buttonState(.combinedSessionState, button: value)
    }
}
