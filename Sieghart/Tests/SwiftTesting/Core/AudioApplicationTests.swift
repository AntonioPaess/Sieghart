import CoreAudio
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.audio, .isolated)) @MainActor
  struct AudioApplicationTests {
    @Test(
      "G10.06 Finder exclusion, current helpers and persistent hide/restore release owned routes")
    func applications() async throws {
      let fixture = try TestDefaults()
      let mixerDefaults = fixture.value
      defer { fixture.cleanup() }
      let browserBackend = CoreMockAudio()
      let mixer = AudioViewModel(backend: browserBackend, defaults: mixerDefaults)
      let safari = AudioApplicationInfo(
        id: "com.apple.Safari", name: "Safari", processes: [501], pid: 12)
      let finder = AudioApplicationInfo(
        id: "com.apple.finder", name: "Finder", processes: [900], pid: 19)
      browserBackend.reading.apps =
        [finder, safari]
        + (0..<5).map {
          AudioApplicationInfo(
            id: "player.\($0)", name: "Player \($0)", processes: [UInt32(600 + $0)],
            pid: pid_t(100 + $0))
        }
      mixer.refresh()
      #expect(mixer.visibleApps.count == 5 && !mixer.visibleApps.contains { $0.id == finder.id })
      await mixer.enableApplications()
      mixer.setGain(0.3, app: safari)
      let other = browserBackend.reading.apps[2]
      mixer.setGain(0.6, app: other)
      let newSafari = AudioApplicationInfo(
        id: safari.id, name: safari.name, processes: [502, 503], pid: 12)
      browserBackend.reading.apps[1] = newSafari
      mixer.setGain(0.2, app: safari)  // The view still holds the old process group.
      #expect(
        browserBackend.appliedProcesses[safari.id] == [502, 503]
          && browserBackend.routes[safari.id] == 0.2,
        "A slider change must tap the current browser helpers, even before the next poll")
      mixer.toggleFavorite(safari)
      mixer.hideApp(safari)
      #expect(mixer.hiddenApps == [HiddenAudioApplication(id: safari.id, name: safari.name)])
      #expect(
        mixer.visibleApps.count == 5 && !mixer.visibleApps.contains { $0.id == safari.id },
        "Hiding refills the five-app cap from real eligible apps")
      #expect(browserBackend.routes[safari.id] == nil && browserBackend.routes[other.id] == 0.6)
      #expect(
        !mixer.routedApps.contains(safari.id) && mixer.gains[safari.id] == 0.2,
        "Hide releases only that app's audio route and retains its saved choice")
      let hiddenCalls = browserBackend.calls
      mixer.setGain(0, app: safari)
      #expect(
        browserBackend.calls == hiddenCalls,
        "A removed row's stale callback cannot retap a hidden app")
      mixer.refresh()
      #expect(
        browserBackend.routes[safari.id] == nil
          && !mixer.visibleApps.contains { $0.id == safari.id })
      let reopened = AudioViewModel(backend: browserBackend, defaults: mixerDefaults)
      reopened.refresh()
      #expect(reopened.hiddenApps == mixer.hiddenApps && !reopened.perAppEnabled)
      #expect(!reopened.visibleApps.contains { $0.id == safari.id })
      mixer.restoreApp(safari.id)
      #expect(mixer.hiddenApps.isEmpty && mixer.visibleApps.first?.id == safari.id)
      #expect(
        browserBackend.routes[safari.id] == 0.2
          && browserBackend.appliedProcesses[safari.id] == [502, 503])
      mixer.hideApp(safari)
      browserBackend.reading.apps.removeAll { $0.id == safari.id }
      mixer.restoreApp(safari.id)
      #expect(
        !mixer.visibleApps.contains { $0.id == safari.id }
          && browserBackend.routes[safari.id] == nil,
        "Restoring a closed app never fabricates a tower")
      let staleCalls = browserBackend.calls
      mixer.setGain(0.1, app: safari)
      #expect(
        browserBackend.calls == staleCalls, "A closed browser's stale slider cannot receive a tap")
      mixer.setGain(0.2, app: finder)
      #expect(
        browserBackend.calls == staleCalls && !mixer.visibleApps.contains { $0.id == finder.id })
      mixer.shutdown()
    }

  }
}
