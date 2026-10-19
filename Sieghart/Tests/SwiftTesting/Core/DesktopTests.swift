import AppKit
import Testing

extension LogicTests {
    @Suite(.tags(.desktop)) struct WindowGeometryTests {
        @Test("G20.01 every layout stays inside the usable work area", arguments: WindowLayout.allCases)
        func layouts(_ layout: WindowLayout) throws {
            let usable = CGRect(x: -1600, y: -880, width: 1440, height: 840)
            let frame = try #require(WindowGeometry.frame(layout, current: CGRect(x: -1500, y: -800, width: 600, height: 400), usable: usable))
            #expect(usable.contains(frame))
            switch layout {
            case .left: #expect(frame == CGRect(x: -1600, y: -880, width: 720, height: 840))
            case .right: #expect(frame == CGRect(x: -880, y: -880, width: 720, height: 840))
            case .topLeft: #expect(frame == CGRect(x: -1600, y: -880, width: 720, height: 420))
            case .topRight: #expect(frame == CGRect(x: -880, y: -880, width: 720, height: 420))
            case .bottomLeft: #expect(frame == CGRect(x: -1600, y: -460, width: 720, height: 420))
            case .bottomRight: #expect(frame == CGRect(x: -880, y: -460, width: 720, height: 420))
            case .maximize: #expect(frame == usable)
            case .center: #expect(frame == CGRect(x: -1180, y: -660, width: 600, height: 400))
            }
        }
        @Test("G20.02 AppKit conversion and selection cover displays above, left and disconnected")
        func displays() throws {
            let above = DesktopScreen.accessibilityRect(CGRect(x: -200, y: 900, width: 1600, height: 1000), primaryTop: 900)
            #expect(above == CGRect(x: -200, y: -1000, width: 1600, height: 1000))
            let primary = DesktopScreen(frame: CGRect(x: 0, y: 0, width: 1600, height: 900), usable: CGRect(x: 0, y: 25, width: 1600, height: 825))
            let left = DesktopScreen(frame: CGRect(x: -1200, y: 100, width: 1200, height: 800), usable: CGRect(x: -1200, y: 125, width: 1200, height: 735))
            #expect(WindowGeometry.screen(for: CGRect(x: -500, y: 300, width: 600, height: 400), in: [primary, left]) == left)
            #expect(WindowGeometry.screen(for: CGRect(x: -1400, y: 300, width: 100, height: 100), in: [primary, left]) == left)
            #expect(WindowGeometry.screen(for: CGRect(x: -1400, y: 300, width: 100, height: 100), in: [primary]) == primary)
            #expect(WindowGeometry.screen(for: .zero, in: [primary]) == nil)
            #expect(WindowGeometry.frame(.center, current: CGRect(x: 0, y: 0, width: 3000, height: 2000), usable: primary.usable) == primary.usable)
        }
        @Test("G20.03 edge mapping, corners and interior do not overlap incorrectly")
        func edges() {
            let screen = DesktopScreen(frame: CGRect(x: -1000, y: -800, width: 1000, height: 800), usable: CGRect(x: -1000, y: -775, width: 1000, height: 725))
            let samples: [(CGPoint, WindowLayout?)] = [
                (.init(x: -999, y: -799), .topLeft), (.init(x: -1, y: -799), .topRight),
                (.init(x: -999, y: -1), .bottomLeft), (.init(x: -1, y: -1), .bottomRight),
                (.init(x: -999, y: -400), .left), (.init(x: -1, y: -400), .right),
                (.init(x: -500, y: -799), .maximize), (.init(x: -500, y: -1), nil),
                (.init(x: -500, y: -400), nil), (.init(x: 100, y: 100), nil)]
            for (point, expected) in samples { #expect(WindowGeometry.snap(at: point, screens: [screen])?.1 == expected) }
            #expect(WindowGeometry.snap(at: CGPoint(x: CGFloat.nan, y: 0), screens: [screen]) == nil)
        }
        @Test("G20.04 reject clicks, resizes and invalid geometry")
        func movement() {
            let before = CGRect(x: 50, y: 100, width: 500, height: 400)
            #expect(!WindowGeometry.movedWithoutResize(from: before, to: before.offsetBy(dx: 1, dy: 1)))
            #expect(!WindowGeometry.movedWithoutResize(from: before, to: CGRect(x: 1, y: 1, width: 600, height: 400)))
            #expect(WindowGeometry.movedWithoutResize(from: before, to: before.offsetBy(dx: -50, dy: 30)))
            #expect(!WindowGeometry.valid(CGRect(x: CGFloat.infinity, y: 0, width: 1, height: 1)))
            #expect(WindowGeometry.frame(.left, current: before, usable: .zero) == nil)
        }
    }
}

@MainActor private final class DesktopBackendFixture: DesktopManaging {
    let app = DesktopApp(pid: 98765, launchedAt: Date(timeIntervalSince1970: 1800000000), name: "Fixture")
    var records: [DesktopWindow] = []
    var writes: [(UUID, CGRect)] = []
    var activations: [String] = []
    var discoveries = 0
    var limited = false
    var failWrite = false
    var actualOverride: CGRect?
    var hitID: UUID?
    var display = DesktopScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), usable: CGRect(x: 0, y: 24, width: 1440, height: 826))
    init() { records = [DesktopWindow(id: UUID(), app: app, title: "One", frame: CGRect(x: 100, y: 100, width: 600, height: 400))]; hitID = records.first?.id }
    func discover() -> DesktopSnapshot { discoveries += 1; return DesktopSnapshot(apps: [app], windows: records, limited: limited) }
    func window(_ id: UUID) -> DesktopWindow? { records.first { $0.id == id } }
    func window(at point: CGPoint) -> DesktopWindow? { hitID.flatMap(window) }
    func screens() -> [DesktopScreen] { [display] }
    func setFrame(_ frame: CGRect, of id: UUID) -> WindowWriteResult {
        writes.append((id, frame))
        guard !failWrite, let index = records.firstIndex(where: { $0.id == id }) else { return .failed("Fixture refused layout") }
        let actual = actualOverride ?? frame; records[index].frame = actual; return .applied(actual)
    }
    func activate(app: DesktopApp) -> Bool { activations.append(app.id); return app == self.app }
    func activate(window: UUID) -> Bool { activations.append(window.uuidString); return records.contains { $0.id == window } }
}
@MainActor private final class DesktopMonitorFixture: DesktopDragMonitoring {
    var callbacks: [@MainActor (DesktopPointerPhase, CGPoint) -> Void] = []
    var receive: (@MainActor (DesktopPointerPhase, CGPoint) -> Void)?
    var fail = false
    var starts = 0
    func start(_ receive: @escaping @MainActor (DesktopPointerPhase, CGPoint) -> Void) -> Bool {
        starts += 1; callbacks.append(receive); self.receive = receive; return !fail
    }
    func stop() { receive = nil }
}

