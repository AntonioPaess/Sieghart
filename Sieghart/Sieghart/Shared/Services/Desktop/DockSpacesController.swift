import AppKit
import ApplicationServices
import Combine
import SwiftUI

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
    private let zoomClicks = NativePairedLeftClickMonitor()
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
        guard let windows = value(axApp, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        // A successful AXWindows read includes minimized windows/dialogs. An
        // unknown attribute or role must never be interpreted as zero windows.
        return windows.count
    }

    func bundleIdentifier(for app: DesktopApp) -> String? {
        running(app)?.bundleIdentifier
    }

    func terminate(app: DesktopApp) -> Bool {
        guard let running = running(app) else { return false }
        return running.terminate()
    }

    func startZoomClickInterceptor(_ onPress: @escaping @MainActor (CGPoint) -> Bool) -> Bool {
        zoomClicks.start(onPress)
    }
    func stopZoomClickInterceptor() { zoomClicks.stop() }
}

@MainActor final class DockSpacesController: ObservableObject {
    nonisolated static let protectedBundles: Set<String> = ["com.apple.finder", "com.apple.systempreferences", "com.sieghart.app"]
    nonisolated static let autoQuitDelayRange: ClosedRange<Int> = 1...15

    @Published var dockPreviewEnabled: Bool {
        didSet { defaults.set(dockPreviewEnabled, forKey: "desktop.dockPreview"); if !dockPreviewEnabled { previewWindows = []; previewApp = nil }; if started { configureNativeMonitoring() } }
    }
    @Published private(set) var previewApp: DesktopApp?
    @Published private(set) var previewWindows: [DockWindowPreview] = []
    @Published var dockClickBehavior: DockClickBehavior {
        didSet { defaults.set(dockClickBehavior.rawValue, forKey: "desktop.dockClickBehavior"); if started { configureNativeMonitoring() } }
    }
    @Published var greenButtonMaximizes: Bool {
        didSet { defaults.set(greenButtonMaximizes, forKey: "desktop.windowMaximizer"); if started { configureZoomInterceptor() } }
    }
    @Published private(set) var zoomStatus = "Green button uses macOS default."
    @Published var autoQuitEnabled: Bool {
        didSet { defaults.set(autoQuitEnabled, forKey: "desktop.autoQuit"); if !autoQuitEnabled { autoQuitScheduler.cancelAll(); scheduledAutoQuit = [] }; if started { configureNativeMonitoring() } }
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
    private let activityMonitor: (any DockActivityMonitoring)?
    private let trusted: () -> Bool
    private var started = false
    private var asleep = false
    private var locked = false
    private var sessionActive = true
    private var zoomPreviousFrames: [UUID: CGRect] = [:]
    private var scheduledAutoQuit: Set<String> = []
    private var monitoringGeneration = 0
    private var lastAppliedMru: Bool?
    private var observedWindowedApps: [String: DesktopApp] = [:]

    init(defaults: UserDefaults = .standard,
         backend: (any DockAndZoomBackend)? = nil,
         spacesBackend: (any SpacesPreferenceBackend)? = nil,
         autoQuitScheduler: (any AutoQuitScheduling)? = nil,
         activityMonitor: (any DockActivityMonitoring)? = nil,
         trusted: @escaping () -> Bool = AXIsProcessTrusted) {
        self.defaults = defaults
        self.backend = backend ?? NativeDockAndZoomBackend()
        self.spacesBackend = spacesBackend ?? NativeSpacesPreferenceBackend()
        self.autoQuitScheduler = autoQuitScheduler ?? NativeAutoQuitScheduler()
        self.trusted = trusted
        self.activityMonitor = activityMonitor ?? (backend == nil ? NativeDockActivityMonitor() : nil)
        lastAppliedMru = defaults.object(forKey: "desktop.spacesOrder.lastApplied") as? Bool
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
    func handleDockClick(for app: DesktopApp, wasFrontmost: Bool, intendedMinimized: Bool? = nil, windowIDs: Set<UUID>? = nil) -> String {
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
            let items = backend.previews(for: app).filter { windowIDs?.contains($0.id) ?? true }
            guard !items.isEmpty else { return "No windows available for \(app.name)." }
            let hasVisible = intendedMinimized ?? items.contains { !$0.isMinimized }
            var changed = false
            for item in items where item.isMinimized != hasVisible {
                if backend.setMinimized(hasVisible, windowID: item.id) { changed = true }
            }
            if dockPreviewEnabled && previewApp?.id == app.id { previewWindows = backend.previews(for: app) }
            let alreadyApplied = items.allSatisfy { $0.isMinimized == hasVisible }
            return changed || alreadyApplied ? (hasVisible ? "Minimized \(app.name) windows." : "Restored \(app.name) windows.") : "Could not change \(app.name) window state."
        }
    }

    func configureZoomInterceptor() {
        configureNativeMonitoring()
        // Replacing the callback preserves a held click's pending release.
        guard available, greenButtonMaximizes, trusted() else {
            backend.stopZoomClickInterceptor()
            zoomStatus = greenButtonMaximizes ? "Green-button maximize is paused. Check Accessibility and retry." : "Green button uses macOS default."
            return
        }
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

    private func configureNativeMonitoring() {
        monitoringGeneration += 1
        activityMonitor?.stop()
        guard available, trusted(), dockPreviewEnabled || dockClickBehavior != .systemDefault || autoQuitEnabled else { return }
        let version = monitoringGeneration
        activityMonitor?.start(previews: dockPreviewEnabled, clicks: dockClickBehavior != .systemDefault, autoQuit: autoQuitEnabled,
            hover: { [weak self] app, anchor in
                guard let self, self.monitoringGeneration == version, self.available, self.trusted(), self.dockPreviewEnabled else { return }
                guard let app, let anchor else { self.activityMonitor?.hidePreview(); return }
                self.loadDockPreview(for: app)
                self.presentDockPreview(anchor: anchor)
            }, prepareClick: { [weak self] app, active in
                guard let self, self.monitoringGeneration == version, self.available, self.trusted(), active, self.dockClickBehavior != .systemDefault else { return nil }
                let behavior = self.dockClickBehavior
                let before = behavior == .minimizeOrRestore ? self.backend.previews(for: app) : []
                if behavior == .minimizeOrRestore && before.isEmpty { return nil }
                let desired = before.contains { !$0.isMinimized }
                let ids = Set(before.map(\.id))
                return { [weak self] in
                    guard let self, self.monitoringGeneration == version, self.available, self.trusted(), self.dockClickBehavior == behavior else { return }
                    self.activityMonitor?.hidePreview()
                    _ = self.handleDockClick(for: app, wasFrontmost: true,
                        intendedMinimized: behavior == .minimizeOrRestore ? desired : nil,
                        windowIDs: behavior == .minimizeOrRestore ? ids : nil)
                }
            }, windowsChanged: { [weak self] app in
                guard let self, self.monitoringGeneration == version else { return }
                self.observeAppWindows(app)
            })
    }

    private func presentDockPreview(anchor: CGRect) {
        activityMonitor?.showPreview(previewWindows, anchor: anchor,
            select: { [weak self] id in
                guard let self, self.available, self.trusted(), self.dockPreviewEnabled else { return }
                _ = self.backend.setMinimized(false, windowID: id); self.activityMonitor?.hidePreview()
            }, minimize: { [weak self] id in
                guard let self, self.available, self.trusted(), self.dockPreviewEnabled else { return }
                _ = self.togglePreviewMinimize(id); self.presentDockPreview(anchor: anchor)
            })
    }

    func observeSnapshot(_ snapshot: DesktopSnapshot) {
        guard available, autoQuitEnabled, trusted() else { return }
        for app in snapshot.apps { observeAppWindows(app) }
    }
    private func observeAppWindows(_ app: DesktopApp) {
        guard available, autoQuitEnabled, trusted() else { return }
        guard let bundle = backend.bundleIdentifier(for: app), !Self.protectedBundles.contains(bundle),
              let count = backend.windowCount(for: app) else {
            scheduledAutoQuit.remove(app.id); autoQuitScheduler.cancel(id: app.id)
            return
        }
        if count > 0 {
            observedWindowedApps[app.id] = app
            scheduledAutoQuit.remove(app.id); autoQuitScheduler.cancel(id: app.id)
        } else if observedWindowedApps[app.id] != nil, scheduledAutoQuit.insert(app.id).inserted {
            autoQuitStatus = "Scheduled auto-quit for \(app.name) in \(autoQuitDelaySeconds)s."
            autoQuitScheduler.schedule(id: app.id, seconds: autoQuitDelaySeconds) { [weak self] in self?.evaluateAutoQuit(for: app) }
        }
    }
    private func evaluateAutoQuit(for app: DesktopApp) {
        scheduledAutoQuit.remove(app.id)
        guard available, autoQuitEnabled, trusted(),
              let bundle = backend.bundleIdentifier(for: app), !Self.protectedBundles.contains(bundle),
              observedWindowedApps[app.id] != nil, backend.windowCount(for: app) == 0 else { return }
        observedWindowedApps.removeValue(forKey: app.id)
        autoQuitStatus = backend.terminate(app: app) ? "Requested quit for \(app.name) after its last window closed." : "Could not quit \(app.name)."
    }

    private func setLastAppliedMru(_ value: Bool?) {
        lastAppliedMru = value
        if let value { defaults.set(value, forKey: "desktop.spacesOrder.lastApplied") }
        else { defaults.removeObject(forKey: "desktop.spacesOrder.lastApplied") }
    }
    @discardableResult private func restoreOwnedSpaces() -> Bool {
        guard let original = savedOriginalMruSpaces else { return true }
        guard let current = spacesBackend.readMruSpaces() else {
            spacesStatus = "Could not read Spaces order; no setting was overwritten. Retry restore."; return false
        }
        guard let applied = lastAppliedMru, current == applied else {
            saveOriginalMru(nil); setLastAppliedMru(nil)
            spacesStatus = "Preserved the Spaces setting changed outside Sieghart."; return true
        }
        guard spacesBackend.writeMruSpaces(original) else {
            spacesStatus = "Could not restore Spaces order. Click Restore original Spaces setting to retry."; return false
        }
        saveOriginalMru(nil); setLastAppliedMru(nil)
        spacesStatus = "Desktop order restored to previous Mac setting."; return true
    }
    func configureSpacesOrder() {
        guard available, keepSpacesOrderFixed else {
            if savedOriginalMruSpaces != nil { _ = restoreOwnedSpaces() }
            else { spacesStatus = keepSpacesOrderFixed ? "Desktop order lock paused." : "Desktop order uses macOS setting." }
            return
        }
        guard let current = spacesBackend.readMruSpaces() else {
            spacesStatus = "Could not read current macOS Spaces setting; nothing was changed."; return
        }
        if savedOriginalMruSpaces != nil, let applied = lastAppliedMru, current != applied {
            saveOriginalMru(nil); setLastAppliedMru(nil); keepSpacesOrderFixed = false
            spacesStatus = "Preserved the Spaces setting changed outside Sieghart. Re-enable to apply again."; return
        }
        if savedOriginalMruSpaces == nil || lastAppliedMru == nil { saveOriginalMru(current) }
        if spacesBackend.writeMruSpaces(false) {
            setLastAppliedMru(false)
            spacesStatus = "Desktop Spaces order locked (auto-rearrange disabled). Original setting saved for restore."
        } else { spacesStatus = "Could not update Spaces order." }
    }
    func restoreOriginalSpacesOrder() {
        if keepSpacesOrderFixed { keepSpacesOrderFixed = false }
        else { _ = restoreOwnedSpaces() }
    }

    func start() {
        started = true
        configureZoomInterceptor()
        configureSpacesOrder()
    }
    func setSleeping(_ value: Bool) { asleep = value; if started { configureZoomInterceptor(); configureSpacesOrder(); autoQuitScheduler.cancelAll(); scheduledAutoQuit = [] } }
    func setLocked(_ value: Bool) { locked = value; if started { configureZoomInterceptor(); configureSpacesOrder(); autoQuitScheduler.cancelAll(); scheduledAutoQuit = [] } }
    func setSessionActive(_ value: Bool) { sessionActive = value; if started { configureZoomInterceptor(); configureSpacesOrder(); autoQuitScheduler.cancelAll(); scheduledAutoQuit = [] } }
    func stop() {
        started = false
        backend.stopZoomClickInterceptor()
        autoQuitScheduler.cancelAll()
        monitoringGeneration += 1; activityMonitor?.stop(); scheduledAutoQuit = []
        _ = restoreOwnedSpaces()
        previewApp = nil; previewWindows = []; zoomPreviousFrames = [:]; observedWindowedApps = [:]
        zoomStatus = "Green button uses macOS default."
        autoQuitStatus = "Auto-quit on last window close is off."
        spacesStatus = "Desktop order uses macOS setting."
    }
}

// The green-button interceptor owns its consumed click pair. Turning a
// feature off drains a swallowed down; a disabled tap never repeats the action.
struct LeftClickPair {
    private(set) var captured = false
    mutating func receive(_ phase: DesktopPointerPhase, down: () -> Bool) -> Bool {
        switch phase {
        case .down: if !captured { captured = down() }; return captured
        case .dragged: return captured
        case .up: let result = captured; captured = false; return result
        }
    }
    mutating func recover(pressed: Bool) { if !pressed { captured = false } }
}
@MainActor private final class NativePairedLeftClickMonitor {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: (@MainActor (CGPoint) -> Bool)?
    private var pair = LeftClickPair()
    private var drainOwner: NativePairedLeftClickMonitor?
    private var drainCheck: Task<Void, Never>?
    func start(_ handler: @escaping @MainActor (CGPoint) -> Bool) -> Bool {
        drainCheck?.cancel(); drainCheck = nil; drainOwner = nil
        self.handler = handler
        if port != nil { return true }
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consumed: Bool = MainActor.assumeIsolated {
                    let monitor = Unmanaged<NativePairedLeftClickMonitor>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        monitor.pair.recover(pressed: CGEventSource.buttonState(.combinedSessionState, button: .left))
                        if let port = monitor.port { CGEvent.tapEnable(tap: port, enable: true) }
                        return false
                    }
                    let phase: DesktopPointerPhase
                    switch type { case .leftMouseDown: phase = .down; case .leftMouseUp: phase = .up; case .leftMouseDragged: phase = .dragged; default: return false }
                    let handler = monitor.handler
                    let modified = !event.flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl, .maskSecondaryFn]).isEmpty
                    let consumed = monitor.pair.receive(phase) { !modified && handler?(event.location) == true }
                    if monitor.handler == nil && !monitor.pair.captured {
                        DispatchQueue.main.async { [weak monitor] in monitor?.stop() }
                    }
                    return consumed
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { stop(); return false }
        self.source = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true); return true
    }
    func stop() {
        handler = nil
        pair.recover(pressed: CGEventSource.buttonState(.combinedSessionState, button: .left))
        if pair.captured {
            // CFRunLoop's userInfo is unretained. Keep the tap alive until its
            // owed release drains, even if its feature owner is deallocated.
            drainOwner = self
            if drainCheck == nil {
                drainCheck = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                        guard let self, self.handler == nil else { return }
                        self.pair.recover(pressed: CGEventSource.buttonState(.combinedSessionState, button: .left))
                        if !self.pair.captured { self.stop(); return }
                    }
                }
            }
            return
        }
        drainCheck?.cancel(); drainCheck = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        source = nil; port = nil; drainOwner = nil
    }
}

