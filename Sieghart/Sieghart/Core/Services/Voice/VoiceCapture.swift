import AVFoundation
import Speech

// Pure session state shared by capture and recognition. Elapsed capture time
// never dispatches on a capture cutoff. Tools require final recognition; only
// a settled browser search can recover after a bounded finalization drain.
struct VoiceCommandSession {
    enum Phase { case idle, listening, finalizing }
    enum Decision: Equatable { case wait, endAudio, noSpeech, inputLost, limitReached, finalResultTimedOut }
    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private var startedAt = 0.0
    private var lastAudioAt = 0.0
    private var lastActivityAt = 0.0
    private var finalizationAt = 0.0
    private var lastRecognitionAt = 0.0
    private var noiseFloor = -65.0
    private var voicedDuration = 0.0
    private var heardSpeech = false
    private var finalText: String?
    private var speechPeak = -100.0
    private var initialLevels: [Double] = []
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
        // Calibrate the initial room/headset floor even when it is louder
        // than our default. Previously only already-quiet samples could update
        // it, permanently classifying a raised microphone floor as speech.
        if time - startedAt <= 0.3, transcript.isEmpty {
            initialLevels.append(decibels)
            noiseFloor = min(-45, initialLevels.min() ?? decibels)
        }
        // A drop from the spoken envelope also counts as quiet. This handles
        // immediate speech before there was a chance to sample room noise.
        speechPeak -= min(duration, 0.1) * 3
        let threshold = max(-90, noiseFloor + 8, speechPeak - 12)
        if decibels >= threshold {
            speechPeak = max(speechPeak, decibels)
            voicedDuration += min(duration, 0.1)
            if voicedDuration >= 0.1 {
                heardSpeech = true
                lastActivityAt = time
            }
        } else {
            voicedDuration = 0
            noiseFloor = min(-35, noiseFloor * 0.9 + decibels * 0.1)
        }
    }
    mutating func recognize(_ text: String, final: Bool, at time: Double) {
        guard phase != .idle else { return }
        let changed = text != transcript
        transcript = text
        if changed { lastRecognitionAt = time }
        if phase == .listening, changed, !text.isEmpty {
            heardSpeech = true
            lastActivityAt = max(lastActivityAt, time)
        }
        if final { finalText = text }
    }
    func decision(at time: Double) -> Decision {
        switch phase {
        case .idle: return .wait
        case .finalizing:
            guard finalText == nil else { return .wait }
            let waited = time - finalizationAt
            return waited >= 6 || (waited >= 4 && time - lastRecognitionAt >= silenceInterval) ? .finalResultTimedOut : .wait
        case .listening:
            if finalText != nil { return .endAudio }
            if time - startedAt >= 55 { return .limitReached }
            if time - lastAudioAt >= 3 { return .inputLost }
            if transcript.isEmpty, time - startedAt >= 12 { return .noSpeech }
            if heardSpeech, time - lastActivityAt >= silenceInterval { return .endAudio }
            return .wait
        }
    }
    mutating func endAudio(at time: Double) {
        guard phase == .listening else { return }
        phase = .finalizing; finalizationAt = time
    }
    mutating func takeFinalCommand() -> String? {
        guard phase == .finalizing, let finalText else { return nil }
        phase = .idle
        return finalText
    }
    // Search alone can use settled text after an audio-confirmed end and a
    // bounded recognizer drain. The caller must reject app/timer/tool actions.
    // Some recognition tasks stop without delivering an isFinal callback.
    mutating func takeSettledSearchText(at time: Double) -> String? {
        guard phase == .finalizing, finalText == nil, !transcript.isEmpty,
              decision(at: time) == .finalResultTimedOut,
              time - lastRecognitionAt >= silenceInterval else { return nil }
        phase = .idle
        return transcript
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

// Native capture is replaceable at the framework boundary. Integration checks
// drive the same controller/session/action path without touching a microphone.
enum VoiceCaptureEvent: Sendable {
    case level(SpeechAudioLevel)
    case recognition(text: String, final: Bool)
    case inputChanged
    case failure(String)
}

@MainActor protocol VoiceCapturing: AnyObject {
    func prepareAccess() async throws
    func start(language: String, receive: @escaping @MainActor (VoiceCaptureEvent) -> Void) throws
    func finish()
    func cancel()
}

enum VoiceCaptureFailure: LocalizedError {
    case speechAccess, microphoneAccess, unavailable, inputUnavailable
    var errorDescription: String? {
        switch self {
        case .speechAccess: "Allow speech recognition in System Settings"
        case .microphoneAccess: "Allow microphone access in System Settings"
        case .unavailable: "Speech recognition is unavailable"
        case .inputUnavailable: "No microphone input is available"
        }
    }
    var permitsInputRetry: Bool { if case .inputUnavailable = self { return true }; return false }
}

// Closing request audio alone is insufficient for every buffer-based recognizer.
// Apple's task.finish() drains accepted audio; task.cancel() discards the task.
// Keep these operations separate, and make the drain sequence checkable.
@MainActor struct SpeechRecognitionDrain {
    private var finished = false
    mutating func finish(endAudio: () -> Void, finishTask: () -> Void) {
        guard !finished else { return }
        finished = true
        endAudio()
        finishTask()
    }
}

@MainActor final class NativeVoiceCapture: VoiceCapturing {
    private var engine: AVAudioEngine?
    private var engineObserver: NSObjectProtocol?
    private var feed: SpeechAudioFeed?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var generation = 0
    private var drain = SpeechRecognitionDrain()

    func prepareAccess() async throws {
        guard await SpeechAuthorizationBridge.request() == .authorized else { throw VoiceCaptureFailure.speechAccess }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw VoiceCaptureFailure.microphoneAccess }
    }

    func start(language: String, receive: @escaping @MainActor (VoiceCaptureEvent) -> Void) throws {
        cancel()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else { throw VoiceCaptureFailure.unavailable }
        let token = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let hardware = input.inputFormat(forBus: 0), format = input.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0, format.sampleRate > 0, format.channelCount > 0 else {
            cancel(); throw VoiceCaptureFailure.inputUnavailable
        }
        let feed = SpeechAudioFeed(request) { @Sendable [weak self] level in
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                receive(.level(level))
            }
        }
        self.feed = feed
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in feed.append(buffer) }
        hasTap = true
        engineObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                receive(.inputChanged)
            }
        }
        do { engine.prepare(); try engine.start() }
        catch { cancel(); throw error }
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                if let text { receive(.recognition(text: text, final: final)) }
                // A final result is complete, even if the framework reports a
                // teardown error in the same callback. Never replace success.
                if !final, let message { receive(.failure(message)) }
            }
        }
    }

    private func stopInput() {
        if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
        engineObserver = nil
        engine?.stop()
        if hasTap { engine?.inputNode.removeTap(onBus: 0); hasTap = false }
    }

    func finish() {
        stopInput()
        drain.finish(endAudio: { feed?.finish() }, finishTask: { task?.finish() })
        feed = nil
    }

    func cancel() {
        generation += 1
        stopInput()
        feed?.finish(); feed = nil
        task?.cancel(); task = nil
        engine = nil
        drain = SpeechRecognitionDrain()
    }
}
