import CoreAudio
import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.audio, .logic))
  struct AudioIdentityTests {
    @Test("G10.01 responsible PID, ancestry fallback and device identity")
    func ownership() throws {
      let parents: [pid_t: pid_t] = [77: 50, 50: 12, 90: 91, 91: 90]
      #expect(
        AudioAppIdentity.ancestor(of: 77, isApplication: { $0 == 12 }, parent: { parents[$0] ?? 0 })
          == 12, "Audio helpers must resolve to the visible app")
      #expect(
        AudioAppIdentity.ancestor(
          of: 90, isApplication: { _ in false }, parent: { parents[$0] ?? 0 }) == nil,
        "Cycles and daemons must not become mixer apps")
      let regular: Set<pid_t> = [12, 19]
      let responsible: [pid_t: pid_t] = [77: 12, 78: 19, 88: 50]
      func resolve(_ pid: pid_t, lookup: ((pid_t) -> pid_t?)? = nil) -> pid_t? {
        let resolver = lookup ?? { responsible[$0] }
        return AudioAppIdentity.applicationPID(
          of: pid, isApplication: regular.contains,
          parent: { [50: 12, 79: 50][$0] ?? 1 }, responsible: resolver)
      }
      #expect(
        resolve(77) == 12 && resolve(78) == 19,
        "Shared WebKit XPC helpers must belong to their actual host, not all to Safari")
      #expect(
        resolve(88) == 12, "Responsibility may point to another helper, so follow its ancestry")
      #expect(
        resolve(79, lookup: { _ in nil }) == 12, "Missing SPI retains public ancestry fallback")
      #expect(
        resolve(79, lookup: { $0 }) == 12, "Self-responsible helpers still follow their parents")
      #expect(
        resolve(80, lookup: { _ in -1 }) == nil && resolve(81, lookup: { _ in 999 }) == nil,
        "Unknown ownership must not borrow another browser's audio")
      #expect(resolve(12, lookup: { _ in 19 }) == 12 && resolve(1) == nil)
      #expect(
        AudioDeviceInfo(
          id: 1, name: "AirPods Pro", uid: "fixture", inputChannels: 1, outputChannels: 2,
          transport: kAudioDeviceTransportTypeBluetooth
        ).symbol == "airpodspro")
      #expect(
        AudioDeviceInfo(
          id: 1, name: "Wireless headphones", uid: "fixture", inputChannels: 0, outputChannels: 2,
          transport: kAudioDeviceTransportTypeBluetooth
        ).symbol == "headphones")
    }

  }
}
