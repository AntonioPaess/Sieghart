import AppKit
import Foundation

@MainActor private final class SampleMonitor: SystemSampling {
    var samples: [MonitorReading] = []
    var calls = 0
    func read() -> MonitorReading { defer { calls += 1 }; return samples[min(calls, samples.count - 1)] }
}
@MainActor private final class SampleAwake: AwakeBackend {
    var current = AwakeContext()
    var acquired: [Bool] = []
    var released: [UInt32] = []
    var fails = false
    func context() -> AwakeContext { current }
    func acquire(display: Bool) throws -> UInt32 { if fails { throw UtilityFailure(message: "Fixture refused") }; acquired.append(display); return UInt32(acquired.count) }
    func release(_ token: UInt32) { released.append(token) }
}
@MainActor private final class SampleDisplay: DisplayPowerBackend {
    var fixture = [DisplayInfo(id: 42, name: "Fixture display", builtIn: true, brightness: 0.7, hdrHeadroom: 2)]
    var brightnessWrites: [Double] = []
    var dimWrites: [Double] = []
    var restoreCount = 0
    var sleeps = 0
    var connected = ["A", "B"]
    var disconnected: [String] = []
    var reconnected: [String] = []
    var fails = false
    func displays() -> [DisplayInfo] { fixture }
    func brightness(_ value: Double, display: CGDirectDisplayID) throws { if fails { throw UtilityFailure(message: "Unsupported fixture") }; brightnessWrites.append(value); fixture[0].brightness = value }
    func dim(_ value: Double, display: CGDirectDisplayID) throws { dimWrites.append(value); fixture[0].dimming = value }
    func restore() { restoreCount += 1 }
    func sleepDisplays() throws { sleeps += 1 }
    func connectedBluetooth() -> [String] { connected }
    func disconnectBluetooth(_ id: String) throws { if id == "B" { throw UtilityFailure(message: "B couldn't disconnect") }; disconnected.append(id) }
    func reconnectBluetooth(_ id: String) throws { reconnected.append(id) }
}
@main struct UtilityChecks {
    @MainActor static func main() async {
        let suite = "Sieghart.UtilityChecks.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = MonitorReading(); first.sampledAt = Date(); first.counters = SystemCounters(time: 10, cpu: [10, 10, 80, 0], received: 1000, sent: 500, diskRead: 500, diskWritten: 100, diskIOAvailable: true)
        var second = first; second.counters = SystemCounters(time: 12, cpu: [20, 20, 160, 0], received: 1600, sent: 700, diskRead: 1100, diskWritten: 300, diskIOAvailable: true)
        second.derive(from: first.counters)
        precondition(second.cpu == 0.2 && second.download == 300 && second.upload == 100 && second.diskReadRate == 300 && second.diskWriteRate == 100)
        precondition(MonitorReading.rate(10, previous: 20, seconds: 2) == nil, "Resetting a counter must not overflow")
        precondition(MonitorReading.rate(30, previous: 20, seconds: 0) == nil)
        var unavailable = first; unavailable.counters.diskIOAvailable = false; unavailable.derive(from: first.counters)
        precondition(unavailable.diskReadRate == nil && unavailable.gpu == nil, "Missing hardware readings aren't fabricated")
        let sampler = SampleMonitor(); sampler.samples = [first, second]
        let monitor = SystemMonitor(backend: sampler)
        precondition(sampler.calls == 0, "Constructing a model must not sample the Mac")
        for _ in 0..<75 { monitor.refresh() }
        precondition(monitor.history.count == 60)

        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let engine = SampleAwake(), awake = KeepAwakeController(backend: engine, defaults: defaults, now: { clock })
        precondition(engine.acquired.isEmpty && !awake.enabled)
        awake.request.onlyOnAC = true; engine.current.onAC = false; awake.start()
        precondition(awake.enabled && !awake.holding && engine.acquired.isEmpty)
        engine.current.onAC = true; awake.tick(); awake.tick()
        precondition(awake.holding && engine.acquired.count == 1, "One owned assertion, not one per refresh")
        awake.request.keepDisplay = true; awake.saveOptions()
        precondition(engine.released == [1] && engine.acquired == [false, true])
        awake.setSleeping(true); precondition(!awake.holding && engine.released == [1, 2])
        awake.setSleeping(false); precondition(awake.holding && engine.acquired.count == 3)
        engine.current.onAC = false; awake.tick(); precondition(!awake.holding && engine.released.count == 3)
        clock = clock.addingTimeInterval(1900); awake.tick(); precondition(!awake.enabled && !awake.holding)
        awake.request.mode = .until; awake.request.until = clock.addingTimeInterval(-1); awake.start()
        precondition(!awake.enabled && awake.error != nil)
        awake.request.mode = .indefinite; awake.request.onlyOnAC = false; awake.request.externalDisplayOnly = true; awake.request.applications = ["fixture.app"]
        awake.start(); precondition(!awake.holding)
        engine.current.externalDisplay = true; engine.current.applications = ["fixture.app"]; awake.tick(); precondition(awake.holding)
        awake.request.restoreOnLaunch = true; awake.saveOptions(); awake.shutdown()
        let restoredEngine = SampleAwake(); restoredEngine.current = engine.current
        let restored = KeepAwakeController(backend: restoredEngine, defaults: defaults, now: { clock })
        precondition(restoredEngine.acquired.isEmpty)
        restored.startLifecycle(center: NotificationCenter()); precondition(restored.enabled && restored.holding)
        restored.stop(); restored.shutdown()
        let failedEngine = SampleAwake(); failedEngine.fails = true
        let failed = KeepAwakeController(backend: failedEngine, defaults: defaults, now: { clock }); failed.request.externalDisplayOnly = false; failed.request.applications = []; failed.start()
        precondition(!failed.holding && failed.error != nil); failed.stop()

        let adapter = SampleDisplay(), display = DisplayPowerController(backend: adapter, defaults: defaults)
        precondition(adapter.brightnessWrites.isEmpty && adapter.sleeps == 0)
        display.refresh(); display.setBrightness(2, display: adapter.fixture[0]); display.setDimming(0, display: adapter.fixture[0])
        precondition(adapter.brightnessWrites == [1] && adapter.dimWrites == [0.2])
        adapter.fails = true; display.setBrightness(0.4, display: adapter.fixture[0]); precondition(display.error != nil && adapter.brightnessWrites == [1])
        display.willSleep(); display.didWake(); precondition(adapter.disconnected.isEmpty && adapter.reconnected.isEmpty, "Bluetooth sleep is opt-in")
        display.disconnectBluetoothOnSleep = true; display.willSleep(); display.didWake(); display.didWake()
        precondition(adapter.disconnected == ["A"] && adapter.reconnected == ["A"], "Restore only successfully disconnected devices, once")
        display.sleepDisplays(); display.restoreBrightness(); precondition(adapter.sleeps == 1 && adapter.restoreCount > 0)
        precondition(DisplayPowerController.shouldBlockMusic(enabled: true, launch: 12, lastPlayKey: 11))
        precondition(!DisplayPowerController.shouldBlockMusic(enabled: true, launch: 15, lastPlayKey: 11))
        precondition(!DisplayPowerController.shouldBlockMusic(enabled: false, launch: 12, lastPlayKey: 11))
        precondition(!DisplayPowerController.shouldBlockMusic(enabled: true, launch: 10, lastPlayKey: 11))
        display.shutdown()
        print("Utility checks passed: counter deltas/reset, bounded history, assertion ownership/conditions/sleep/deadlines/restoration, brightness capabilities, safe dimming, owned Bluetooth restoration and playback launch gating. No real system action used.")
    }
}
