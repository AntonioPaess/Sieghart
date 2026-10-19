import Dispatch
import Foundation
import Speech
import Testing

extension MacContractsTests {
  @Suite(.tags(.callbacks, .isolated)) @MainActor
  struct SpeechAuthorizationTests {
    @Test("G02.01 off-main authorization callbacks preserve all states")
    func offMainCallbacks() async throws {
      for expected in [SFSpeechRecognizerAuthorizationStatus.authorized, .denied, .restricted] {
        let status = await SpeechAuthorizationBridge.request { callback in
          DispatchQueue.global(qos: .userInitiated).async {
            #expect(!Thread.isMainThread)
            callback(expected)
          }
        }
        #expect(status == expected)
      }
    }

  }
}
