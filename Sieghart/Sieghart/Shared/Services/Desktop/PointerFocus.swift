import AppKit

enum PointerFocusEvent { case moved(CGPoint), cancel }
@MainActor protocol PointerFocusMonitoring: AnyObject {
    func start(_ receive: @escaping @MainActor (PointerFocusEvent) -> Void) -> Bool
    func stop()
    func location() -> CGPoint?
    var buttonsPressed: Bool { get }
}
@MainActor final class NativePointerFocusMonitor: PointerFocusMonitoring {
    private var global: Any?
    private var local: Any?
    func start(_ receive: @escaping @MainActor (PointerFocusEvent) -> Void) -> Bool {
        stop()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let handler: (NSEvent) -> Void = { event in
            MainActor.assumeIsolated {
                if event.type == .mouseMoved, let point = event.cgEvent?.location { receive(.moved(point)) }
                else { receive(.cancel) }
            }
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        guard global != nil else { stop(); return false }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            handler(event); return event
        }
        guard local != nil else { stop(); return false }
        return true
    }
    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil
    }
    func location() -> CGPoint? {
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return nil }
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: primaryTop - point.y)
    }
    var buttonsPressed: Bool { NSEvent.pressedMouseButtons != 0 }
}

@MainActor protocol PointerDwellScheduling: AnyObject {
    func schedule(_ perform: @escaping @MainActor () -> Void)
    func cancel()
}
@MainActor final class NativePointerDwellScheduler: PointerDwellScheduling {
    private var task: Task<Void, Never>?
    func schedule(_ perform: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled else { return }
            perform()
        }
    }
    func cancel() { task?.cancel(); task = nil }
}
