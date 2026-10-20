import AppKit
import Foundation
import Testing

extension LogicTests {
    @Suite(.tags(.desktop)) struct DockSpacesLogicTests {
        @Test("G25.03 intercepted green-button click pairs survive recovery and drain after disable")
        func pairedClick() {
            var pair = LeftClickPair(); var actions = 0
            #expect(pair.receive(.down) { actions += 1; return true })
            pair.recover(pressed: true)
            #expect(pair.receive(.down) { actions += 1; return true })
            #expect(pair.receive(.dragged) { false })
            #expect(pair.receive(.up) { false })
            #expect(!pair.receive(.up) { false } && actions == 1)
            #expect(!pair.receive(.down) { false })
            #expect(!pair.receive(.up) { false })
            _ = pair.receive(.down) { true }; pair.recover(pressed: false)
            #expect(!pair.captured)
        }
        @Test("G25.01 dock preview aspect ratio clamps extreme dimensions and protected bundles include Finder and Sieghart")
        func previewAspectAndProtectedBundles() {
            let app = DesktopApp(pid: 100, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Safari")
            let wide = DockWindowPreview(id: UUID(), app: app, title: "Wide", frame: CGRect(x: 0, y: 0, width: 4000, height: 200), isMinimized: false)
            let tall = DockWindowPreview(id: UUID(), app: app, title: "Tall", frame: CGRect(x: 0, y: 0, width: 100, height: 2000), isMinimized: true)
            let empty = DockWindowPreview(id: UUID(), app: app, title: "Zero", frame: .zero, isMinimized: false)
            #expect(wide.aspectRatio == 3.0)
            #expect(tall.aspectRatio == 0.5)
            #expect(empty.aspectRatio == 1.6)
            #expect(DockSpacesController.protectedBundles.contains("com.apple.finder"))
            #expect(DockSpacesController.protectedBundles.contains("com.sieghart.app"))
        }
    }
}

@MainActor private final class DockAndZoomBackendFixture: DockAndZoomBackend {
    var previewMap: [String: [DockWindowPreview]] = [:]
    var hiddenApps: [String] = []
    var broughtForwardApps: [String] = []
    var terminatedApps: [String] = []
    var bundleMap: [String: String] = [:]
    var windowCounts: [String: Int] = [:]
    var zoomTarget: GreenZoomTarget?
    var frameWrites: [(UUID, CGRect)] = []
    var zoomHandler: (@MainActor (CGPoint) -> Bool)?
    var interceptorStarts = 0
    var minimizeWrites: [(UUID, Bool)] = []

