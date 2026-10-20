import AppKit
import Foundation
import Testing

extension LogicTests {
    @Suite(.tags(.desktop)) struct DockSpacesLogicTests {
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

    func previews(for app: DesktopApp) -> [DockWindowPreview] { previewMap[app.id] ?? [] }
    func setMinimized(_ minimized: Bool, windowID: UUID) -> Bool {
        for (appID, items) in previewMap {
            if let idx = items.firstIndex(where: { $0.id == windowID }) {
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
