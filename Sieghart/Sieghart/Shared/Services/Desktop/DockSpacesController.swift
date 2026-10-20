import AppKit
import ApplicationServices
import Combine

struct DockWindowPreview: Equatable, Identifiable, Sendable {
    let id: UUID
    var app: DesktopApp
    var title: String
    var frame: CGRect
    var isMinimized: Bool
    var aspectRatio: CGFloat {
        guard frame.width > 0, frame.height > 0 else { return 1.6 }
        return min(max(frame.width / frame.height, 0.5), 3.0)
    }
}

enum DockClickBehavior: String, CaseIterable, Codable, Sendable {
    case systemDefault, minimizeOrRestore, hideActiveApp, bringAllForward
    var title: String {
        switch self {
        case .systemDefault: "Keep macOS default"
        case .minimizeOrRestore: "Minimize or restore windows"
        case .hideActiveApp: "Hide active app"
        case .bringAllForward: "Bring all app windows forward"
        }
    }
}

struct GreenZoomTarget: Equatable, Sendable {
    let window: DesktopWindow
    let usableScreen: CGRect
}

@MainActor protocol SpacesPreferenceBackend: AnyObject {
    func readMruSpaces() -> Bool?
    @discardableResult func writeMruSpaces(_ value: Bool) -> Bool
}

@MainActor final class NativeSpacesPreferenceBackend: SpacesPreferenceBackend {
    private let domain = "com.apple.dock" as CFString
    private let key = "mru-spaces" as CFString
    func readMruSpaces() -> Bool? {
        guard let raw = CFPreferencesCopyAppValue(key, domain) as? NSNumber else { return true }
        return raw.boolValue
    }
    @discardableResult func writeMruSpaces(_ value: Bool) -> Bool {
        CFPreferencesSetAppValue(key, NSNumber(value: value), domain)
        return CFPreferencesAppSynchronize(domain)
    }
}

@MainActor protocol AutoQuitScheduling: AnyObject {
    func schedule(id: String, seconds: Int, perform: @escaping @MainActor () -> Void)
    func cancel(id: String)
    func cancelAll()
}

@MainActor final class NativeAutoQuitScheduler: AutoQuitScheduling {
    private var tasks: [String: Task<Void, Never>] = [:]
    func schedule(id: String, seconds: Int, perform: @escaping @MainActor () -> Void) {
        tasks[id]?.cancel()
        let clamped = max(1, min(seconds, 15))
        tasks[id] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(clamped)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.tasks[id] = nil
            perform()
        }
    }
    func cancel(id: String) { tasks[id]?.cancel(); tasks[id] = nil }
    func cancelAll() { for task in tasks.values { task.cancel() }; tasks = [:] }
}

@MainActor protocol DockAndZoomBackend: AnyObject {
    func previews(for app: DesktopApp) -> [DockWindowPreview]
    func setMinimized(_ minimized: Bool, windowID: UUID) -> Bool
    func hide(app: DesktopApp) -> Bool
    func bringAllForward(app: DesktopApp) -> Bool
    func greenZoomTarget(at point: CGPoint) -> GreenZoomTarget?
    func setWindowFrame(_ frame: CGRect, windowID: UUID) -> WindowWriteResult
    func windowCount(for app: DesktopApp) -> Int?
    func bundleIdentifier(for app: DesktopApp) -> String?
    func terminate(app: DesktopApp) -> Bool
    func startZoomClickInterceptor(_ onPress: @escaping @MainActor (CGPoint) -> Bool) -> Bool
    func stopZoomClickInterceptor()
}

@MainActor final class NativeDockAndZoomBackend: DockAndZoomBackend {
    private struct PreviewEntry {
        let element: AXUIElement
        let app: DesktopApp
    }
    private var entries: [UUID: PreviewEntry] = [:]
    private var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var zoomHandler: (@MainActor (CGPoint) -> Bool)?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    private func axElement(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }
    private func running(_ app: DesktopApp) -> NSRunningApplication? {
        guard app.pid != ownPID, let launchedAt = app.launchedAt,
              let running = NSRunningApplication(processIdentifier: app.pid),
              !running.isTerminated, running.launchDate == launchedAt else { return nil }
        return running
    }
    private func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = value(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        let rect = CGRect(origin: origin, size: size)
        return WindowGeometry.valid(rect) ? rect : nil
    }

