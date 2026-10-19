import CoreAudio
import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.audio, .logic))
  struct AudioPCMTests {
    @Test("G10.07 bounded PCM conversion, mute, microphone offset and channel folding")
    func pcmLayouts() throws {
      let stereo = CoreBuffers([[1, -1, 0.5, -0.5, 0.2, -0.2]], channels: [2])
      let planar = CoreBuffers([[9, 9], [9, 9]], channels: [1, 1])
      AudioPCM.render(
        input: stereo.list.unsafePointer, output: planar.list.unsafeMutablePointer, gain: 0.5)
      #expect(
        planar.values(0, count: 2) == [0.5, 0.25] && planar.values(1, count: 2) == [-0.5, -0.25],
        "Interleaved to planar, bounded by shorter output")
      let interleaved = CoreBuffers([[9, 9, 9, 9, 9, 9]], channels: [2])
      AudioPCM.render(
        input: planar.list.unsafePointer, output: interleaved.list.unsafeMutablePointer, gain: 1)
      #expect(
        interleaved.values(0, count: 6) == [0.5, -0.5, 0.25, -0.25, 0, 0],
        "Planar to interleaved; unused frames must be cleared")
      AudioPCM.render(
        input: stereo.list.unsafePointer, output: interleaved.list.unsafeMutablePointer, gain: 0)
      #expect(
        interleaved.values(0, count: 6) == [0, 0, 0, 0, 0, 0], "Mute clears every output sample")
      let combined = CoreBuffers([[0.99, 0.99], [0.6, -0.6, 0.2, -0.2]], channels: [1, 2])
      AudioPCM.render(
        input: combined.list.unsafePointer, output: interleaved.list.unsafeMutablePointer,
        gain: 0.5, sourceBufferOffset: 1)
      #expect(
        interleaved.values(0, count: 6) == [0.3, -0.3, 0.1, -0.1, 0, 0],
        "Hardware microphone buffers must never be mixed into app playback")
      let callStereo = CoreBuffers([[0.8, 0.4, -0.6, -0.2]], channels: [2])
      let mono = CoreBuffers([[9, 9]], channels: [1])
      AudioPCM.render(
        input: callStereo.list.unsafePointer, output: mono.list.unsafeMutablePointer, gain: 0.5)
      #expect(
        abs(mono.values(0, count: 2)[0] - 0.3) < 0.0001
          && abs(mono.values(0, count: 2)[1] + 0.2) < 0.0001,
        "A Bluetooth call folds stereo channels without changing playback speed")
      let monoSource = CoreBuffers([[0.4, -0.4]], channels: [1])
      AudioPCM.render(
        input: monoSource.list.unsafePointer, output: planar.list.unsafeMutablePointer, gain: 1)
      #expect(
        planar.values(0, count: 2) == [0.4, -0.4] && planar.values(1, count: 2) == [0.4, -0.4])
    }

  }
}
