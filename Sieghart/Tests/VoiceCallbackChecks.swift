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
        print("PASS: speech authorization resumes safely from a background queue")
    }
}
