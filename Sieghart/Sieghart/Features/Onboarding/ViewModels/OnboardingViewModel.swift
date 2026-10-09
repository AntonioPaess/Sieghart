import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var preparingAccess = false
    @Published var accessStatus = ""
    @Published var step: Int
    @Published var selection: CompanionAvatar?
    @Published var detected: Set<AIProvider> = []
    @Published var allowUsage = true
    @Published var allowClipboard = false
    init(initialStep: Int = 0) { step = min(2, max(0, initialStep)) }
    func loadTools(usage: AIUsageViewModel, clipboard: ClipboardViewModel?) {
        detected = InstalledAIProviders.detect()
        allowUsage = usage.automaticDetection
        allowClipboard = clipboard?.isEnabled ?? false
    }
    func complete(preferences: CompanionPreferences, usage: AIUsageViewModel, codex: CodexUsageViewModel, clipboard: ClipboardViewModel?) {
        preferences.avatar = selection ?? preferences.avatar
        usage.automaticDetection = allowUsage
        codex.enabled = allowUsage && detected.contains(.codex)
        usage.claudeEnabled = allowUsage && detected.contains(.claude)
        clipboard?.isEnabled = allowClipboard
        preferences.onboardingComplete = true
    }
    func prepareVoice(using prepare: @escaping () async -> String) {
        guard !preparingAccess else { return }
        preparingAccess = true
        Task {
            accessStatus = await prepare()
            preparingAccess = false
        }
    }
}
