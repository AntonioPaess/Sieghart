import CoreAudio
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.audio, .isolated)) @MainActor
  struct AudioDevicePreferenceTests {
    @Test("G10.04 automatic opt-in, manual choice, UID reconnect and safe restoration")
    func devicePreference() async throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let backend = CoreMockAudio()
      let audio = AudioViewModel(backend: backend, defaults: defaults)
      defer { audio.shutdown() }
      audio.refresh()
      let app = try #require(audio.state.apps.first)
      await audio.enableApplications()
      audio.setGain(1, app: app)
      backend.reading.apps = (0..<2).map {
        AudioApplicationInfo(
          id: "app.\($0)", name: "App \($0)", processes: [UInt32($0 + 10)], pid: pid_t($0 + 100))
      }
      audio.refresh()
      audio.disableApplications()
      let orderedApps = audio.state.apps
      try #require(orderedApps.count == 2)
      audio.toggleFavorite(orderedApps[0])
      audio.toggleFavorite(orderedApps[1])
      let headphones = backend.reading.devices[2]
      audio.preferDevice(headphones, input: false)
      let beforePriority = backend.reading.output
      audio.refresh()
      #expect(
        backend.reading.output == beforePriority, "Saved priority is not automatic authorization")
      audio.automaticDevices = true
      #expect(backend.reading.output == headphones.id)
      audio.selectDevice(1)
      audio.refresh()
      #expect(audio.state.output == 1, "Keep a manual choice until topology changes")
      backend.reading.devices.removeLast()
      audio.refresh()
      let reconnected = AudioDeviceInfo(
        id: 42, name: headphones.name, uid: headphones.uid, inputChannels: headphones.inputChannels,
        outputChannels: headphones.outputChannels)
      backend.reading.devices.append(reconnected)
      audio.refresh()
      #expect(
        audio.state.output == 42, "Reconnect resolves the same UID even with a different object ID")
      audio.cycleOutput()
      #expect(audio.state.output == 1)
      let mutedBefore = try #require(audio.state.inputMuted)
      audio.toggleMicrophoneMute()
      #expect(audio.state.inputMuted == !mutedBefore)
      backend.reading.inputMuted = nil
      audio.toggleMicrophoneMute()
      #expect(audio.error != nil)
      audio.shutdown()
      let restored = AudioViewModel(backend: CoreMockAudio(), defaults: defaults)
      #expect(
        restored.gains[app.id] == 1 && !restored.perAppEnabled && restored.favoriteApps.count == 2
          && restored.outputPriority == [headphones.uid],
        "Saved gain must not authorize a new capture session")
    }

  }
}