extension MacContractsTests {
    @Suite(.tags(.desktop, .isolated)) @MainActor struct DesktopContracts {
        @Test("G20.05 initialization and start stay inert until opt-in or explicit refresh")
        func consent() throws {
            let defaults = try TestDefaults(); defer { defaults.cleanup() }
            let backend = DesktopBackendFixture(), monitor = DesktopMonitorFixture()
            var trust = false, requests = 0
            let model = DesktopController(defaults: defaults.value, backend: backend, monitor: monitor, trusted: { trust }, requestAccess: { requests += 1 })
            model.start(observeSystem: false); model.refresh()
            #expect(backend.discoveries == 0 && monitor.starts == 0 && requests == 0)
            model.edgeSnapping = true; #expect(monitor.starts == 0 && requests == 0)
            model.allowAccess(); #expect(requests == 1 && monitor.starts == 0)
            trust = true; model.retrySnapping(); #expect(monitor.starts == 1 && backend.discoveries == 0)
            model.refresh(); #expect(backend.discoveries == 1 && model.windows.count == 1)
            let restored = DesktopController(defaults: defaults.value, backend: backend, monitor: DesktopMonitorFixture(), trusted: { true })
            #expect(restored.edgeSnapping)
            model.stop(); model.refresh(); #expect(backend.discoveries == 1 && monitor.receive == nil)
        }
        @Test("G20.06 layout reads the selected stable handle and records actual constrained geometry")
        func selectedWindow() throws {
            let defaults = try TestDefaults(); defer { defaults.cleanup() }
            let backend = DesktopBackendFixture()
            let model = DesktopController(defaults: defaults.value, backend: backend, monitor: DesktopMonitorFixture(), trusted: { true })
            model.start(observeSystem: false); model.refresh()
            let id = backend.records[0].id, before = backend.records[0].frame
            model.selectedID = id
            backend.records.insert(DesktopWindow(id: UUID(), app: backend.app, title: "New", frame: .init(x: 1, y: 1, width: 300, height: 200)), at: 0)
            let constrained = CGRect(x: 0, y: 24, width: 800, height: 826); backend.actualOverride = constrained
            model.apply(.left)
            #expect(backend.writes.last?.0 == id && model.canUndo && model.status.contains("adjusted"))
            backend.actualOverride = nil; backend.failWrite = true; model.undo()
            #expect(model.canUndo && backend.window(id)?.frame == constrained)
            backend.failWrite = false; model.undo()
            #expect(backend.window(id)?.frame == before && !model.canUndo)
            model.stop()
        }
        @Test("G20.07 undo never overwrites a manual change or a closed window")
        func staleUndo() throws {
            let defaults = try TestDefaults(); defer { defaults.cleanup() }
            let backend = DesktopBackendFixture()
            let model = DesktopController(defaults: defaults.value, backend: backend, monitor: DesktopMonitorFixture(), trusted: { true })
            model.start(observeSystem: false); model.refresh(); model.selectedID = backend.records[0].id
            model.apply(.left); backend.records[0].frame.origin.x += 20
            model.undo(); #expect(backend.writes.count == 1 && model.status.contains("skipped"))
            model.apply(.right); backend.records = []
            model.undo(); #expect(backend.writes.count == 2 && !model.canUndo)
            model.apply(.left); #expect(backend.writes.count == 2)
            model.stop()
        }
        @Test("G20.08 failed layout has no undo; history is bounded at 32")
        func history() throws {
            let defaults = try TestDefaults(); defer { defaults.cleanup() }
            let backend = DesktopBackendFixture()
            let model = DesktopController(defaults: defaults.value, backend: backend, monitor: DesktopMonitorFixture(), trusted: { true })
            model.start(observeSystem: false); model.refresh(); model.selectedID = backend.records[0].id
            backend.failWrite = true; model.apply(.left); #expect(!model.canUndo && model.status == "Fixture refused layout")
            backend.failWrite = false
            for index in 0..<40 { model.apply(index.isMultiple(of: 2) ? .left : .right) }
            let count = backend.writes.count
            for _ in 0..<35 { model.undo() }
            #expect(backend.writes.count == count + 32 && !model.canUndo)
            model.stop()
        }
        @Test("G20.09 edge snapping requires a moved window, excludes resize and restores dropped frame")
        func drag() throws {
            let defaults = try TestDefaults(); defer { defaults.cleanup() }
            let backend = DesktopBackendFixture(), monitor = DesktopMonitorFixture()
            let model = DesktopController(defaults: defaults.value, backend: backend, monitor: monitor, trusted: { true })
            model.start(observeSystem: false); model.edgeSnapping = true
            let callback = try #require(monitor.receive), edge = CGPoint(x: 1, y: 400)
            callback(.down, edge); callback(.up, edge); #expect(backend.writes.isEmpty)
            callback(.down, edge); backend.records[0].frame.origin.x += 40
            callback(.up, edge); #expect(backend.writes.isEmpty, "App-driven movement during a click is not a drag")
            callback(.down, .init(x: 100, y: 400)); callback(.dragged, edge)
            backend.records[0].frame.size.width += 80; callback(.up, edge); #expect(backend.writes.isEmpty)
            callback(.down, .init(x: 100, y: 400)); callback(.dragged, edge); backend.records[0].frame.origin.x -= 100
            let dropped = backend.records[0].frame
            callback(.up, edge); #expect(backend.writes.count == 1 && backend.records[0].frame.width == 720)
            model.undo(); #expect(backend.records[0].frame == dropped)
            callback(.down, edge); backend.records = []; callback(.up, edge); #expect(backend.writes.count == 2)
            model.stop()
        }
        @Test("G20.10 sleep, screen lock, inactive session, disabled options and old callbacks independently block snapping")
        func lifecycle() throws {
            let defaults = try TestDefaults(); defer { defaults.cleanup() }
            let backend = DesktopBackendFixture(), monitor = DesktopMonitorFixture()
            var trust = true
            let model = DesktopController(defaults: defaults.value, backend: backend, monitor: monitor, trusted: { trust })
            model.start(observeSystem: false); model.edgeSnapping = true
            let old = try #require(monitor.receive)
            old(.down, .zero); model.setLocked(true); model.setSessionActive(false); model.setSessionActive(true)
            #expect(monitor.receive == nil)
            model.setSleeping(true); model.setLocked(false); #expect(monitor.receive == nil)
            model.setSleeping(false); let callback = try #require(monitor.receive)
            backend.records[0].frame.origin.x += 50; old(.up, .init(x: 1, y: 400)); #expect(backend.writes.isEmpty)
            callback(.down, .zero); trust = false; callback(.up, .init(x: 1, y: 400))
            #expect(monitor.receive == nil && backend.writes.isEmpty)
            model.refresh(); #expect(model.apps.isEmpty && backend.discoveries == 0)
            trust = true; model.edgeSnapping = false; model.setSleeping(true); model.setSleeping(false)
            #expect(monitor.receive == nil)
            model.stop(); old(.down, .zero); old(.up, .zero); #expect(backend.writes.isEmpty)
        }
        @Test("G20.11 failed monitor start cannot retain a valid callback and retry installs once")
        func retry() throws {
            let defaults = try TestDefaults(); defer { defaults.cleanup() }
            let backend = DesktopBackendFixture(), monitor = DesktopMonitorFixture(); monitor.fail = true
            let model = DesktopController(defaults: defaults.value, backend: backend, monitor: monitor, trusted: { true })
            model.start(observeSystem: false); model.edgeSnapping = true
            let failed = try #require(monitor.callbacks.first)
            #expect(monitor.receive == nil && model.snapStatus.contains("unavailable"))
            monitor.fail = false; model.retrySnapping(); failed(.down, .zero)
            backend.records[0].frame.origin.x += 50; failed(.up, .init(x: 1, y: 400))
            #expect(backend.writes.isEmpty && monitor.starts == 2)
            model.stop()
        }
        @Test("G20.12 switcher activates only explicitly requested app or stable window; permission gates every action")
        func activation() throws {
            let defaults = try TestDefaults(); defer { defaults.cleanup() }
            let backend = DesktopBackendFixture(); var trust = true
            let model = DesktopController(defaults: defaults.value, backend: backend, monitor: DesktopMonitorFixture(), trusted: { trust })
            model.start(observeSystem: false); backend.limited = true; model.refresh()
            #expect(model.status.contains("Partial") && backend.activations.isEmpty)
            model.selectedID = backend.records[0].id; #expect(backend.activations.isEmpty)
            model.activate(app: backend.app); model.activate(window: backend.records[0].id)
            #expect(backend.activations == [backend.app.id, backend.records[0].id.uuidString])
            trust = false; model.activate(app: backend.app); model.apply(.left); model.undo()
            #expect(backend.activations.count == 2 && backend.writes.isEmpty && model.selectedID == nil)
            model.stop()
        }
        @Test("G20.13 native frame transaction restores partial failure and reports rollback failure")
        func transaction() {
            let original = CGRect(x: 100, y: 200, width: 500, height: 300), desired = CGRect(x: 0, y: 25, width: 720, height: 800)
            var current = original, writes = 0
            let result = WindowFrameWriter.write(desired, read: { current }, position: { point in
                writes += 1
                if writes == 1 { return false }
                current.origin = point; return true
            }, size: { size in current.size = size; return true })
            #expect(current == original)
            guard case .failed(let message) = result else { Issue.record("Partial failure reported as success"); return }
            #expect(message.contains("restored"))
            let failed = WindowFrameWriter.write(desired, read: { current }, position: { _ in false }, size: { size in
                if size == original.size { return false }; current.size = size; return true
            })
            guard case .failed(let failure) = failed else { Issue.record("Rollback failure reported as success"); return }
            #expect(failure.contains("could not restore"))
            let adjusted = CGRect(x: 0, y: 25, width: 900, height: 800)
            let success = WindowFrameWriter.write(desired, read: { current }, position: { point in current.origin = point; return true }, size: { _ in current.size = adjusted.size; return true })
            #expect(success == .applied(adjusted))
        }
    }
}