    func previews(for app: DesktopApp) -> [DockWindowPreview] {
        guard AXIsProcessTrusted(), running(app) != nil else { return [] }
        let axApp = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.08)
        guard let windows = value(axApp, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        var list: [DockWindowPreview] = []
        for win in windows.prefix(16) {
            AXUIElementSetMessagingTimeout(win, 0.08)
            guard value(win, kAXRoleAttribute) as? String == kAXWindowRole else { continue }
            let minimized = (value(win, kAXMinimizedAttribute) as? Bool) == true
            let rect = frame(win) ?? CGRect(x: 0, y: 0, width: 800, height: 500)
            let id = entries.first { $0.value.app.id == app.id && CFEqual($0.value.element, win) }?.key ?? UUID()
            entries[id] = PreviewEntry(element: win, app: app)
            let title = (value(win, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            list.append(DockWindowPreview(id: id, app: app, title: title.isEmpty ? "Untitled window" : title, frame: rect, isMinimized: minimized))
        }
        return list
    }

    func setMinimized(_ minimized: Bool, windowID: UUID) -> Bool {
        guard AXIsProcessTrusted(), let entry = entries[windowID], running(entry.app) != nil else { return false }
        let cfBool: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        guard AXUIElementSetAttributeValue(entry.element, kAXMinimizedAttribute as CFString, cfBool) == .success else { return false }
        if !minimized {
            _ = running(entry.app)?.activate(options: [])
            _ = AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
        }
        return true
    }

    func hide(app: DesktopApp) -> Bool {
        guard AXIsProcessTrusted(), let running = running(app) else { return false }
        return running.hide()
    }

    func bringAllForward(app: DesktopApp) -> Bool {
        guard AXIsProcessTrusted(), let running = running(app), running.activate(options: []) else { return false }
        for item in previews(for: app) {
            if item.isMinimized { _ = setMinimized(false, windowID: item.id) }
            if let entry = entries[item.id] {
                _ = AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
            }
        }
        return true
    }

    func greenZoomTarget(at point: CGPoint) -> GreenZoomTarget? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.06)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.06)
        let role = value(hit, kAXRoleAttribute) as? String
        let subrole = value(hit, kAXSubroleAttribute) as? String
        guard role == kAXButtonRole,
              subrole == kAXZoomButtonSubrole || subrole == kAXFullScreenButtonSubrole,
              let winElement = axElement(value(hit, kAXWindowAttribute)),
              let rect = frame(winElement) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(winElement, &pid) == .success, pid != ownPID,
              let runningApp = NSRunningApplication(processIdentifier: pid),
              runningApp.activationPolicy == .regular else { return nil }
        let desktopApp = DesktopApp(pid: pid, launchedAt: runningApp.launchDate, name: runningApp.localizedName ?? "App")
        let id = entries.first { $0.value.app.id == desktopApp.id && CFEqual($0.value.element, winElement) }?.key ?? UUID()
        entries[id] = PreviewEntry(element: winElement, app: desktopApp)
        let title = (value(winElement, kAXTitleAttribute) as? String) ?? "Window"
        let screens = NSScreen.screens
        guard let primaryTop = screens.first?.frame.maxY else { return nil }
        let desktopScreens = screens.map {
            DesktopScreen(frame: DesktopScreen.accessibilityRect($0.frame, primaryTop: primaryTop),
                          usable: DesktopScreen.accessibilityRect($0.visibleFrame, primaryTop: primaryTop))
        }
        guard let targetScreen = WindowGeometry.screen(for: rect, in: desktopScreens) else { return nil }
        return GreenZoomTarget(window: DesktopWindow(id: id, app: desktopApp, title: title, frame: rect), usableScreen: targetScreen.usable)
    }

    func setWindowFrame(_ desired: CGRect, windowID: UUID) -> WindowWriteResult {
        guard AXIsProcessTrusted(), let entry = entries[windowID], running(entry.app) != nil else {
            return .failed("Window is no longer available.")
        }
        return WindowFrameWriter.write(desired, read: { self.frame(entry.element) }, position: { point in
            var point = point
            guard let v = AXValueCreate(.cgPoint, &point) else { return false }
            return AXUIElementSetAttributeValue(entry.element, kAXPositionAttribute as CFString, v) == .success
        }, size: { size in
            var size = size
            guard let v = AXValueCreate(.cgSize, &size) else { return false }
            return AXUIElementSetAttributeValue(entry.element, kAXSizeAttribute as CFString, v) == .success
        })
    }

    func windowCount(for app: DesktopApp) -> Int? {
        guard AXIsProcessTrusted(), running(app) != nil else { return nil }
        let axApp = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.08)
        guard let windows = value(axApp, kAXWindowsAttribute) as? [AXUIElement] else { return 0 }
        let standardWindows = windows.filter {
            AXUIElementSetMessagingTimeout($0, 0.06)
            return (value($0, kAXRoleAttribute) as? String) == kAXWindowRole
        }
        return standardWindows.count
    }

    func bundleIdentifier(for app: DesktopApp) -> String? {
        running(app)?.bundleIdentifier
    }

    func terminate(app: DesktopApp) -> Bool {
        guard let running = running(app) else { return false }
        return running.terminate()
    }

    func startZoomClickInterceptor(_ onPress: @escaping @MainActor (CGPoint) -> Bool) -> Bool {
        stopZoomClickInterceptor()
        zoomHandler = onPress
        let mask = CGEventMask(1) << CGEventType.leftMouseDown.rawValue
        tapPort = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let location = event.location
                let shouldConsume: Bool = MainActor.assumeIsolated {
                    let backend = Unmanaged<NativeDockAndZoomBackend>.fromOpaque(context).takeUnretainedValue()
                    return type == .leftMouseDown && backend.zoomHandler?(location) == true
                }
                return shouldConsume ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tapPort, let source = CFMachPortCreateRunLoopSource(nil, tapPort, 0) else {
            stopZoomClickInterceptor(); return false
        }
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tapPort, enable: true)
        return true
    }

    func stopZoomClickInterceptor() {
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: false); CFMachPortInvalidate(tapPort) }
        tapPort = nil; tapSource = nil; zoomHandler = nil
    }
}

