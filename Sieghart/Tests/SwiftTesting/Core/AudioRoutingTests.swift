import CoreAudio
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.audio, .isolated)) @MainActor
  struct AudioRoutingTests {
    @Test("G10.02 opt-in capture, gain clamps, failures and device replacement")
    func routeOwnership() async throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let backend = CoreMockAudio()
      let audio = AudioViewModel(backend: backend, defaults: defaults)
      defer { audio.shutdown() }
      #expect(backend.calls == 0 && !audio.perAppEnabled)
      audio.refresh()
      let app = try #require(audio.state.apps.first)
      audio.setGain(0.4, app: app)
      #expect(backend.calls == 0, "No app capture before explicit enable")
      await audio.enableApplications()
      #expect(backend.calls == 0 && backend.permissionRequests == 1 && audio.access == .ready)
      let waiting = AudioApplicationInfo(
        id: "waiting", name: "Waiting app", processes: [], pid: 100, isPlaying: false)
      let beforeWaiting = backend.calls
      audio.setGain(0.4, app: waiting)
      #expect(
        backend.calls == beforeWaiting && audio.gains[waiting.id] == nil,
        "An open app without an audio connection must never claim an effective mix")
      audio.setGain(0.4, app: app)
      #expect(audio.routedApps == [app.id] && backend.routes[app.id] == 0.4)
      audio.setGain(0, app: app)
      #expect(backend.routes[app.id] == 0)
      audio.setGain(4, app: app)
      #expect(backend.routes[app.id] == 1)
      audio.setVolume(-1)
      audio.setVolume(2, input: true)
      audio.muteInput(true)
      #expect(
        audio.state.outputVolume == 0 && audio.state.inputVolume == 1
          && audio.state.inputMuted == true)
      backend.fail = true
      audio.setGain(0.2, app: app)
      #expect(
        audio.gains[app.id] == 1 && audio.error != nil && audio.routedApps.contains(app.id),
        "A failed replacement retains its last applied gain")
      audio.selectDevice(3)
      #expect(audio.state.output == 1 && audio.error != nil && backend.routes.isEmpty)
      let calls = backend.calls
      audio.refresh()
      #expect(backend.calls == calls, "Failed saved routes aren't repeatedly retried")
      backend.fail = false
      audio.selectDevice(3)
      #expect(audio.state.output == 3 && backend.routes[app.id] == 1)
    }

    @Test("G10.03 format changes, disappearance, five-app cap and favorite ordering")
    func routeTopology() async throws {
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
      audio.selectDevice(3)
      backend.reading.output = 1
      let stopped = backend.stopped
      audio.refresh()
      #expect(backend.stopped > stopped)
      let oldStops = backend.stopped
      backend.reading.devices[0].sampleRate = 16000
      audio.refresh()
      #expect(
        backend.stopped > oldStops,
        "An AirPods format change rebuilds routes even with the same device ID")
      backend.reading.apps = []
      audio.refresh()
      #expect(backend.routes.isEmpty && audio.routedApps.isEmpty)
      backend.reading.apps = (0..<8).map {
        AudioApplicationInfo(
          id: "app.\($0)", name: "App \($0)", processes: [UInt32($0 + 10)], pid: pid_t($0 + 100))
      }
      audio.refresh()
      #expect(
        audio.visibleApps.count == 5
          && audio.visibleApps.map(\.id) == ["app.0", "app.1", "app.2", "app.3", "app.4"])
      backend.reading.apps = Array(backend.reading.apps.prefix(2))
      audio.refresh()
      #expect(
        audio.visibleApps.count == 2, "The mixer never fills missing apps with placeholder columns")
      audio.disableApplications()
      #expect(!audio.perAppEnabled && backend.routes.isEmpty)
      let orderedApps = audio.state.apps
      try #require(orderedApps.count >= 2)
      audio.toggleFavorite(orderedApps[1])
      #expect(audio.visibleApps.first?.id == orderedApps[1].id)
      audio.toggleFavorite(orderedApps[0])
      audio.moveApp(orderedApps[1], direction: -1)
      #expect(
        audio.favoriteApps.count == 2 && audio.visibleApps.first?.id == orderedApps[1].id,
        "Ordering favorites preserves favorite status")
      backend.reading.apps = []
      audio.refresh()
      #expect(audio.visibleApps.isEmpty, "Closed favorites must not fabricate towers")
    }

  }
}
