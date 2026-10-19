import AppKit
import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.utilities, .logic))
  @MainActor struct PlaybackGateTests {
    @Test("G14.05 only enabled launches shortly after playback are blocked")
    func musicGate() throws {
      #expect(DisplayPowerViewModel.shouldBlockMusic(enabled: true, launch: 12, lastPlayKey: 11))
      #expect(!DisplayPowerViewModel.shouldBlockMusic(enabled: true, launch: 15, lastPlayKey: 11))
      #expect(!DisplayPowerViewModel.shouldBlockMusic(enabled: false, launch: 12, lastPlayKey: 11))
      #expect(!DisplayPowerViewModel.shouldBlockMusic(enabled: true, launch: 10, lastPlayKey: 11))
    }

  }
}
