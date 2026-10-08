import SwiftUI

struct CompanionOnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel
    @EnvironmentObject private var preferences: CompanionPreferences
    @EnvironmentObject private var codex: CodexUsageViewModel
    @EnvironmentObject private var usage: AIUsageViewModel
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var scrollable: Bool
    var clipboard: ClipboardViewModel?
    var prepareVoice: (() async -> String)?
    var onFinish: () -> Void
    var arrivalPreviewTime: Double?
    init(scrollable: Bool = true, clipboard: ClipboardViewModel? = nil, initialStep: Int = 0, arrivalPreviewTime: Double? = nil, onFinish: @escaping () -> Void = {}, prepareVoice: (() async -> String)? = nil) {
        self.scrollable = scrollable; self.clipboard = clipboard; self.arrivalPreviewTime = arrivalPreviewTime; self.onFinish = onFinish; self.prepareVoice = prepareVoice
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(initialStep: initialStep))
    }
    private var chosen: CompanionAvatar { viewModel.selection ?? preferences.avatar }
    private var moves: Bool { preferences.characterMotion && !preferences.usesReducedMotion && !reducedMotion }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                if viewModel.step > 0 { CompanionCharacter(size: 48, avatar: chosen, animates: moves) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.step == 0 ? "A little companion. A quieter day." : viewModel.step == 1 ? "Find your companion." : "Bring your tools along.").font(.largeTitle.weight(.semibold))
                    Text(viewModel.step == 0 ? "Meet Sieghart. A familiar face for your time and your tools." : viewModel.step == 1 ? "Six personalities. The same useful companion." : "Choose what stays nearby. You can change this anytime.")
                        .foregroundStyle(CompanionStyle.muted)
                }
            }
            Group {
                if scrollable { ScrollView { page }.scrollIndicators(.hidden) }
                else { page; Spacer(minLength: 0) }
            }
            HStack {
                if viewModel.step > 0 { Button("Back") { viewModel.step -= 1 }.buttonStyle(CompanionButtonStyle()) }
                Spacer()
                HStack(spacing: 6) { ForEach(0..<3) { index in Capsule().fill(viewModel.step == index ? CompanionStyle.accent : CompanionStyle.edge.opacity(0.15)).frame(width: viewModel.step == index ? 20 : 6, height: 6) } }
                    .accessibilityLabel("Step \(viewModel.step + 1) of 3")
                Spacer()
                Button(viewModel.step == 0 ? "Meet the companions" : viewModel.step == 1 ? "Continue with \(chosen.name)" : "Make yourself at home") {
                    if viewModel.step < 2 { viewModel.step += 1 }
                    else {
                        viewModel.complete(preferences: preferences, usage: usage, codex: codex, clipboard: clipboard)
                        onFinish()
                    }
                }.buttonStyle(CompanionButtonStyle(primary: true)).disabled(viewModel.preparingAccess)
            }
        }.padding(32).frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(CompanionStyle.ink).background { WorkspaceBackdrop() }.preferredColorScheme(preferences.appearance.colorScheme)
            .environment(\.workspaceGlass, true).environment(\.surfaceGlassEnabled, preferences.windowGlass)
            .environment(\.islandReduceMotion, preferences.usesReducedMotion)
            .animation(moves ? .spring(response: 0.55, dampingFraction: 0.86) : nil, value: viewModel.step)
            .onAppear { viewModel.loadTools(usage: usage, clipboard: clipboard) }
    }
    private var page: some View {
        VStack(alignment: .leading, spacing: 18) {
            if viewModel.step == 0 {
                VStack(spacing: 12) {
                    CompanionArrivalView(avatar: chosen, animates: moves, previewElapsed: arrivalPreviewTime)
                    Text("Ready when you are.").font(.title2.weight(.semibold))
                    Text("Keep a timer nearby, find something you copied, or speak a command. Your companion stays with you — without taking over your day.")
                        .font(.callout).foregroundStyle(CompanionStyle.muted).multilineTextAlignment(.center).frame(maxWidth: 470)
                    HStack(spacing: 14) { ForEach(CompanionAvatar.allCases) { avatar in CompanionCharacter(size: 34, avatar: avatar, animates: moves) } }
                        .padding(.top, 16).accessibilityHidden(true)
                    Text("Six companions. Yours to choose.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }.frame(maxWidth: .infinity).padding(.vertical, 22).modifier(WorkspaceSurface(radius: 24))
            } else if viewModel.step == 1 {
                CompanionAvatarPicker(selection: Binding(get: { chosen }, set: { viewModel.selection = $0 }), animates: moves)
                Text(chosen.detail).font(.callout).foregroundStyle(CompanionStyle.muted)
                Text("Your choice appears in the menu bar, island, focus sessions and voice feedback. Change it anytime in Appearance.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(AIProvider.allCases) { provider in
                        HStack(spacing: 12) {
                            ProviderMark(provider: provider, size: 30)
                            Text(provider.title).font(.headline)
                            Spacer()
                            Text(viewModel.detected.contains(provider) ? "Detected on this Mac" : "Available when installed").font(.caption).foregroundStyle(CompanionStyle.muted)
                        }
                    }
                    HStack { Text("Automatically follow local AI usage"); Spacer(); Toggle("Automatically follow local AI usage", isOn: $viewModel.allowUsage).labelsHidden().toggleStyle(WorkspaceSwitchStyle()) }
                    Text("Read local token counts, model/project names and work status using existing sign-in. Conversation text is not saved. No extra API key.")
                        .font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack { Text("Keep clipboard history on this Mac"); Spacer(); Toggle("Keep clipboard history on this Mac", isOn: $viewModel.allowClipboard).labelsHidden().toggleStyle(WorkspaceSwitchStyle()) }
                    Text("Save new copies of text, images and file references locally. Search, pin and reuse them. Marked secret copies and password-manager apps are skipped. Pause or clear history anytime.")
                        .font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                }.companionCard()
                HStack(spacing: 10) {
                    if let prepareVoice {
                        Button(viewModel.preparingAccess ? "Preparing voice…" : "Set up voice access") {
                            viewModel.prepareVoice(using: prepareVoice)
                        }.buttonStyle(CompanionButtonStyle(compact: true)).disabled(viewModel.preparingAccess)
                    }
                    if viewModel.allowClipboard, let clipboard { Button("Set up direct paste") { clipboard.requestPasteAccess(); viewModel.accessStatus = clipboard.status }.buttonStyle(CompanionButtonStyle(compact: true)) }
                }
                if !viewModel.accessStatus.isEmpty { Text(viewModel.accessStatus).font(.caption).foregroundStyle(CompanionStyle.accentInk) }
                Text("Your companion and timers work offline with both options off. Access setup is optional; you can also grant it when using voice or direct paste later.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            }
        }.id(viewModel.step).transition(.opacity.combined(with: .offset(x: moves ? 14 : 0)))
    }
}
