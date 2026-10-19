import AVFoundation
import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.callbacks, .logic))
  struct SpeechPCMTests {
    @Test(
      "G02.07 Float32 PCM layouts and rates preserve channel, level and duration",
      arguments: [16_000.0, 24_000, 48_000], [false, true])
    func floatPCM(rate: Double, interleaved: Bool) throws {
      let format = try #require(
        AVAudioFormat(
          commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: interleaved))
      let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
      buffer.frameLength = 1_024
      let channels = try #require(buffer.floatChannelData)
      for channel in 0..<2 {
        for frame in 0..<1_024 {
          channels[channel][frame * Int(buffer.stride)] = channel == 0 ? 0.1 : 0.8
        }
      }
      let level = try #require(SpeechAudioLevel.measure(buffer, at: 1))
      #expect(abs(level.decibels + 20) < 0.01)
      #expect(abs(level.duration - 1_024 / rate) < 0.0001)
      buffer.frameLength = 0
      #expect(SpeechAudioLevel.measure(buffer, at: 1) == nil)
    }

    @Test(
      "G02.07 integer PCM formats preserve decibels",
      arguments: [AVAudioCommonFormat.pcmFormatInt16, .pcmFormatInt32])
    func integerPCM(commonFormat: AVAudioCommonFormat) throws {
      let format = try #require(
        AVAudioFormat(
          commonFormat: commonFormat, sampleRate: 24_000, channels: 1, interleaved: false))
      let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
      buffer.frameLength = 256
      if commonFormat == .pcmFormatInt16 {
        let channels = try #require(buffer.int16ChannelData)
        for frame in 0..<256 { channels[0][frame] = 8_192 }
      } else {
        let channels = try #require(buffer.int32ChannelData)
        for frame in 0..<256 { channels[0][frame] = 536_870_912 }
      }
      let level = try #require(SpeechAudioLevel.measure(buffer, at: 1))
      #expect(abs(level.decibels + 12.0412) < 0.001)
      #expect(abs(level.duration - 256 / 24_000.0) < 0.0001)
    }
  }
}
