import AppKit
import ApplicationServices
import Combine

@MainActor final class DesktopController: ObservableObject {
    @Published private(set) var apps: [DesktopApp] = []
    @Published private(set) var windows: [DesktopWindow] = []
    @Published var selectedID: UUID?
    @Published private(set) var status = "Refresh to list apps and windows."
    @Published private(set) var snapStatus = "Edge snapping is off."
    @Published private(set) var canUndo = false
    @Published private(set) var focusStatus = "Pointer focus is off."
    @Published var focusFollowsPointer: Bool {
        didSet { defaults.set(focusFollowsPointer, forKey: "desktop.focusFollowsPointer"); configureMonitor() }
    }
    @Published var edgeSnapping: Bool {
        didSet { defaults.set(edgeSnapping, forKey: "desktop.edgeSnapping"); configureMonitor() }
    }
    let dockSpaces: DockSpacesController
    private struct UndoEntry { let id: UUID; let before: CGRect; let after: CGRect }
    private let backend: any DesktopManaging
    private let monitor: any DesktopDragMonitoring
    private let pointer: any PointerFocusMonitoring
    private let dwell: any PointerDwellScheduling
    private let defaults: UserDefaults
    private let trusted: () -> Bool
    private let requestAccess: () -> Void
    private var history: [UndoEntry] = []
    private var drag: DesktopWindow?
    private var dragOrigin: CGPoint?
    private var pointerDragged = false
    private var started = false
    private var asleep = false
    private var locked = false
    private var sessionActive = true
    private var generation = 0
    private var focusTicket = 0
    private var focusMonitoring = false
    private var snapMonitoring = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    init(defaults: UserDefaults = .standard, backend: (any DesktopManaging)? = nil, monitor: (any DesktopDragMonitoring)? = nil,
         pointer: (any PointerFocusMonitoring)? = nil, dwell: (any PointerDwellScheduling)? = nil,
         dockSpaces: DockSpacesController? = nil,
         trusted: @escaping () -> Bool = AXIsProcessTrusted,
         requestAccess: @escaping () -> Void = { AccessibilityAccess.request() }) {
        self.defaults = defaults; self.backend = backend ?? NativeDesktopBackend(); self.monitor = monitor ?? NativeDesktopDragMonitor()
        self.pointer = pointer ?? NativePointerFocusMonitor(); self.dwell = dwell ?? NativePointerDwellScheduler()
        self.dockSpaces = dockSpaces ?? DockSpacesController(defaults: defaults, trusted: trusted)
        self.trusted = trusted; self.requestAccess = requestAccess
        edgeSnapping = defaults.bool(forKey: "desktop.edgeSnapping")
        focusFollowsPointer = defaults.bool(forKey: "desktop.focusFollowsPointer")
    }
    private var available: Bool { started && !asleep && !locked && sessionActive }
    private func permitted() -> Bool {
        guard available else { status = "Window tools are paused."; return false }
        guard trusted() else {
            apps = []; windows = []; selectedID = nil; drag = nil
            status = "Allow Accessibility, then refresh."; configureMonitor(); return false
        }
        return true
    }
    func allowAccess() {
        requestAccess(); configureMonitor(); dockSpaces.configureZoomInterceptor()
        status = trusted() ? "Accessibility is allowed. Refresh the list to choose a window." : "Enable this copy of Sieghart in macOS Privacy & Security, then return and refresh."
    }
    func refresh() {
        guard permitted() else { return }
        let snapshot = backend.discover()
        apps = snapshot.apps; windows = snapshot.windows
        dockSpaces.observeSnapshot(snapshot)
        if !windows.contains(where: { $0.id == selectedID }) { selectedID = nil }
        status = snapshot.limited ? "Partial list: refresh again if a window is missing. Full-screen and minimized windows are excluded." :
            "\(apps.count) apps, \(windows.count) windows. Full-screen and minimized windows are excluded."
        configureMonitor()
    }
    func activate(app: DesktopApp) {
        guard permitted() else { return }
        status = backend.activate(app: app) ? "Activation requested for \(app.name)." : "App is no longer available. Refresh the list."
    }
    func activate(window id: UUID) {
        guard permitted() else { return }
        status = backend.activate(window: id) ? "Window activation requested." : "Could not bring this window forward. Refresh the list."
    }
    func apply(_ layout: WindowLayout) {
        guard permitted() else { return }
        guard let id = selectedID, let window = backend.window(id), let screen = WindowGeometry.screen(for: window.frame, in: backend.screens()) else {
            status = "Select an available window and refresh if needed."; return
        }
        apply(layout, to: window, on: screen)
    }
    private func apply(_ layout: WindowLayout, to window: DesktopWindow, on screen: DesktopScreen) {
        guard let desired = WindowGeometry.frame(layout, current: window.frame, usable: screen.usable) else { status = "No usable display is available."; return }
        switch backend.setFrame(desired, of: window.id) {
        case .applied(let actual):
            guard WindowGeometry.valid(actual) else { status = "The app returned an invalid window frame. Refresh the list."; return }
            if !WindowGeometry.matches(actual, window.frame) {
                history.append(UndoEntry(id: window.id, before: window.frame, after: actual))
                if history.count > 32 { history.removeFirst(history.count - 32) }
            }
            canUndo = !history.isEmpty
            if let index = windows.firstIndex(where: { $0.id == window.id }) { windows[index].frame = actual }
            status = WindowGeometry.matches(actual, desired) ? "Applied \(layout.title.lowercased())." : "The app adjusted the requested layout to its window limits."
        case .failed(let message): status = message
        }
    }
    func undo() {
        guard permitted(), let entry = history.popLast() else { return }
        canUndo = !history.isEmpty
        guard let current = backend.window(entry.id), WindowGeometry.matches(current.frame, entry.after) else {
            status = "Undo skipped: this window was closed or changed after the layout."; return
        }
        switch backend.setFrame(entry.before, of: entry.id) {
        case .applied(let actual):
            if let index = windows.firstIndex(where: { $0.id == entry.id }) { windows[index].frame = actual }
            status = WindowGeometry.matches(actual, entry.before) ? "Previous frame restored." : "The app adjusted the restored frame to its window limits."
        case .failed(let message):
            if let current = backend.window(entry.id), WindowGeometry.matches(current.frame, entry.after) {
                history.append(entry); canUndo = true
            }
            status = message
        }
    }
    func start(observeSystem: Bool = true) {
        guard !started else { return }; started = true; dockSpaces.start(); configureMonitor()
        guard observeSystem else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == NSWorkspace.willSleepNotification { self?.setSleeping(true) }
                    if name == NSWorkspace.didWakeNotification { self?.setSleeping(false) }
                    if name == NSWorkspace.sessionDidResignActiveNotification { self?.setSessionActive(false) }
                    if name == NSWorkspace.sessionDidBecomeActiveNotification { self?.setSessionActive(true) }
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
    func setSleeping(_ value: Bool) { asleep = value; dockSpaces.setSleeping(value); configureMonitor() }
    func setLocked(_ value: Bool) { locked = value; dockSpaces.setLocked(value); configureMonitor() }
    func setSessionActive(_ value: Bool) { sessionActive = value; dockSpaces.setSessionActive(value); configureMonitor() }
    func retrySnapping() { configureMonitor() }
    func retryPointerFocus() { configureMonitor() }
    private func configureMonitor() {
        generation += 1; snapMonitoring = false; monitor.stop(); drag = nil; dragOrigin = nil; pointerDragged = false
        focusMonitoring = false; pointer.stop(); cancelFocusWait(); configurePointerFocus()
        guard started, edgeSnapping else { snapStatus = "Edge snapping is off."; return }
        guard available else { snapStatus = "Edge snapping is paused."; return }
        guard trusted() else { snapStatus = "Allow Accessibility, then retry edge snapping."; return }
        let current = generation
        let installed = monitor.start { [weak self] phase, point in
            guard let self, self.generation == current, self.snapMonitoring, self.available, self.edgeSnapping else { return }
            guard self.trusted() else { self.configureMonitor(); return }
            switch phase {
            case .down:
                self.drag = self.backend.window(at: point); self.dragOrigin = point; self.pointerDragged = false
            case .dragged:
                if let origin = self.dragOrigin, hypot(point.x - origin.x, point.y - origin.y) > 4 { self.pointerDragged = true }
            case .up:
                let candidate = self.pointerDragged ? self.drag : nil
                self.drag = nil; self.dragOrigin = nil; self.pointerDragged = false
                guard let candidate, let moved = self.backend.window(candidate.id), candidate.app.id == moved.app.id,
                      WindowGeometry.movedWithoutResize(from: candidate.frame, to: moved.frame),
                      let (screen, layout) = WindowGeometry.snap(at: point, screens: self.backend.screens()) else { return }
                // Undo restores the actual dropped frame, not the frame from
                // before the user's own drag.
                self.apply(layout, to: moved, on: screen)
            }
        }
        snapMonitoring = installed
        if !installed { monitor.stop() }
        snapStatus = installed ? "Drag a window to an edge or corner, then release. Top edge fills the usable screen." : "Edge snapping unavailable. Check Accessibility and retry."
    }
    private func cancelFocusWait() { focusTicket += 1; dwell.cancel() }
    private func configurePointerFocus() {
        guard started, focusFollowsPointer else { focusStatus = "Pointer focus is off."; return }
        guard available else { focusStatus = "Pointer focus is paused."; return }
        guard trusted() else { focusStatus = "Allow Accessibility, then retry pointer focus."; return }
        let current = generation
        let installed = pointer.start { [weak self] event in
            guard let self, self.generation == current, self.focusMonitoring, self.available, self.focusFollowsPointer else { return }
            self.cancelFocusWait()
            guard self.trusted() else { self.configureMonitor(); return }
            guard case .moved(let point) = event, point.x.isFinite, point.y.isFinite, !self.pointer.buttonsPressed else { return }
            let ticket = self.focusTicket
            self.dwell.schedule { [weak self] in self?.focus(at: point, generation: current, ticket: ticket) }
        }
        if !installed { pointer.stop(); cancelFocusWait() }
        focusMonitoring = installed
        focusStatus = installed ? "Rest the pointer on another window for 0.3 seconds to bring it forward. Works with a mouse or trackpad." : "Pointer focus unavailable. Check Accessibility and retry."
    }
    private func focus(at point: CGPoint, generation current: Int, ticket: Int) {
        guard generation == current, focusMonitoring, focusTicket == ticket,
              available, focusFollowsPointer else { return }
        guard trusted() else { configureMonitor(); return }
        guard !pointer.buttonsPressed,
              let location = pointer.location(), hypot(location.x - point.x, location.y - point.y) <= 2,
              let window = backend.window(at: location), window.frame.contains(location),
              let refreshed = backend.window(window.id), refreshed.app.id == window.app.id,
              refreshed.frame.contains(location) else { return }
        guard let latestPoint = pointer.location(), hypot(latestPoint.x - point.x, latestPoint.y - point.y) <= 2,
              trusted(), !pointer.buttonsPressed else { return }
        if backend.isFocused(window: window.id) { return }
        guard let finalPoint = pointer.location(), hypot(finalPoint.x - point.x, finalPoint.y - point.y) <= 2,
              !pointer.buttonsPressed, trusted(), backend.window(at: finalPoint)?.id == window.id else { return }
        focusStatus = backend.activate(window: window.id) ? "Focus requested for \(window.app.name)." : "Could not focus this window. Move the pointer away and try again."
    }
    func stop() {
        started = false; dockSpaces.stop(); configureMonitor()
        for (center, token) in observers { center.removeObserver(token) }; observers = []
        apps = []; windows = []; selectedID = nil; history = []; canUndo = false
        status = "Window tools are paused."
    }
}
