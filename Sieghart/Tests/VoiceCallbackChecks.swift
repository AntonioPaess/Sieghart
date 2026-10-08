import AVFoundation
import Dispatch
import Speech

@main
struct VoiceCallbackChecks {
    @MainActor static func main() async {
        // Exercise the actual bridge used by voice startup from an off-main
        // framework callback. No permission request or microphone capture runs.
        for expected in [SFSpeechRecognizerAuthorizationStatus.authorized, .denied, .restricted] {
            let status = await SpeechAuthorizationBridge.request { callback in
                DispatchQueue.global(qos: .userInitiated).async {
                    precondition(!Thread.isMainThread)
                    callback(expected)
                }
            }
            precondition(status == expected)
        }
        var session = VoiceCommandSession()
        // Regression: headset/room noise remains audible after the phrase.
        // The old floor never learned this noise and listened indefinitely.
        session.start(at: 0)
        for tick in 1...10 { session.observe(decibels: -42, duration: 0.1, at: Double(tick) / 10) }
        session.recognize("Pesquise por ChatGPT no Google", final: false, at: 1)
        for tick in 11...25 { session.observe(decibels: -20, duration: 0.1, at: Double(tick) / 10) }
        for tick in 26...41 { session.observe(decibels: -42, duration: 0.1, at: Double(tick) / 10) }
        precondition(session.decision(at: 4.1) == .endAudio, "Trailing microphone noise must not keep listening forever")

        session.start(at: 0)
        session.recognize("Pesquise por ChatGPT no Google", final: true, at: 1)
        precondition(session.decision(at: 1) == .endAudio, "An authoritative final result must finish capture")

        session.start(at: 0)
        session.recognize("pesquisa no Google", final: false, at: 0.1)
        // Speech continues for forty seconds, even when the transcript stalls.
        for tick in 1...400 {
            let time = Double(tick) / 10
            session.observe(decibels: -26, duration: 0.1, at: time)
            precondition(session.decision(at: time) == .wait)
        }
        for tick in 401...413 {
            let time = Double(tick) / 10
            session.observe(decibels: -72, duration: 0.1, at: time)
            precondition(session.decision(at: time) == .wait)
        }
        session.observe(decibels: -72, duration: 0.1, at: 41.5)
        precondition(session.decision(at: 41.5) == .endAudio)
        session.endAudio(at: 41.5)
        precondition(session.takeFinalCommand() == nil) // No partial dispatch.
        session.recognize("pesquisa no Google sobre animações fluidas", final: true, at: 42)
        precondition(session.takeFinalCommand() == "pesquisa no Google sobre animações fluidas")
        precondition(session.takeFinalCommand() == nil) // Exactly once.

        // A short thinking/breath pause is followed by more speech.
        session.start(at: 0)
        for tick in 1...10 { session.observe(decibels: -42, duration: 0.1, at: Double(tick) / 10) }
        for tick in 11...20 { session.observe(decibels: -80, duration: 0.1, at: Double(tick) / 10) }
        precondition(session.decision(at: 2) == .wait)
        session.observe(decibels: -42, duration: 0.1, at: 2.1)
        precondition(session.decision(at: 2.3) == .wait)
        session.cancel()
        session.recognize("open Safari", final: true, at: 3)
        precondition(session.takeFinalCommand() == nil)
        session.start(at: 4)
        precondition(session.transcript.isEmpty)
        precondition(session.decision(at: 7.1) == .inputLost)

        session.start(at: 0)
        for tick in 1...120 { session.observe(decibels: -65, duration: 0.1, at: Double(tick) / 10) }
        precondition(session.decision(at: 12) == .noSpeech)
        session.start(at: 0)
        for tick in 1...550 { session.observe(decibels: -25, duration: 0.1, at: Double(tick) / 10) }
        precondition(session.decision(at: 55) == .limitReached)
        precondition(session.takeFinalCommand() == nil)
        session.endAudio(at: 55)
        precondition(session.decision(at: 59.1) == .finalResultTimedOut)

        session.start(at: 0)
        session.recognize("open", final: true, at: 0.1)
        session.observe(decibels: -25, duration: 0.1, at: 0.4)
        precondition(session.decision(at: 0.4) == .endAudio)
        session.endAudio(at: 0.4)
        precondition(session.takeFinalCommand() == "open")
        precondition(session.takeFinalCommand() == nil)

        var drain = SpeechRecognitionDrain()
        var drainCalls: [String] = []
        drain.finish(endAudio: { drainCalls.append("endAudio") }, finishTask: { drainCalls.append("task.finish") })
        drain.finish(endAudio: { drainCalls.append("duplicate endAudio") }, finishTask: { drainCalls.append("duplicate finish") })
        precondition(drainCalls == ["endAudio", "task.finish"], "Drain must close the request and finish the recognizer, in order, once")

        session.start(at: 0)
        for tick in 1...20 { session.observe(decibels: -80, duration: 0.1, at: Double(tick) / 10) }
        session.recognize("voz baixa", final: false, at: 2)
        for tick in 21...150 { session.observe(decibels: -58, duration: 0.1, at: Double(tick) / 10) }
        precondition(session.decision(at: 15) == .wait)

        var recovery = VoiceInputRecovery()
        precondition(recovery.retry(hasSpeech: false))
        precondition(!recovery.retry(hasSpeech: false))
        recovery = VoiceInputRecovery()
        precondition(!recovery.retry(hasSpeech: true))

        // Bluetooth microphone layouts/rates, synthetic samples only.
        for rate in [16_000.0, 24_000, 48_000] {
            for interleaved in [false, true] {
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: interleaved)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
                buffer.frameLength = 1_024
                for channel in 0..<2 {
                    for frame in 0..<1_024 { buffer.floatChannelData![channel][frame * Int(buffer.stride)] = channel == 0 ? 0.1 : 0.8 }
                }
                let level = SpeechAudioLevel.measure(buffer, at: 1)!
                precondition(abs(level.decibels + 20) < 0.01)
                precondition(abs(level.duration - 1_024 / rate) < 0.0001)
                buffer.frameLength = 0
                precondition(SpeechAudioLevel.measure(buffer, at: 1) == nil)
            }
        }
        for commonFormat in [AVAudioCommonFormat.pcmFormatInt16, .pcmFormatInt32] {
            let format = AVAudioFormat(commonFormat: commonFormat, sampleRate: 24_000, channels: 1, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
            buffer.frameLength = 256
            if commonFormat == .pcmFormatInt16 {
                for frame in 0..<256 { buffer.int16ChannelData![0][frame] = 8_192 }
            } else {
                for frame in 0..<256 { buffer.int32ChannelData![0][frame] = 536_870_912 }
            }
            precondition(abs(SpeechAudioLevel.measure(buffer, at: 1)!.decibels + 12.0412) < 0.001)
        }
        print("PASS: off-main authorization; audio pause endpoint; >10s speech; final-word drain; cancellation/timeouts; headset PCM layouts")
    }
}
