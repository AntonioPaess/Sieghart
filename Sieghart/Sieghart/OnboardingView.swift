import SwiftUI

struct CompanionOnboardingView: View {
    @EnvironmentObject private var preferences: CompanionPreferences
    @EnvironmentObject private var codex: CodexUsageModel
    @EnvironmentObject private var usage: AIUsageModel
    var scrollable = true
    @State private var step = 0
    @State private var selection: CompanionAvatar = .crtBuddy
    @State private var detected: Set<AIProvider> = []
    @State private var allowUsage = true
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                CompanionCharacter(size: 60, avatar: selection, animates: preferences.characterMotion && !preferences.usesReducedMotion)
                VStack(alignment: .leading, spacing: 5) {
                    Text(step == 0 ? "Meet your companion." : "Bring your AI work along.").font(.largeTitle.weight(.semibold))
                    Text(step == 0 ? "Six personalities. One quiet place to focus." : "Your island can follow the tools you already use.")
                        .foregroundStyle(CompanionStyle.muted)
                }
            }
            Group {
                if scrollable { ScrollView { page } }
                else { page; Spacer(minLength: 0) }
            }
            HStack {
                if step > 0 { Button("Back") { step = 0 }.buttonStyle(CompanionButtonStyle()) }
                Spacer()
                Text("\(step + 1) of 2").font(.caption).foregroundStyle(CompanionStyle.muted)
                Button(step == 0 ? "Continue with \(selection.name)" : "Meet Sieghart") {
                    if step == 0 { step = 1 }
                    else {
                        preferences.avatar = selection
                        usage.automaticDetection = allowUsage
                        codex.enabled = allowUsage && detected.contains(.codex)
                        usage.claudeEnabled = allowUsage && detected.contains(.claude)
                        preferences.onboardingComplete = true
                    }
                }.buttonStyle(CompanionButtonStyle(primary: true))
            }
        }.padding(32).frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white).background { WorkspaceBackdrop() }
            .environment(\.workspaceGlass, true)
            .environment(\.islandReduceMotion, preferences.usesReducedMotion)
            .onAppear { selection = preferences.avatar; detected = InstalledAIProviders.detect() }
    }

    private var page: some View {
            VStack(alignment: .leading, spacing: 18) {
            if step == 0 {
                CompanionAvatarPicker(selection: $selection, animates: preferences.characterMotion && !preferences.usesReducedMotion)
                Text(selection.detail).font(.callout).foregroundStyle(CompanionStyle.muted)
                Text("Your choice appears in the menu bar, island, focus sessions and voice feedback. Change it anytime in Appearance.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(AIProvider.allCases) { provider in
                        HStack(spacing: 12) {
                            ProviderMark(provider: provider, size: 38)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.title).font(.headline)
                                Text(detected.contains(provider) ? "Detected on this Mac" : "Not found yet — detected when installed")
                                    .font(.caption).foregroundStyle(CompanionStyle.muted)
                            }
                            Spacer()
                            Image(systemName: detected.contains(provider) ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(detected.contains(provider) ? .mint : CompanionStyle.muted)
                        }
                    }
                    Divider()
                    Toggle("Automatically follow local AI usage", isOn: $allowUsage).toggleStyle(WorkspaceSwitchStyle())
                    Text("With your permission, Sieghart reads local token counts, model and project names, and work status. Codex limits use your existing sign-in. Conversation text is not saved. Your focus companion works with this switched off.")
                        .font(.callout).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                    Text("No extra API key. No permission prompt each time you open the island. You can turn monitoring off in AI limits.")
                        .font(.caption).foregroundStyle(CompanionStyle.muted)
                }.companionCard()
                Text("Microphone, speech and optional impact controls are available when you choose to use them.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            }
    }
}
