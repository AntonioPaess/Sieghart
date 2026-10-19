import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.middleClick, .isolated)) @MainActor
  struct MiddleClickStateTests {
    @Test("G13.02 disabled state, explicit accessibility request and trusted start")
    func gestureConsent() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }

      let backend = CoreMiddleClickBackend()
      let delivery = CoreMiddleDelivery()
      var trusted = false
      var emitted = 0
      var asked = 0
      let model = MiddleClickController(
        defaults: defaults, backend: backend, trusted: { trusted }, requestAccess: { asked += 1 },
        emit: { emitted += 1 }, deliver: { delivery.enqueue($0) })

      model.start(observeSystem: false)
      #expect(!model.isEnabled && backend.starts == 0)
      model.isEnabled = true
      #expect(backend.starts == 0 && model.status.contains("Accessibility"))
      model.allowAccess()
      #expect(asked == 1 && emitted == 0)
      trusted = true
      model.configure()
      #expect(backend.starts == 1)
      model.isEnabled = false
    }

    @Test("G13.03 callback delivers once and obsolete delivery cannot emit input")
    func obsoleteCallback() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }

      let backend = CoreMiddleClickBackend()
      let delivery = CoreMiddleDelivery()
      var trusted = false
      var emitted = 0
      var asked = 0
      let model = MiddleClickController(
        defaults: defaults, backend: backend, trusted: { trusted }, requestAccess: { asked += 1 },
        emit: { emitted += 1 }, deliver: { delivery.enqueue($0) })

      trusted = true
      model.start(observeSystem: false)
      model.isEnabled = true
      let callback = try #require(backend.callback)
      callback()
      #expect(delivery.pendingCount == 1)
      delivery.drain()
      #expect(emitted == 1)
      model.isEnabled = false
      callback()
      #expect(delivery.pendingCount == 1)
      delivery.drain()
      #expect(emitted == 1)
      backend.failure = true
      model.isEnabled = true
      #expect(!model.status.contains("ready"))
      model.isEnabled = false
    }

  }
}
