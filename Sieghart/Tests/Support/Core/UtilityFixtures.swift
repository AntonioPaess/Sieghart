import AppKit
import Foundation

@MainActor final class CoreSampleMonitor: SystemSampling {
  var samples: [MonitorReading] = []
  var calls = 0
  func read() -> MonitorReading {
    defer { calls += 1 }
    return samples[min(calls, samples.count - 1)]
  }
}
@MainActor final class CoreSampleAwake: AwakeBackend {
  var current = AwakeContext()
  var acquired: [Bool] = []
  var released: [UInt32] = []
  var fails = false
  func context() -> AwakeContext { current }
  func acquire(display: Bool) throws -> UInt32 {
    if fails { throw UtilityFailure(message: "Fixture refused") }
    acquired.append(display)
    return UInt32(acquired.count)
  }
  func release(_ token: UInt32) { released.append(token) }
}
@MainActor final class CoreSampleDisplay: DisplayPowerBackend {
  var fixture = [
    DisplayInfo(id: 42, name: "Fixture display", builtIn: true, brightness: 0.7, hdrHeadroom: 2)
  ]
  var brightnessWrites: [Double] = []
  var dimWrites: [Double] = []
  var restoreCount = 0
  var sleeps = 0
  var connected = ["A", "B"]
  var disconnected: [String] = []
  var reconnected: [String] = []
  var fails = false
  func displays() -> [DisplayInfo] { fixture }
  func brightness(_ value: Double, display: CGDirectDisplayID) throws {
    if fails { throw UtilityFailure(message: "Unsupported fixture") }
    brightnessWrites.append(value)
    fixture[0].brightness = value
  }
  func dim(_ value: Double, display: CGDirectDisplayID) throws {
    dimWrites.append(value)
    fixture[0].dimming = value
  }
  func restore() { restoreCount += 1 }
  func sleepDisplays() throws { sleeps += 1 }
  func connectedBluetooth() -> [String] { connected }
  func disconnectBluetooth(_ id: String) throws {
    if id == "B" { throw UtilityFailure(message: "B couldn't disconnect") }
    disconnected.append(id)
  }
  func reconnectBluetooth(_ id: String) throws { reconnected.append(id) }
}
