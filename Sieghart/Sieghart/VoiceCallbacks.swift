import AVFoundation
import Speech

// The audio tap runs off-main. This wrapper serializes request writes and
// closes the feed before teardown, without transferring UI actor state.
final class SpeechAudioFeed: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let lock = NSLock()
    private var open = true
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if open { request.append(buffer) }
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