@MainActor final class DockSpacesController: ObservableObject {
    nonisolated static let protectedBundles: Set<String> = ["com.apple.finder", "com.apple.systempreferences", "com.sieghart.app"]
    nonisolated static let autoQuitDelayRange: ClosedRange<Int> = 1...15

    @Published var dockPreviewEnabled: Bool {
        didSet { defaults.set(dockPreviewEnabled, forKey: "desktop.dockPreview"); if !dockPreviewEnabled { previewWindows = []; previewApp = nil } }
    }
    @Published private(set) var previewApp: DesktopApp?
    @Published private(set) var previewWindows: [DockWindowPreview] = []
    @Published var dockClickBehavior: DockClickBehavior {
        didSet { defaults.set(dockClickBehavior.rawValue, forKey: "desktop.dockClickBehavior") }
    }
    @Published var greenButtonMaximizes: Bool {
        didSet { defaults.set(greenButtonMaximizes, forKey: "desktop.windowMaximizer"); if started { configureZoomInterceptor() } }
    }
    @Published private(set) var zoomStatus = "Green button uses macOS default."
    @Published var autoQuitEnabled: Bool {
        didSet { defaults.set(autoQuitEnabled, forKey: "desktop.autoQuit"); if !autoQuitEnabled { autoQuitScheduler.cancelAll() } }
    }
    @Published var autoQuitDelaySeconds: Int {
        didSet {
            let clamped = min(max(autoQuitDelaySeconds, Self.autoQuitDelayRange.lowerBound), Self.autoQuitDelayRange.upperBound)
            if autoQuitDelaySeconds != clamped { autoQuitDelaySeconds = clamped }
            defaults.set(clamped, forKey: "desktop.autoQuitDelay")
        }
    }
    @Published private(set) var autoQuitStatus = "Auto-quit on last window close is off."
    @Published var keepSpacesOrderFixed: Bool {
        didSet { defaults.set(keepSpacesOrderFixed, forKey: "desktop.spacesOrder.fixed"); if started { configureSpacesOrder() } }
    }
    @Published private(set) var spacesStatus = "Desktop order uses macOS setting."
    @Published private(set) var savedOriginalMruSpaces: Bool?

