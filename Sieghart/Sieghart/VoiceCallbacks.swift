import Speech

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
