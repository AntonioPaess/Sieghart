import AppKit
import ApplicationServices

struct DesktopApp: Equatable, Identifiable, Sendable {
    let pid: Int32
    let launchedAt: Date?
    var name: String
    var id: String { "\(pid):\(launchedAt?.timeIntervalSince1970 ?? 0)" }
}
struct DesktopWindow: Equatable, Identifiable, Sendable {
    let id: UUID
    var app: DesktopApp
    var title: String
    var frame: CGRect
}
struct DesktopSnapshot {
    var apps: [DesktopApp] = []
    var windows: [DesktopWindow] = []
    var limited = false
}
@MainActor protocol DesktopManaging: AnyObject {
    func discover() -> DesktopSnapshot
    func window(_ id: UUID) -> DesktopWindow?
    func window(at point: CGPoint) -> DesktopWindow?
    func screens() -> [DesktopScreen]
    func setFrame(_ frame: CGRect, of id: UUID) -> WindowWriteResult
    func activate(app: DesktopApp) -> Bool
    func activate(window: UUID) -> Bool
}

@MainActor final class NativeDesktopBackend: DesktopManaging {
    private struct Entry {
        let element: AXUIElement
        let app: DesktopApp
    }
    private var entries: [UUID: Entry] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func running(_ app: DesktopApp) -> NSRunningApplication? {
        guard app.pid != ownPID, let launchedAt = app.launchedAt,
              let running = NSRunningApplication(processIdentifier: app.pid),
              !running.isTerminated, running.launchDate == launchedAt else { return nil }
        return running
    }
    private func app(_ running: NSRunningApplication) -> DesktopApp {
        DesktopApp(pid: running.processIdentifier, launchedAt: running.launchDate, name: running.localizedName ?? "Application")
    }
    private func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = value(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        let result = CGRect(origin: origin, size: size)
        return WindowGeometry.valid(result) ? result : nil
    }
    private func summary(_ entry: Entry, id: UUID) -> DesktopWindow? {
        guard running(entry.app) != nil,
              value(entry.element, kAXRoleAttribute) as? String == kAXWindowRole,
              value(entry.element, kAXMinimizedAttribute) as? Bool != true,
              value(entry.element, "AXFullScreen") as? Bool != true,
              let frame = frame(entry.element) else { return nil }
        return DesktopWindow(id: id, app: entry.app, title: value(entry.element, kAXTitleAttribute) as? String ?? "Untitled window", frame: frame)
    }
    private func register(_ window: AXUIElement, app: DesktopApp) -> DesktopWindow? {
        AXUIElementSetMessagingTimeout(window, 0.08)
        let id = entries.first { $0.value.app.id == app.id && CFEqual($0.value.element, window) }?.key ?? UUID()
        let entry = Entry(element: window, app: app)
        guard let record = summary(entry, id: id) else { return nil }
        entries[id] = entry
        // Bound retained AX handles even if many windows open between refreshes.
        if entries.count > 256, let obsolete = entries.keys.first(where: { $0 != id }) { entries.removeValue(forKey: obsolete) }
        return record
    }
    func discover() -> DesktopSnapshot {
        guard AXIsProcessTrusted() else { return DesktopSnapshot() }
        var result = DesktopSnapshot(), retained: Set<UUID> = []
        let deadline = ContinuousClock.now + .seconds(1)
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        result.apps = apps.map(app)
        for running in apps.prefix(64) {
            guard ContinuousClock.now < deadline, result.windows.count < 128 else { result.limited = true; break }
            let application = AXUIElementCreateApplication(running.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.08)
            guard let windows = value(application, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in windows.prefix(32) {
                guard ContinuousClock.now < deadline, result.windows.count < 128 else { result.limited = true; break }
                if let record = register(window, app: app(running)) { retained.insert(record.id); result.windows.append(record) }
            }
            if windows.count > 32 { result.limited = true }
        }
        if apps.count > 64 { result.limited = true }
        // Keep IDs for still-listed windows, including old handles while a bounded
        // scan is incomplete. Every later operation revalidates process and AX.
        if !result.limited { entries = entries.filter { retained.contains($0.key) } }
        return result
    }
    func window(_ id: UUID) -> DesktopWindow? {
        guard AXIsProcessTrusted(), let entry = entries[id] else { return nil }
        return summary(entry, id: id)
    }
    func window(at point: CGPoint) -> DesktopWindow? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.08)
        guard let window = value(hit, kAXRoleAttribute) as? String == kAXWindowRole ? hit : element(value(hit, kAXWindowAttribute)) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid != ownPID,
              let application = NSRunningApplication(processIdentifier: pid), application.activationPolicy == .regular else { return nil }
        return register(window, app: app(application))
    }
    func screens() -> [DesktopScreen] {
        let screens = NSScreen.screens
        guard let primaryTop = screens.first?.frame.maxY else { return [] }
        return screens.map { DesktopScreen(frame: DesktopScreen.accessibilityRect($0.frame, primaryTop: primaryTop),
                                           usable: DesktopScreen.accessibilityRect($0.visibleFrame, primaryTop: primaryTop)) }
    }
    func setFrame(_ desired: CGRect, of id: UUID) -> WindowWriteResult {
        guard AXIsProcessTrusted(), let entry = entries[id], summary(entry, id: id) != nil else { return .failed("Window is no longer available. Refresh the list.") }
        var positionSettable = DarwinBoolean(false), sizeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(entry.element, kAXPositionAttribute as CFString, &positionSettable) == .success, positionSettable.boolValue,
              AXUIElementIsAttributeSettable(entry.element, kAXSizeAttribute as CFString, &sizeSettable) == .success, sizeSettable.boolValue else {
            return .failed("This window does not support moving and resizing.")
        }
        return WindowFrameWriter.write(desired, read: { self.frame(entry.element) }, position: { point in
            var point = point
            guard AXIsProcessTrusted(), let value = AXValueCreate(.cgPoint, &point) else { return false }
            return AXUIElementSetAttributeValue(entry.element, kAXPositionAttribute as CFString, value) == .success
        }, size: { size in
            var size = size
            guard AXIsProcessTrusted(), let value = AXValueCreate(.cgSize, &size) else { return false }
            return AXUIElementSetAttributeValue(entry.element, kAXSizeAttribute as CFString, value) == .success
        })
    }
    func activate(app: DesktopApp) -> Bool {
        guard AXIsProcessTrusted(), let running = running(app) else { return false }
        return running.activate(options: [])
    }
    func activate(window id: UUID) -> Bool {
        guard AXIsProcessTrusted(), let entry = entries[id], summary(entry, id: id) != nil, activate(app: entry.app) else { return false }
        return AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString) == .success
    }
}

enum DesktopPointerPhase { case down, dragged, up }
@MainActor protocol DesktopDragMonitoring: AnyObject {
    func start(_ receive: @escaping @MainActor (DesktopPointerPhase, CGPoint) -> Void) -> Bool
    func stop()
}
@MainActor final class NativeDesktopDragMonitor: DesktopDragMonitoring {
    private var monitor: Any?
    func start(_ receive: @escaping @MainActor (DesktopPointerPhase, CGPoint) -> Void) -> Bool {
        stop()
        // A global monitor observes other apps only; it never consumes or posts
        // mouse events. NSEvent delivers its handler on the main thread.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            MainActor.assumeIsolated {
                guard let point = event.cgEvent?.location else { return }
                let phase: DesktopPointerPhase = event.type == .leftMouseDown ? .down : event.type == .leftMouseDragged ? .dragged : .up
                receive(phase, point)
            }
        }
        return monitor != nil
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}