    private let defaults: UserDefaults
    private let backend: any DockAndZoomBackend
    private let spacesBackend: any SpacesPreferenceBackend
    private let autoQuitScheduler: any AutoQuitScheduling
    private let trusted: () -> Bool
    private var started = false
    private var asleep = false
    private var locked = false
    private var sessionActive = true
    private var zoomPreviousFrames: [UUID: CGRect] = [:]
    private var observedWindowedApps: [String: DesktopApp] = [:]

    init(defaults: UserDefaults = .standard,
         backend: (any DockAndZoomBackend)? = nil,
         spacesBackend: (any SpacesPreferenceBackend)? = nil,
         autoQuitScheduler: (any AutoQuitScheduling)? = nil,
         trusted: @escaping () -> Bool = AXIsProcessTrusted) {
        self.defaults = defaults
        self.backend = backend ?? NativeDockAndZoomBackend()
        self.spacesBackend = spacesBackend ?? NativeSpacesPreferenceBackend()
        self.autoQuitScheduler = autoQuitScheduler ?? NativeAutoQuitScheduler()
        self.trusted = trusted
        dockPreviewEnabled = defaults.bool(forKey: "desktop.dockPreview")
        dockClickBehavior = DockClickBehavior(rawValue: defaults.string(forKey: "desktop.dockClickBehavior") ?? "") ?? .systemDefault
        greenButtonMaximizes = defaults.bool(forKey: "desktop.windowMaximizer")
        autoQuitEnabled = defaults.bool(forKey: "desktop.autoQuit")
        let storedDelay = defaults.object(forKey: "desktop.autoQuitDelay") as? Int ?? 2
        autoQuitDelaySeconds = min(max(storedDelay, Self.autoQuitDelayRange.lowerBound), Self.autoQuitDelayRange.upperBound)
        keepSpacesOrderFixed = defaults.bool(forKey: "desktop.spacesOrder.fixed")
        if defaults.bool(forKey: "desktop.spacesOrder.hasSavedOriginal"),
           let saved = defaults.object(forKey: "desktop.spacesOrder.savedOriginal") as? Bool {
            savedOriginalMruSpaces = saved
        }
    }

    private var available: Bool { started && !asleep && !locked && sessionActive }

    private func saveOriginalMru(_ value: Bool?) {
        savedOriginalMruSpaces = value
        if let value {
            defaults.set(true, forKey: "desktop.spacesOrder.hasSavedOriginal")
            defaults.set(value, forKey: "desktop.spacesOrder.savedOriginal")
        } else {
            defaults.removeObject(forKey: "desktop.spacesOrder.hasSavedOriginal")
            defaults.removeObject(forKey: "desktop.spacesOrder.savedOriginal")
        }
    }

    func loadDockPreview(for app: DesktopApp) {
        guard available, trusted(), dockPreviewEnabled else {
            previewApp = nil; previewWindows = []; return
        }
        previewApp = app
        previewWindows = backend.previews(for: app)
    }