    func previews(for app: DesktopApp) -> [DockWindowPreview] { previewMap[app.id] ?? [] }
    func setMinimized(_ minimized: Bool, windowID: UUID) -> Bool {
        for (appID, items) in previewMap {
            if let idx = items.firstIndex(where: { $0.id == windowID }) {
                minimizeWrites.append((windowID, minimized))
                previewMap[appID]?[idx].isMinimized = minimized
                return true
            }
        }
        return false
    }
    func hide(app: DesktopApp) -> Bool { hiddenApps.append(app.id); return true }
    func bringAllForward(app: DesktopApp) -> Bool { broughtForwardApps.append(app.id); return true }
    func greenZoomTarget(at point: CGPoint) -> GreenZoomTarget? { zoomTarget }
    func setWindowFrame(_ frame: CGRect, windowID: UUID) -> WindowWriteResult {
        frameWrites.append((windowID, frame))
        if var target = zoomTarget, target.window.id == windowID {
            var win = target.window; win.frame = frame
            zoomTarget = GreenZoomTarget(window: win, usableScreen: target.usableScreen)
        }
        return .applied(frame)
    }
    func windowCount(for app: DesktopApp) -> Int? { windowCounts[app.id] }
    func bundleIdentifier(for app: DesktopApp) -> String? { bundleMap[app.id] }
    func terminate(app: DesktopApp) -> Bool { terminatedApps.append(app.id); return true }
    func startZoomClickInterceptor(_ onPress: @escaping @MainActor (CGPoint) -> Bool) -> Bool {
        interceptorStarts += 1; zoomHandler = onPress; return true
    }
    func stopZoomClickInterceptor() { zoomHandler = nil }
}

@MainActor private final class SpacesPreferenceFixture: SpacesPreferenceBackend {
    var currentMru: Bool? = true
    var writes: [Bool] = []
    var allowWrite = true
    func readMruSpaces() -> Bool? { currentMru }
    func writeMruSpaces(_ value: Bool) -> Bool {
        guard allowWrite else { return false }
        writes.append(value); currentMru = value; return true
    }
}

@MainActor private final class AutoQuitSchedulerFixture: AutoQuitScheduling {
    var scheduled: [String: (Int, @MainActor () -> Void)] = [:]
    func schedule(id: String, seconds: Int, perform: @escaping @MainActor () -> Void) {
        scheduled[id] = (seconds, perform)
    }
    func cancel(id: String) { scheduled.removeValue(forKey: id) }
    func cancelAll() { scheduled = [:] }
    func fire(id: String) {
        let action = scheduled.removeValue(forKey: id)?.1
        action?()
    }
}

extension MacContractsTests {
    @Suite(.tags(.desktop, .isolated)) @MainActor struct DockSpacesContracts {
        @Test("G25.02 dockPreview and dockClick minimize, restore, hide and bring forward windows only after opt-in")
        func dockPreviewAndClick() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = DockAndZoomBackendFixture()
            let spaces = SpacesPreferenceFixture()
            let scheduler = AutoQuitSchedulerFixture()
            let app = DesktopApp(pid: 202, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Notes")
            let w1 = DockWindowPreview(id: UUID(), app: app, title: "Note 1", frame: CGRect(x: 0, y: 0, width: 600, height: 400), isMinimized: false)
            let w2 = DockWindowPreview(id: UUID(), app: app, title: "Note 2", frame: CGRect(x: 50, y: 50, width: 600, height: 400), isMinimized: true)
            backend.previewMap[app.id] = [w1, w2]

            let model = DockSpacesController(defaults: store.value, backend: backend, spacesBackend: spaces, autoQuitScheduler: scheduler, trusted: { true })
            model.start()
            // Disabled by default
            model.loadDockPreview(for: app)
            #expect(model.previewWindows.isEmpty)

            model.dockPreviewEnabled = true
            model.loadDockPreview(for: app)
            #expect(model.previewWindows.count == 2)
            #expect(model.togglePreviewMinimize(w1.id))
            #expect(model.previewWindows.first?.isMinimized == true)

            // Dock click behavior: minimize or restore
            model.dockClickBehavior = .minimizeOrRestore
            // Both w1 and w2 are now minimized -> clicking active Dock icon restores them
            let restoredMsg = model.handleDockClick(for: app, wasFrontmost: true)
            #expect(restoredMsg.contains("Restored") && model.previewWindows.allSatisfy { !$0.isMinimized })
            // Clicking again minimizes visible windows
            let minimizedMsg = model.handleDockClick(for: app, wasFrontmost: true)
            #expect(minimizedMsg.contains("Minimized") && model.previewWindows.allSatisfy(\.isMinimized))

            // Hide active app
            model.dockClickBehavior = .hideActiveApp
            _ = model.handleDockClick(for: app, wasFrontmost: true)
            #expect(backend.hiddenApps == [app.id])
            model.stop()
        }

        @Test("G25.03 windowMaximizer intercepts green zoom button to fill usable desktop and restores previous frame on second click")
        func greenButtonMaximizeAndRestore() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = DockAndZoomBackendFixture()
            let spaces = SpacesPreferenceFixture()
            let scheduler = AutoQuitSchedulerFixture()
            let app = DesktopApp(pid: 303, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Safari")
            let initialFrame = CGRect(x: 120, y: 80, width: 700, height: 500)
            let usable = CGRect(x: 0, y: 25, width: 1440, height: 825)
            let win = DesktopWindow(id: UUID(), app: app, title: "Docs", frame: initialFrame)
            backend.zoomTarget = GreenZoomTarget(window: win, usableScreen: usable)

            let model = DockSpacesController(defaults: store.value, backend: backend, spacesBackend: spaces, autoQuitScheduler: scheduler, trusted: { true })
            model.start()
            #expect(backend.zoomHandler == nil)
            model.greenButtonMaximizes = true
            let handler = try #require(backend.zoomHandler)

            // First click on green button maximizes to usable area
            #expect(handler(CGPoint(x: 135, y: 90)))
            #expect(backend.frameWrites.last?.1 == usable)

            // Second click on green button while maximized restores original frame
            #expect(handler(CGPoint(x: 15, y: 35)))
            #expect(backend.frameWrites.last?.1 == initialFrame)
            model.stop()
            #expect(backend.zoomHandler == nil)
        }

        @Test("G25.04 autoQuit only terminates previously windowed non-protected apps whose window count stays zero after grace delay")
        func autoQuitLastWindow() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = DockAndZoomBackendFixture()
            let spaces = SpacesPreferenceFixture()
            let scheduler = AutoQuitSchedulerFixture()
            let notes = DesktopApp(pid: 404, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Notes")
            let finder = DesktopApp(pid: 405, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Finder")
            let helper = DesktopApp(pid: 406, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Helper")
            backend.bundleMap[notes.id] = "com.apple.Notes"
            backend.bundleMap[finder.id] = "com.apple.finder"
            backend.bundleMap[helper.id] = "com.example.Helper"

            let model = DockSpacesController(defaults: store.value, backend: backend, spacesBackend: spaces, autoQuitScheduler: scheduler, trusted: { true })
            model.autoQuitEnabled = true
            model.autoQuitDelaySeconds = 3
            model.start()

            // Observe Notes and Finder with 1 window; Helper has 0 windows and was never seen with a window
            let wNotes = DesktopWindow(id: UUID(), app: notes, title: "Memo", frame: CGRect(x: 0, y: 0, width: 400, height: 300))
            let wFinder = DesktopWindow(id: UUID(), app: finder, title: "Home", frame: CGRect(x: 0, y: 0, width: 400, height: 300))
            backend.windowCounts[notes.id] = 1
            backend.windowCounts[finder.id] = 1
            backend.windowCounts[helper.id] = 0
            model.observeSnapshot(DesktopSnapshot(apps: [notes, finder, helper], windows: [wNotes, wFinder]))
            #expect(scheduler.scheduled.isEmpty)

            // Both Notes and Finder drop to 0 windows
            backend.windowCounts[notes.id] = 0
            backend.windowCounts[finder.id] = 0
            model.observeSnapshot(DesktopSnapshot(apps: [notes, finder, helper], windows: []))
            // Finder and windowless Helper are never scheduled
            #expect(scheduler.scheduled[finder.id] == nil && scheduler.scheduled[helper.id] == nil)
            #expect(scheduler.scheduled[notes.id]?.0 == 3)

            // If Notes reopens a window before timer fires, it is not terminated
            backend.windowCounts[notes.id] = 1
            scheduler.fire(id: notes.id)
            #expect(backend.terminatedApps.isEmpty)

            // Now Notes closes its last window and stays at 0 when timer fires
            backend.windowCounts[notes.id] = 0
            model.observeSnapshot(DesktopSnapshot(apps: [notes], windows: []))
            scheduler.fire(id: notes.id)
            #expect(backend.terminatedApps == [notes.id])
            model.stop()
        }

        @Test("G25.04 native window notifications schedule once; unknown reads and reopen cancel safely")
        func observedCloseAndUnknown() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = DockAndZoomBackendFixture(), events = DockActivityFixture(), scheduler = AutoQuitSchedulerFixture()
            let app = DesktopApp(pid: 909, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Fixture")
            backend.bundleMap[app.id] = "com.example.fixture"
            let model = DockSpacesController(defaults: store.value, backend: backend, spacesBackend: SpacesPreferenceFixture(), autoQuitScheduler: scheduler, activityMonitor: events, trusted: { true })
            model.autoQuitEnabled = true; model.start()
            let changed = try #require(events.changed)
            changed(app); #expect(scheduler.scheduled.isEmpty)
            backend.windowCounts[app.id] = 1; changed(app)
            backend.windowCounts[app.id] = 0; changed(app)
            #expect(scheduler.scheduled.count == 1)
            backend.windowCounts[app.id] = nil; changed(app)
            #expect(scheduler.scheduled.isEmpty)
            backend.windowCounts[app.id] = 0; changed(app)
            backend.windowCounts[app.id] = nil; scheduler.fire(id: app.id)
            #expect(backend.terminatedApps.isEmpty)
            backend.windowCounts[app.id] = 1; changed(app)
            backend.windowCounts[app.id] = 0; changed(app)
            scheduler.fire(id: app.id); #expect(backend.terminatedApps == [app.id])
            model.stop(); changed(app); #expect(scheduler.scheduled.isEmpty)
        }
        @Test("G25.02 native Dock hover/click reach previews and actions only while opted in")
        func nativeDockRouting() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = DockAndZoomBackendFixture(), events = DockActivityFixture()
            let app = DesktopApp(pid: 910, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Fixture")
            let item = DockWindowPreview(id: UUID(), app: app, title: "Owned fixture", frame: CGRect(x: 0, y: 0, width: 500, height: 300), isMinimized: false)
            backend.previewMap[app.id] = [item]
            let model = DockSpacesController(defaults: store.value, backend: backend, spacesBackend: SpacesPreferenceFixture(), autoQuitScheduler: AutoQuitSchedulerFixture(), activityMonitor: events, trusted: { true })
            model.start(); #expect(events.starts == 0)
            model.dockPreviewEnabled = true
            events.hover?(app, CGRect(x: 20, y: 800, width: 50, height: 50))
            #expect(events.previews.count == 1 && model.previewWindows == [item])
            events.minimize?(item.id); #expect(events.previews.first?.isMinimized == true)
            events.select?(item.id); #expect(backend.previewMap[app.id]?.first?.isMinimized == false)
            model.dockClickBehavior = .hideActiveApp
            let prepare = try #require(events.prepareClick)
            #expect(prepare(app, false) == nil && backend.hiddenApps.isEmpty)
            let action = try #require(prepare(app, true))
            #expect(backend.hiddenApps.isEmpty, "Down prepares only; the native gesture continues")
            action(); #expect(backend.hiddenApps == [app.id])
            model.setLocked(true); #expect(prepare(app, true) == nil && events.prepareClick == nil)
            model.stop()
        }
        @Test("G25.02 native Dock restore cannot reverse the intent captured before mouse-up")
        func beforeNativeDockIntent() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = DockAndZoomBackendFixture(), events = DockActivityFixture()
            let app = DesktopApp(pid: 911, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Fixture")
            let one = DockWindowPreview(id: UUID(), app: app, title: "One", frame: CGRect(x: 0, y: 0, width: 500, height: 300), isMinimized: true)
            let two = DockWindowPreview(id: UUID(), app: app, title: "Two", frame: one.frame, isMinimized: true)
            backend.previewMap[app.id] = [one, two]
            let model = DockSpacesController(defaults: store.value, backend: backend, spacesBackend: SpacesPreferenceFixture(), autoQuitScheduler: AutoQuitSchedulerFixture(), activityMonitor: events, trusted: { true })
            model.start(); defer { model.stop() }
            model.dockClickBehavior = .minimizeOrRestore
            let prepare = try #require(events.prepareClick)
            let restore = try #require(prepare(app, true))
            #expect(backend.minimizeWrites.isEmpty)
            // The Dock itself restores one window before our observed up.
            backend.previewMap[app.id]?[0].isMinimized = false
            restore()
            #expect(backend.previewMap[app.id]?.allSatisfy { !$0.isMinimized } == true)
            #expect(backend.minimizeWrites.count == 1 && backend.minimizeWrites.first?.0 == two.id && backend.minimizeWrites.first?.1 == false)
            restore(); #expect(backend.minimizeWrites.count == 1, "Already achieved intent never toggles back")
            let minimize = try #require(prepare(app, true))
            let newWindow = DockWindowPreview(id: UUID(), app: app, title: "New", frame: one.frame, isMinimized: false)
            backend.previewMap[app.id]?.append(newWindow)
            minimize()
            #expect(backend.minimizeWrites.count == 3)
            #expect(backend.previewMap[app.id]?.first { $0.id == newWindow.id }?.isMinimized == false)
            minimize(); #expect(backend.minimizeWrites.count == 3)
        }
        @Test("G25.05 restore preserves external Spaces edits, including a restart with an ownership marker")
        func externalSpacesChange() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = DockAndZoomBackendFixture(), spaces = SpacesPreferenceFixture()
            let model = DockSpacesController(defaults: store.value, backend: backend, spacesBackend: spaces, autoQuitScheduler: AutoQuitSchedulerFixture(), trusted: { true })
            model.start(); model.keepSpacesOrderFixed = true
            #expect(spaces.currentMru == false)
            spaces.currentMru = true; let writes = spaces.writes.count
            // Simulate relaunch with a persisted ownership marker after an
            // external change; no original instance shutdown writes the value.
            let relaunched = DockSpacesController(defaults: store.value, backend: backend, spacesBackend: spaces, autoQuitScheduler: AutoQuitSchedulerFixture(), trusted: { true })
            relaunched.start()
            #expect(!relaunched.keepSpacesOrderFixed && spaces.writes.count == writes)
            relaunched.stop()
            model.keepSpacesOrderFixed = false
            #expect(spaces.currentMru == true && spaces.writes.count == writes && model.savedOriginalMruSpaces == nil)
            model.stop()
        }
        @Test("G25.05 spacesOrder backs up original mru-spaces value and restores on disable, sleep or stop")
        func spacesOrderRestore() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = DockAndZoomBackendFixture()
            let spaces = SpacesPreferenceFixture(); spaces.currentMru = nil
            let scheduler = AutoQuitSchedulerFixture()

            let model = DockSpacesController(defaults: store.value, backend: backend, spacesBackend: spaces, autoQuitScheduler: scheduler, trusted: { true })
            model.start()
            // Refuses to write if current value cannot be read
            model.keepSpacesOrderFixed = true
            #expect(spaces.writes.isEmpty && model.savedOriginalMruSpaces == nil)

            spaces.currentMru = true
            model.configureSpacesOrder()
            #expect(model.savedOriginalMruSpaces == true && spaces.writes == [false] && spaces.currentMru == false)

            // Sleep restores original
            model.setSleeping(true)
            #expect(spaces.currentMru == true)
            model.setSleeping(false)
            #expect(spaces.currentMru == false)

            // Explicit restore clears backup and restores true
            model.restoreOriginalSpacesOrder()
            #expect(!model.keepSpacesOrderFixed && model.savedOriginalMruSpaces == nil && spaces.currentMru == true)
            model.stop()
        }
    }
}

@MainActor private final class DockActivityFixture: DockActivityMonitoring {
    var starts = 0
    var hover: (@MainActor (DesktopApp?, CGRect?) -> Void)?
    var prepareClick: (@MainActor (DesktopApp, Bool) -> (@MainActor () -> Void)?)?
    var changed: (@MainActor (DesktopApp) -> Void)?
    var select: (@MainActor (UUID) -> Void)?, minimize: (@MainActor (UUID) -> Void)?
    var previews: [DockWindowPreview] = []
    func start(previews: Bool, clicks: Bool, autoQuit: Bool,
               hover: @escaping @MainActor (DesktopApp?, CGRect?) -> Void,
               prepareClick: @escaping @MainActor (DesktopApp, Bool) -> (@MainActor () -> Void)?,
               windowsChanged: @escaping @MainActor (DesktopApp) -> Void) {
        starts += 1; self.hover = hover; self.prepareClick = prepareClick; changed = windowsChanged
    }
    func showPreview(_ windows: [DockWindowPreview], anchor: CGRect, select: @escaping @MainActor (UUID) -> Void, minimize: @escaping @MainActor (UUID) -> Void) {
        previews = windows; self.select = select; self.minimize = minimize
    }
    func hidePreview() { previews = [] }
    func stop() { hover = nil; prepareClick = nil; changed = nil; hidePreview() }
}

@MainActor private final class DockDwellFixture: PointerDwellScheduling {
    var action: (@MainActor () -> Void)?
    func schedule(_ perform: @escaping @MainActor () -> Void) { action = perform }
    func cancel() { action = nil }
    func fire() { let next = action; action = nil; next?() }
}

extension MacContractsTests {
    @Suite(.tags(.desktop, .isolated)) @MainActor struct DockObservationTests {
        private var hit: DockIconHit {
            DockIconHit(app: DesktopApp(pid: 912, launchedAt: Date(timeIntervalSince1970: 1_800_000_000), name: "Fixture"), anchor: CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        @Test("G25.02 Dock observation applies once on short same-icon up, never on down")
        func shortClick() {
            let target = hit; var actions = 0
            let gesture = DockClickObservation(hitTest: { _ in target }, prepare: { _ in { actions += 1 } })
            gesture.receive(.down, at: CGPoint(x: 10, y: 10), time: 10, modified: false)
            #expect(actions == 0)
            gesture.receive(.up, at: CGPoint(x: 12, y: 10), time: 10.1, modified: false)
            gesture.receive(.up, at: CGPoint(x: 12, y: 10), time: 10.2, modified: false)
            #expect(actions == 1)
        }
        @Test("G25.02 Dock drag, hold, modifiers and changed target retain native behavior", arguments: ["drag", "hold", "moved", "modifierDown", "modifierUp", "flagsOrContext", "changedApp", "relaunch", "missingIcon", "doubleClick"])
        func rejectedGesture(_ kind: String) {
            let original = hit; var target: DockIconHit? = original, actions = 0
            let gesture = DockClickObservation(hitTest: { _ in target }, prepare: { _ in { actions += 1 } })
            gesture.receive(.down, at: CGPoint(x: 10, y: 10), time: 10, modified: kind == "modifierDown", clickCount: kind == "doubleClick" ? 2 : 1)
            switch kind {
            case "drag": gesture.receive(.dragged, at: CGPoint(x: 11, y: 10), time: 10.05, modified: false)
            case "flagsOrContext": gesture.cancel()
            case "changedApp": target = DockIconHit(app: DesktopApp(pid: 999, launchedAt: original.app.launchedAt, name: "Other"), anchor: original.anchor)
            case "relaunch": target = DockIconHit(app: DesktopApp(pid: original.app.pid, launchedAt: Date(timeIntervalSince1970: 1_800_000_001), name: "Fixture"), anchor: original.anchor)
            case "missingIcon": target = nil
            default: break
            }
            gesture.receive(.up, at: CGPoint(x: kind == "moved" ? 20 : 10, y: 10), time: kind == "hold" ? 11 : 10.1, modified: kind == "modifierUp")
            #expect(actions == 0)
        }
        @Test("G25.02 hover leaving inside throttle cancels without querying AX again")
        func throttledExit() throws {
            let target = hit, dwell = DockDwellFixture(); var point = CGPoint(x: 10, y: 10), queries = 0, shown = 0
            let tracker = DockHoverTracking(dwell: dwell, location: { point }, hitTest: { p in queries += 1; return target.anchor.contains(p) ? target : nil }, show: { _ in shown += 1 }, hide: {})
            tracker.moved(point, at: 0)
            let late = try #require(dwell.action)
            point = CGPoint(x: 100, y: 100); tracker.moved(point, at: 0.05)
            late()
            #expect(shown == 0 && queries == 1 && dwell.action == nil)
        }
        @Test("G25.02 hover expiry revalidates injected current position and Dock identity", arguments: ["leftWithoutEvent", "relaunch", "newAnchor", "noPosition"])
        func currentHover(_ kind: String) {
            let original = hit, dwell = DockDwellFixture(); var point: CGPoint? = CGPoint(x: 10, y: 10), target = original
            var shown: [DockIconHit] = []
            let tracker = DockHoverTracking(dwell: dwell, location: { point }, hitTest: { p in target.anchor.contains(p) ? target : nil }, show: { shown.append($0) }, hide: {})
            tracker.moved(point!, at: 0)
            switch kind {
            case "leftWithoutEvent": point = CGPoint(x: 100, y: 100)
            case "relaunch": target = DockIconHit(app: DesktopApp(pid: original.app.pid, launchedAt: Date(timeIntervalSince1970: 1_800_000_001), name: "Fixture"), anchor: original.anchor)
            case "newAnchor": target = DockIconHit(app: original.app, anchor: original.anchor.insetBy(dx: -5, dy: -5))
            default: point = nil
            }
            dwell.fire()
            #expect(shown == (kind == "newAnchor" ? [target] : []))
        }
    }
}