struct DockIconHit: Equatable {
    let app: DesktopApp
    let anchor: CGRect
}

@MainActor final class DockClickObservation {
    private struct Pending {
        let hit: DockIconHit
        let point: CGPoint
        let time: TimeInterval
        let perform: @MainActor () -> Void
    }
    private let hitTest: @MainActor (CGPoint) -> DockIconHit?
    private let prepare: @MainActor (DockIconHit) -> (@MainActor () -> Void)?
    private var pending: Pending?
    init(hitTest: @escaping @MainActor (CGPoint) -> DockIconHit?,
         prepare: @escaping @MainActor (DockIconHit) -> (@MainActor () -> Void)?) {
        self.hitTest = hitTest; self.prepare = prepare
    }
    func receive(_ phase: DesktopPointerPhase, at point: CGPoint, time: TimeInterval, modified: Bool, clickCount: Int = 1) {
        switch phase {
        case .down:
            pending = nil
            guard !modified, clickCount == 1, time.isFinite, point.x.isFinite, point.y.isFinite,
                  let hit = hitTest(point), hit.anchor.contains(point), let perform = prepare(hit) else { return }
            pending = Pending(hit: hit, point: point, time: time, perform: perform)
        case .dragged: cancel()
        case .up:
            let candidate = pending; pending = nil // A release can apply at most once.
            guard let candidate, !modified, clickCount == 1, time.isFinite,
                  (0...0.35).contains(time - candidate.time),
                  hypot(point.x - candidate.point.x, point.y - candidate.point.y) <= 4,
                  let current = hitTest(point), current.app.id == candidate.hit.app.id,
                  current.anchor.contains(point) else { return }
            candidate.perform()
        }
    }
    func cancel() { pending = nil }
}

