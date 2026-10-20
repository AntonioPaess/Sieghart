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
    private var deadline: ContinuousClock.Instant?
    private var perform: (@MainActor () -> Void)?
    private let delay: Duration
    private(set) var workersStarted = 0
    init(delay: Duration = .milliseconds(300)) { self.delay = delay }
    func schedule(_ perform: @escaping @MainActor () -> Void) {
        deadline = .now + delay; self.perform = perform
        guard task == nil else { return }
        workersStarted += 1
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let next = self?.deadline else { return }
                do { try await Task.sleep(until: next, clock: .continuous) } catch { return }
                guard !Task.isCancelled, let self else { return }
                // Motion only updates the deadline/closure; one worker sleeps.
                guard let latest = deadline, ContinuousClock.now >= latest else { continue }
                let action = self.perform
                task = nil; deadline = nil; self.perform = nil
                action?(); return
            }
        }
    }
    func cancel() { task?.cancel(); task = nil; deadline = nil; perform = nil }
}
