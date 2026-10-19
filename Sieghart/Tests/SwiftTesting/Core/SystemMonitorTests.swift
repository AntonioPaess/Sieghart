import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.utilities, .isolated)) @MainActor
  struct SystemMonitorTests {
    @Test("G14.02 construction does not sample and history retains 60 readings")
    func monitorHistory() throws {
      var first = MonitorReading()
      first.sampledAt = Date(timeIntervalSince1970: 1_800_000_000)
      first.counters = SystemCounters(
        time: 10, cpu: [10, 10, 80, 0], received: 1000, sent: 500, diskRead: 500, diskWritten: 100,
        diskIOAvailable: true)
      var second = first
      second.counters = SystemCounters(
        time: 12, cpu: [20, 20, 160, 0], received: 1600, sent: 700, diskRead: 1100,
        diskWritten: 300, diskIOAvailable: true)
      second.derive(from: first.counters)

      var unavailable = first
      unavailable.counters.diskIOAvailable = false
      unavailable.derive(from: first.counters)

      let sampler = CoreSampleMonitor()
      sampler.samples = [first, second]
      let monitor = SystemMonitorViewModel(backend: sampler)
      #expect(sampler.calls == 0, "Constructing a model must not sample the Mac")
      for _ in 0..<75 { monitor.refresh() }
      #expect(monitor.history.count == 60)
    }

  }
}
