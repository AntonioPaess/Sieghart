import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.activity, .isolated)) @MainActor
  struct OnboardingPreferenceTests {
    @Test("G08.07 first run has six characters and legacy avatar restores Sig")
    func onboarding() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let prefs = CompanionPreferences(defaults: defaults)
      #expect(
        !prefs.onboardingComplete && CompanionAvatar.allCases.count == 6,
        "First run introduces Sig and five specialists")
      defaults.set("coast-buddy", forKey: "appearance.avatar")
      prefs.onboardingComplete = true
      let restored = CompanionPreferences(defaults: defaults)
      #expect(
        restored.onboardingComplete && restored.avatar == .sig,
        "Finishing onboarding preserves consent and fixes Sig as principal")
    }

  }
}
