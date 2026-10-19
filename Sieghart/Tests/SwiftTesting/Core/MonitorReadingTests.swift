import AppKit
import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.utilities, .logic))
  struct MonitorReadingTests {
    @Test("G14.01 CPU, network, disk, reset and absent readings")
    func counterDeltas() throws {
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
      #expect(
        second.cpu == 0.2 && second.download == 300 && second.upload == 100
          && second.diskReadRate == 300 && second.diskWriteRate == 100)
      #expect(
        MonitorReading.rate(10, previous: 20, seconds: 2) == nil,
        "Resetting a counter must not overflow")
      #expect(MonitorReading.rate(30, previous: 20, seconds: 0) == nil)
      var unavailable = first
      unavailable.counters.diskIOAvailable = false
      unavailable.derive(from: first.counters)
      #expect(
        unavailable.diskReadRate == nil && unavailable.gpu == nil,
        "Missing hardware readings aren't fabricated")
    }

  }
}