@MainActor final class DockHoverTracking {
    private let dwell: any PointerDwellScheduling
    private let location: @MainActor () -> CGPoint?
    private let hitTest: @MainActor (CGPoint) -> DockIconHit?
    private let show: @MainActor (DockIconHit) -> Void
    private let hide: @MainActor () -> Void
    private var candidate: DockIconHit?
    private var lastMove = -TimeInterval.infinity
    private var generation = 0
    init(dwell: any PointerDwellScheduling, location: @escaping @MainActor () -> CGPoint?,
         hitTest: @escaping @MainActor (CGPoint) -> DockIconHit?, show: @escaping @MainActor (DockIconHit) -> Void,
         hide: @escaping @MainActor () -> Void) {
        self.dwell = dwell; self.location = location; self.hitTest = hitTest; self.show = show; self.hide = hide
    }
    func moved(_ point: CGPoint, at time: TimeInterval) {
        // Cheap exit detection also hides an already visible preview when its
        // final mouse event falls inside the AX-query throttle window.
        if let candidate, !candidate.anchor.contains(point) { cancel() }
        guard time - lastMove >= 0.1 else { return }; lastMove = time
        guard let hit = hitTest(point), hit.anchor.contains(point) else { cancel(); return }
        guard hit.app.id != candidate?.app.id else { return }
        cancel(); candidate = hit
        let ticket = generation
        dwell.schedule { [weak self] in
            guard let self, self.generation == ticket else { return }
            // Throttled/missed events cannot authorize a stale hover. Read the
            // current position AND current Dock identity before presentation.
            guard let point = self.location(), let fresh = self.hitTest(point),
                  fresh.app.id == hit.app.id, fresh.anchor.contains(point) else { self.cancel(); return }
            self.candidate = fresh; self.show(fresh)
        }
    }
    func cancel() { generation += 1; dwell.cancel(); candidate = nil; hide() }
}

