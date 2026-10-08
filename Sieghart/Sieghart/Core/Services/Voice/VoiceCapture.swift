import AVFoundation
import Speech

// Pure session state shared by capture and recognition. Elapsed capture time
// never dispatches a partial command; only a final recognition result can.
struct VoiceCommandSession {
    enum Phase { case idle, listening, finalizing }
    enum Decision: Equatable { case wait, endAudio, noSpeech, inputLost, limitReached, recognitionInterrupted, finalResultTimedOut }
    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private var startedAt = 0.0
    private var lastAudioAt = 0.0
    private var lastActivityAt = 0.0
    private var finalizationAt = 0.0
    private var noiseFloor = -65.0
    private var voicedDuration = 0.0
    private var heardSpeech = false
    private var finalText: String?
    private var finalReceivedAt: Double?
    private var interrupted = false
    let silenceInterval = 1.4
    var hasDetectedSpeech: Bool { heardSpeech }

    mutating func start(at time: Double) {
        self = Self()
        phase = .listening
        startedAt = time; lastAudioAt = time; lastActivityAt = time
    }
    mutating func observe(decibels: Double, duration: Double, at time: Double) {
        guard phase == .listening, decibels.isFinite, duration > 0, time >= lastAudioAt else { return }
        lastAudioAt = time
        let threshold = max(-62, noiseFloor + 10)
        if decibels >= threshold {
            voicedDuration += min(duration, 0.1)
            lastActivityAt = time
            if voicedDuration >= 0.1 { heardSpeech = true }
            if let finalReceivedAt, time > finalReceivedAt + 0.1 { interrupted = true }
        } else {
            voicedDuration = 0
            // Follow quiet room/microphone noise, without learning the voice as
            // background noise or reacting to one transient as a whole phrase.
            noiseFloor = min(-45, noiseFloor * 0.96 + decibels * 0.04)
        }
    }
    mutating func recognize(_ text: String, final: Bool, at time: Double) {
        guard phase != .idle else { return }
        let changed = text != transcript
        transcript = text
        if phase == .listening, changed, !text.isEmpty {
            heardSpeech = true
            lastActivityAt = max(lastActivityAt, time)
        }
        if final { finalText = text; finalReceivedAt = time }
    }
    func decision(at time: Double) -> Decision {
        switch phase {
        case .idle: return .wait
        case .finalizing:
            return time - finalizationAt >= 4 && finalText == nil ? .finalResultTimedOut : .wait
        case .listening:
            if interrupted { return .recognitionInterrupted }
            if time - startedAt >= 55 { return .limitReached }
            if time - lastAudioAt >= 3 { return .inputLost }
            if heardSpeech, time - lastActivityAt >= silenceInterval { return .endAudio }
            if !heardSpeech, time - startedAt >= 12 { return .noSpeech }
            return .wait
        }
    }
    mutating func endAudio(at time: Double) {
        guard phase == .listening else { return }
        phase = .finalizing; finalizationAt = time
    }
    mutating func takeFinalCommand() -> String? {
        guard phase == .finalizing, let finalText, !interrupted else { return nil }
        phase = .idle
        return finalText
    }
    mutating func cancel() { self = Self() }
}

// Bluetooth can renegotiate its microphone format when capture starts. Retry
// once before speech, but never stitch together/truncate a spoken command.
struct VoiceInputRecovery {
    private var attempted = false
    mutating func retry(hasSpeech: Bool) -> Bool {
        guard !hasSpeech, !attempted else { return false }
        attempted = true
        return true
    }
}

struct SpeechAudioLevel: Sendable {
    let decibels: Double
    let duration: Double
    let time: Double
    static func measure(_ buffer: AVAudioPCMBuffer, at time: Double) -> Self? {
        guard buffer.format.sampleRate > 0, buffer.frameLength > 0,
              buffer.format.channelCount > 0 else { return nil }
        let frames = Int(buffer.frameLength), stride = Int(buffer.stride)
        var sum = 0.0
        // The first channel suffices for microphone activity. Respect PCM stride
        // for both interleaved and planar inputs, before the tap reuses its data.
        if let data = buffer.floatChannelData {
            for frame in 0..<frames { let value = Double(data[0][frame * stride]); sum += value * value }
        } else if let data = buffer.int16ChannelData {
            for frame in 0..<frames { let value = Double(data[0][frame * stride]) / 32768; sum += value * value }
        } else if let data = buffer.int32ChannelData {
            for frame in 0..<frames { let value = Double(data[0][frame * stride]) / 2147483648; sum += value * value }
        } else { return nil }
        guard sum.isFinite else { return nil }
        return Self(decibels: max(-100, 10 * log10(max(sum / Double(frames), 1e-10))),
                    duration: Double(frames) / buffer.format.sampleRate, time: time)
    }
}

// The tap runs off-main. Serialize writes and close before teardown; only a
// small Sendable level value crosses to the UI, never an audio buffer.
final class SpeechAudioFeed: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let lock = NSLock()
    private var open = true
    private let onLevel: @Sendable (SpeechAudioLevel) -> Void
    init(_ request: SFSpeechAudioBufferRecognitionRequest, onLevel: @escaping @Sendable (SpeechAudioLevel) -> Void = { _ in }) {
        self.request = request; self.onLevel = onLevel
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard open else { lock.unlock(); return }
        request.append(buffer)
        let level = SpeechAudioLevel.measure(buffer, at: ProcessInfo.processInfo.systemUptime)
        lock.unlock()
        if let level { onLevel(level) }
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        guard open else { return }
        open = false
        request.endAudio()
    }
}

// Speech authorization may call back on a background queue. A Sendable callback
// must not inherit the main actor of the UI that initiated the request.
enum SpeechAuthorizationBridge {
    nonisolated static func request(
        using requester: @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void = { callback in
            SFSpeechRecognizer.requestAuthorization(callback)
        }
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            requester { @Sendable status in continuation.resume(returning: status) }
        }
    }
}