    @discardableResult
    func togglePreviewMinimize(_ windowID: UUID) -> Bool {
        guard available, trusted(), let item = previewWindows.first(where: { $0.id == windowID }) else { return false }
        let ok = backend.setMinimized(!item.isMinimized, windowID: windowID)
        if ok, let app = previewApp { previewWindows = backend.previews(for: app) }
        return ok
    }

    @discardableResult
    func handleDockClick(for app: DesktopApp, wasFrontmost: Bool) -> String {
        guard available, trusted() else { return "Allow Accessibility to use Dock click actions." }
        guard wasFrontmost, dockClickBehavior != .systemDefault else {
            _ = backend.bringAllForward(app: app)
            return "Activated \(app.name)."
        }
        switch dockClickBehavior {
        case .systemDefault:
            return "Used macOS default Dock click."
        case .hideActiveApp:
            return backend.hide(app: app) ? "Hidden \(app.name)." : "Could not hide \(app.name)."
        case .bringAllForward:
            return backend.bringAllForward(app: app) ? "Brought all \(app.name) windows forward." : "Could not raise \(app.name) windows."
        case .minimizeOrRestore:
            let items = backend.previews(for: app)
            guard !items.isEmpty else { return "No windows available for \(app.name)." }
            let hasVisible = items.contains { !$0.isMinimized }
            var changed = false
            for item in items where item.isMinimized != hasVisible {
                if backend.setMinimized(hasVisible, windowID: item.id) { changed = true }
            }
            if dockPreviewEnabled && previewApp?.id == app.id { previewWindows = backend.previews(for: app) }
            return changed ? (hasVisible ? "Minimized \(app.name) windows." : "Restored \(app.name) windows.") : "Could not change \(app.name) window state."
        }
    }

    func configureZoomInterceptor() {
        backend.stopZoomClickInterceptor()
        guard started, greenButtonMaximizes else { zoomStatus = "Green button uses macOS default."; return }
        guard available else { zoomStatus = "Green-button maximize is paused."; return }
        guard trusted() else { zoomStatus = "Allow Accessibility, then retry green-button maximize."; return }
        let ok = backend.startZoomClickInterceptor { [weak self] point in
            guard let self, self.available, self.greenButtonMaximizes, self.trusted() else { return false }
            return self.handleGreenZoomClick(at: point)
        }
        zoomStatus = ok ? "Green window button maximizes to usable desktop instead of full-screen Space. Click again to restore." : "Green-button maximize unavailable. Check Accessibility and retry."
    }

    @discardableResult
    func handleGreenZoomClick(at point: CGPoint) -> Bool {
        guard available, greenButtonMaximizes, trusted(),
              let target = backend.greenZoomTarget(at: point),
              let maxFrame = WindowGeometry.frame(.maximize, current: target.window.frame, usable: target.usableScreen) else { return false }
        let win = target.window
        if WindowGeometry.matches(win.frame, maxFrame), let previous = zoomPreviousFrames[win.id] {
            if case .applied = backend.setWindowFrame(previous, windowID: win.id) {
                zoomPreviousFrames.removeValue(forKey: win.id)
                zoomStatus = "Restored \(win.app.name) window from green-button maximize."
                return true
            }
            return false
        }
        let previous = win.frame
        if case .applied(let actual) = backend.setWindowFrame(maxFrame, windowID: win.id), WindowGeometry.valid(actual) {
            zoomPreviousFrames[win.id] = previous
            zoomStatus = "Maximized \(win.app.name) to usable screen."
            return true
        }
        return false
    }

    func observeSnapshot(_ snapshot: DesktopSnapshot) {
        for win in snapshot.windows {
            observedWindowedApps[win.app.id] = win.app
            autoQuitScheduler.cancel(id: win.app.id)
        }
        guard available, autoQuitEnabled, trusted() else { return }
        for (appID, app) in observedWindowedApps {
            let bundle = backend.bundleIdentifier(for: app) ?? ""
            if Self.protectedBundles.contains(bundle) { continue }
            guard let count = backend.windowCount(for: app) else {
                observedWindowedApps.removeValue(forKey: appID)
                autoQuitScheduler.cancel(id: appID)
                continue
            }
            if count == 0 {
                autoQuitStatus = "Scheduled auto-quit for \(app.name) in \(autoQuitDelaySeconds)s."
                autoQuitScheduler.schedule(id: appID, seconds: autoQuitDelaySeconds) { [weak self] in
                    self?.evaluateAutoQuit(for: app)
                }
            } else {
                autoQuitScheduler.cancel(id: appID)
            }
        }
    }