@MainActor protocol DockActivityMonitoring: AnyObject {
    func start(previews: Bool, clicks: Bool, autoQuit: Bool,
               hover: @escaping @MainActor (DesktopApp?, CGRect?) -> Void,
               prepareClick: @escaping @MainActor (DesktopApp, Bool) -> (@MainActor () -> Void)?,
               windowsChanged: @escaping @MainActor (DesktopApp) -> Void)
    func showPreview(_ windows: [DockWindowPreview], anchor: CGRect,
                     select: @escaping @MainActor (UUID) -> Void, minimize: @escaping @MainActor (UUID) -> Void)
    func hidePreview()
    func stop()
}

@MainActor private final class NativeDockActivityMonitor: DockActivityMonitoring {
    private var global: Any?, local: Any?
    private var clickMonitor: Any?
    private var clickPreparation: (@MainActor (DesktopApp, Bool) -> (@MainActor () -> Void)?)?
    private lazy var clickGesture = DockClickObservation(hitTest: { [weak self] point in
        self?.dockHit(at: point)
    }, prepare: { [weak self] hit in
        self?.clickPreparation?(hit.app, NSWorkspace.shared.frontmostApplication?.processIdentifier == hit.app.pid)
    })
    private lazy var hoverTracking = DockHoverTracking(dwell: NativePointerDwellScheduler(),
        location: { [weak self] in self?.currentLocation() },
        hitTest: { [weak self] point in self?.dockHit(at: point) },
        show: { [weak self] hit in self?.hover?(hit.app, hit.anchor) },
        hide: { [weak self] in self?.hidePreview() })
    private var workspaceTokens: [NSObjectProtocol] = []
    private struct AppObservation { let observer: AXObserver; let app: DesktopApp }
    private var observations: [Int32: AppObservation] = [:]
    private var windowsChanged: (@MainActor (DesktopApp) -> Void)?
    private var hover: (@MainActor (DesktopApp?, CGRect?) -> Void)?
    private var dockPID: pid_t?
    private var pendingWindows: [pid_t: Task<Void, Never>] = [:]
    private var panel: NSPanel?

