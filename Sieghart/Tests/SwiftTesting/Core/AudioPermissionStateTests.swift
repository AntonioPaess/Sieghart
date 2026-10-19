import CoreAudio
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.audio, .isolated)) @MainActor
  struct AudioPermissionStateTests {
    @Test("G10.05 denial, retry and obsolete authorization never activate capture")
    func permissionGeneration() async throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let deniedBackend = CoreMockAudio()
      deniedBackend.permissionFailure = kAudioDevicePermissionsError
      let denied = AudioViewModel(backend: deniedBackend, defaults: defaults)
      await denied.enableApplications()
      #expect(
        !denied.perAppEnabled && denied.access == .permissionRequired && deniedBackend.calls == 0,
        "No saved mix before the real permission request succeeds")
      deniedBackend.permissionFailure = nil
      await denied.enableApplications()
      #expect(denied.perAppEnabled && deniedBackend.permissionRequests == 2)
      let delayedBackend = CoreMockAudio()
      delayedBackend.holdsRequest = true
      let delayed = AudioViewModel(backend: delayedBackend, defaults: defaults)
      let signal = AsyncStream<Void>.makeStream()
      delayedBackend.permissionStarted = { signal.continuation.yield(()) }
      let request = Task { await delayed.enableApplications() }
      var iterator = signal.stream.makeAsyncIterator()
      _ = await iterator.next()
      #expect(delayed.access == .requesting && !delayed.perAppEnabled)
      delayed.disableApplications()
      delayedBackend.pending?.resume()
      await request.value
      signal.continuation.finish()
      denied.shutdown()
      delayed.shutdown()
      #expect(
        delayed.access == .off && !delayed.perAppEnabled && delayedBackend.calls == 0,
        "An obsolete permission request must not enable capture")
    }

  }
}