    private func evaluateAutoQuit(for app: DesktopApp) {
        guard available, autoQuitEnabled, trusted() else { return }
        let bundle = backend.bundleIdentifier(for: app) ?? ""
        guard !Self.protectedBundles.contains(bundle),
              observedWindowedApps[app.id] != nil,
              backend.windowCount(for: app) == 0 else { return }
        observedWindowedApps.removeValue(forKey: app.id)
        if backend.terminate(app: app) {
            autoQuitStatus = "Requested quit for \(app.name) after its last window closed."
        } else {
            autoQuitStatus = "Could not quit \(app.name)."
        }
    }

    func configureSpacesOrder() {
        guard available else {
            if let original = savedOriginalMruSpaces { _ = spacesBackend.writeMruSpaces(original) }
            spacesStatus = keepSpacesOrderFixed ? "Desktop order lock paused while the Mac sleeps or is locked." : "Desktop order uses macOS setting."
            return
        }
        guard keepSpacesOrderFixed else {
            if let original = savedOriginalMruSpaces {
                if spacesBackend.writeMruSpaces(original) {
                    saveOriginalMru(nil)
                    spacesStatus = "Desktop order restored to previous Mac setting."
                } else {
                    spacesStatus = "Could not restore Spaces order. Click Restore original to retry."
                }
            } else {
                spacesStatus = "Desktop order uses macOS setting."
            }
            return
        }
        if savedOriginalMruSpaces == nil {
            guard let current = spacesBackend.readMruSpaces() else {
                spacesStatus = "Could not read current macOS Spaces setting; nothing was changed."
                return
            }
            saveOriginalMru(current)
        }
        if spacesBackend.writeMruSpaces(false) {
            spacesStatus = "Desktop Spaces order locked (auto-rearrange disabled). Original setting saved for restore."
        } else {
            spacesStatus = "Could not update Spaces order."
        }
    }

    func restoreOriginalSpacesOrder() {
        if keepSpacesOrderFixed {
            keepSpacesOrderFixed = false
        } else if let original = savedOriginalMruSpaces {
            if spacesBackend.writeMruSpaces(original) {
                saveOriginalMru(nil)
                spacesStatus = "Desktop order restored to previous Mac setting."
            } else {
                spacesStatus = "Could not restore Spaces order. Click Restore original to retry."
            }
        }
    }

    func start() {
        started = true
        configureZoomInterceptor()
        configureSpacesOrder()
    }
    func setSleeping(_ value: Bool) { asleep = value; if started { configureZoomInterceptor(); configureSpacesOrder(); autoQuitScheduler.cancelAll() } }
    func setLocked(_ value: Bool) { locked = value; if started { configureZoomInterceptor(); configureSpacesOrder(); autoQuitScheduler.cancelAll() } }
    func setSessionActive(_ value: Bool) { sessionActive = value; if started { configureZoomInterceptor(); configureSpacesOrder(); autoQuitScheduler.cancelAll() } }
    func stop() {
        started = false
        backend.stopZoomClickInterceptor()
        autoQuitScheduler.cancelAll()
        if let original = savedOriginalMruSpaces, spacesBackend.writeMruSpaces(original) {
            if !keepSpacesOrderFixed { saveOriginalMru(nil) }
        }
        previewApp = nil; previewWindows = []; zoomPreviousFrames = [:]; observedWindowedApps = [:]
        zoomStatus = "Green button uses macOS default."
        autoQuitStatus = "Auto-quit on last window close is off."
        spacesStatus = "Desktop order uses macOS setting."
    }
}