    func start(previews: Bool, clicks wantsClicks: Bool, autoQuit: Bool,
               hover: @escaping @MainActor (DesktopApp?, CGRect?) -> Void,
               prepareClick: @escaping @MainActor (DesktopApp, Bool) -> (@MainActor () -> Void)?,
               windowsChanged: @escaping @MainActor (DesktopApp) -> Void) {
        stop(); self.hover = hover; self.windowsChanged = windowsChanged; clickPreparation = prepareClick
        dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        if previews {
            global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                MainActor.assumeIsolated { if let point = event.cgEvent?.location { self?.moved(point) } }
            }
            local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                MainActor.assumeIsolated { if let point = event.cgEvent?.location { self?.moved(point) } }; return event
            }
        }
        if wantsClicks {
            // Observe only: do not consume/post events or interfere with Dock
            // icon reordering, context menus, holds or native restore behavior.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let phase: DesktopPointerPhase
                    switch event.type {
                    case .leftMouseDown: self.hoverTracking.cancel(); phase = .down
                    case .leftMouseDragged: phase = .dragged
                    case .leftMouseUp: phase = .up
                    default: self.clickGesture.cancel(); self.hoverTracking.cancel(); return
                    }
                    guard let point = event.cgEvent?.location else { self.clickGesture.cancel(); return }
                    let modified = !event.modifierFlags.intersection([.command, .option, .shift, .control, .function]).isEmpty
                    self.clickGesture.receive(phase, at: point, time: event.timestamp, modified: modified, clickCount: event.clickCount)
                }
            }
        }
        if autoQuit {
            for app in NSWorkspace.shared.runningApplications { observe(app) }
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                    MainActor.assumeIsolated {
                        guard let self, let pid else { return }
                        if name == NSWorkspace.didLaunchApplicationNotification, let app = NSRunningApplication(processIdentifier: pid) { self.observe(app) }
                        else { self.removeObservation(pid) }
                    }
                })
            }
        }
    }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    private func dockItem(at point: CGPoint) -> (DesktopApp, CGRect)? {
        guard AXIsProcessTrusted(), let dockPID else { return nil }
        // Avoid AX traffic for the normal interior of the usable desktop.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        guard NSScreen.screens.contains(where: { screen in
            let r = DesktopScreen.accessibilityRect(screen.frame, primaryTop: primaryTop)
            return r.contains(point) && !r.insetBy(dx: 180, dy: 180).contains(point)
        }) else { return nil }
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.03)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, var element = hit else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == dockPID else { return nil }
        for _ in 0..<6 {
            AXUIElementSetMessagingTimeout(element, 0.03)
            if attribute(element, kAXRoleAttribute) as? String == "AXDockItem",
               attribute(element, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
               let url = attribute(element, kAXURLAttribute) as? URL, url.isFileURL, url.pathExtension == "app",
               let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }),
               app.activationPolicy == .regular, !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               let launched = app.launchDate,
               let rawP = attribute(element, kAXPositionAttribute), CFGetTypeID(rawP) == AXValueGetTypeID(),
               let rawS = attribute(element, kAXSizeAttribute), CFGetTypeID(rawS) == AXValueGetTypeID() {
                var p = CGPoint.zero, s = CGSize.zero
                guard AXValueGetValue(rawP as! AXValue, .cgPoint, &p), AXValueGetValue(rawS as! AXValue, .cgSize, &s) else { return nil }
                return (DesktopApp(pid: app.processIdentifier, launchedAt: launched, name: app.localizedName ?? "App"), CGRect(origin: p, size: s))
            }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }
    private func currentLocation() -> CGPoint? {
        guard let top = NSScreen.screens.first?.frame.maxY else { return nil }
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: top - point.y)
    }
    private func dockHit(at point: CGPoint) -> DockIconHit? {
        dockItem(at: point).map { DockIconHit(app: $0.0, anchor: $0.1) }
    }
    private func moved(_ point: CGPoint) {
        if panel?.frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) == true { return }
        hoverTracking.moved(point, at: ProcessInfo.processInfo.systemUptime)
    }
    private func observe(_ app: NSRunningApplication) {
        guard AXIsProcessTrusted(), app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let launched = app.launchDate, observations[app.processIdentifier] == nil else { return }
        var observer: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, { observer, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let monitor = Unmanaged<NativeDockActivityMonitor>.fromOpaque(context).takeUnretainedValue()
                // A destroyed AX element can no longer answer GetPid. The
                // observer, rather than that element, identifies the app.
                guard let pid = monitor.observations.first(where: { CFEqual($0.value.observer, observer) })?.key else { return }
                monitor.pendingWindows[pid]?.cancel()
                monitor.pendingWindows[pid] = Task { [weak monitor] in
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    guard let monitor, !Task.isCancelled else { return }
                    monitor.pendingWindows[pid] = nil; monitor.changed(pid)
                }
            }
        }, &observer)
        guard result == .success, let observer else { return }
        let desktop = DesktopApp(pid: app.processIdentifier, launchedAt: launched, name: app.localizedName ?? "App")
        observations[app.processIdentifier] = AppObservation(observer: observer, app: desktop)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.04)
        _ = AXObserverAddNotification(observer, axApp, kAXWindowCreatedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        changed(app.processIdentifier)
    }
    private func changed(_ pid: pid_t) {
        guard let observation = observations[pid] else { return }
        let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.04)
        if let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] {
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.04)
                _ = AXObserverAddNotification(observation.observer, window, kAXUIElementDestroyedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
        windowsChanged?(observation.app)
    }
    private func removeObservation(_ pid: pid_t) {
        pendingWindows.removeValue(forKey: pid)?.cancel()
        if let item = observations.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(item.observer), .commonModes)
        }
    }
    func showPreview(_ windows: [DockWindowPreview], anchor: CGRect,
                     select: @escaping @MainActor (UUID) -> Void, minimize: @escaping @MainActor (UUID) -> Void) {
        guard !windows.isEmpty else { hidePreview(); return }
        let preview = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false; preview.level = .popUpMenu; preview.isOpaque = false; preview.backgroundColor = .clear
        preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = NSHostingView(rootView: DockHoverPreview(windows: windows, select: select, minimize: minimize))
        let size = CGSize(width: 320, height: CGFloat(min(windows.count, 6)) * 58 + 20)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitAnchor = CGRect(x: anchor.minX, y: primaryTop - anchor.maxY, width: anchor.width, height: anchor.height)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(appKitAnchor) }) else { return }
        let usable = screen.visibleFrame
        let x = min(max(appKitAnchor.midX - size.width / 2, usable.minX + 6), usable.maxX - size.width - 6)
        let y = min(max(appKitAnchor.maxY + 8, usable.minY + 6), usable.maxY - size.height - 6)
        preview.contentView = view; preview.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: true)
        panel = preview; preview.orderFrontRegardless()
    }
    func hidePreview() { panel?.orderOut(nil) }
    func stop() {
        clickGesture.cancel(); clickPreparation = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }; clickMonitor = nil
        hoverTracking.cancel(); hidePreview()
        if let global { NSEvent.removeMonitor(global) }; global = nil
        if let local { NSEvent.removeMonitor(local) }; local = nil
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }; workspaceTokens = []
        for pid in Array(observations.keys) { removeObservation(pid) }
        windowsChanged = nil; hover = nil
    }
}
private struct DockHoverPreview: View {
    var windows: [DockWindowPreview]
    var select: @MainActor (UUID) -> Void
    var minimize: @MainActor (UUID) -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(windows) { item in
                    HStack {
                        RoundedRectangle(cornerRadius: 3).stroke(.secondary).frame(width: 30 * item.aspectRatio, height: 25)
                            .accessibilityHidden(true)
                        Button { select(item.id) } label: { Text(item.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }
                            .accessibilityLabel("Show \(item.title), \(item.app.name)")
                        Button(item.isMinimized ? "Restore" : "Minimize") { minimize(item.id) }.font(.caption)
                    }.frame(height: 50)
                }
            }.padding(10)
        }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
