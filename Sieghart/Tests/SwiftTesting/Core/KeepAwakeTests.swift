import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.utilities, .isolated)) @MainActor
  struct KeepAwakeTests {
    @Test("G14.03 AC, owned token replacement, sleep, wake and deadlines")
    func assertionOwnership() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      var clock = Date(timeIntervalSince1970: 1_800_000_000)
      let engine = CoreSampleAwake()
      let awake = KeepAwakeViewModel(backend: engine, defaults: defaults, now: { clock })
      #expect(engine.acquired.isEmpty && !awake.enabled)
      awake.request.onlyOnAC = true
      engine.current.onAC = false
      awake.start()
      #expect(awake.enabled && !awake.holding && engine.acquired.isEmpty)
      engine.current.onAC = true
      awake.tick()
      awake.tick()
      #expect(
        awake.holding && engine.acquired.count == 1, "One owned assertion, not one per refresh")
      awake.request.keepDisplay = true
      awake.saveOptions()
      #expect(engine.released == [1] && engine.acquired == [false, true])
      awake.setSleeping(true)
      #expect(!awake.holding && engine.released == [1, 2])
      awake.setSleeping(false)
      #expect(awake.holding && engine.acquired.count == 3)
      engine.current.onAC = false
      awake.tick()
      #expect(!awake.holding && engine.released.count == 3)
      clock = clock.addingTimeInterval(1900)
      awake.tick()
      #expect(!awake.enabled && !awake.holding)
      awake.request.mode = .until
      awake.request.until = clock.addingTimeInterval(-1)
      awake.start()
      #expect(!awake.enabled && awake.error != nil)
      defer { awake.shutdown() }
    }

    @Test(
      "G14.04 app and display conditions, explicit lifecycle restoration and acquisition failure")
    func conditionalRestore() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      var clock = Date(timeIntervalSince1970: 1_800_000_000)
      let engine = CoreSampleAwake()
      let awake = KeepAwakeViewModel(backend: engine, defaults: defaults, now: { clock })

      awake.request.onlyOnAC = true
      engine.current.onAC = false
      awake.start()

      engine.current.onAC = true
      awake.tick()
      awake.tick()

      awake.request.keepDisplay = true
      awake.saveOptions()

      awake.setSleeping(true)
      awake.setSleeping(false)
      engine.current.onAC = false
      awake.tick()
      clock = clock.addingTimeInterval(1900)
      awake.tick()
      awake.request.mode = .until
      awake.request.until = clock.addingTimeInterval(-1)
      awake.start()

      awake.request.mode = .indefinite
      awake.request.onlyOnAC = false
      awake.request.externalDisplayOnly = true
      awake.request.applications = ["fixture.app"]
      awake.start()
      #expect(!awake.holding)
      engine.current.externalDisplay = true
      engine.current.applications = ["fixture.app"]
      awake.tick()
      #expect(awake.holding)
      awake.request.restoreOnLaunch = true
      awake.saveOptions()
      awake.shutdown()
      let restoredEngine = CoreSampleAwake()
      restoredEngine.current = engine.current
      let restored = KeepAwakeViewModel(backend: restoredEngine, defaults: defaults, now: { clock })
      #expect(restoredEngine.acquired.isEmpty)
      restored.startLifecycle(center: NotificationCenter())
      #expect(restored.enabled && restored.holding)
      restored.stop()
      restored.shutdown()
      let failedEngine = CoreSampleAwake()
      failedEngine.fails = true
      let failed = KeepAwakeViewModel(backend: failedEngine, defaults: defaults, now: { clock })
      failed.request.externalDisplayOnly = false
      failed.request.applications = []
      failed.start()
      #expect(!failed.holding && failed.error != nil)
      failed.stop()
      defer {
        awake.shutdown()
        failed.shutdown()
      }
    }

  }
}
