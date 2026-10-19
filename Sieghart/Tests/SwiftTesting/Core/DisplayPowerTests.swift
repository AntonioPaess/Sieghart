import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.utilities, .isolated)) @MainActor
  struct DisplayPowerTests {
    @Test("G14.05 clamps, dim floor, error and opt-in owned Bluetooth restoration")
    func displayOwnership() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let adapter = CoreSampleDisplay()
      let display = DisplayPowerViewModel(backend: adapter, defaults: defaults)
      #expect(adapter.brightnessWrites.isEmpty && adapter.sleeps == 0)
      display.refresh()
      display.setBrightness(2, display: adapter.fixture[0])
      display.setDimming(0, display: adapter.fixture[0])
      #expect(adapter.brightnessWrites == [1] && adapter.dimWrites == [0.2])
      adapter.fails = true
      display.setBrightness(0.4, display: adapter.fixture[0])
      #expect(display.error != nil && adapter.brightnessWrites == [1])
      display.willSleep()
      display.didWake()
      #expect(
        adapter.disconnected.isEmpty && adapter.reconnected.isEmpty, "Bluetooth sleep is opt-in")
      display.disconnectBluetoothOnSleep = true
      display.willSleep()
      display.didWake()
      display.didWake()
      #expect(
        adapter.disconnected == ["A"] && adapter.reconnected == ["A"],
        "Restore only successfully disconnected devices, once")
      display.sleepDisplays()
      display.restoreBrightness()
      #expect(adapter.sleeps == 1 && adapter.restoreCount > 0)
      display.shutdown()
    }

  }
}
