import SwiftUI

private enum MenuPage: String, CaseIterable {
    case companion = "Companion", timers = "Timers", ai = "AI", audio = "Audio", avatars = "Avatars"
    var symbol: String { switch self { case .companion: "face.smiling"; case .timers: "timer"; case .ai: "sparkles"; case .audio: "speaker.wave.2"; case .avatars: "person.crop.square" } }
}
struct MenuBarView: View {
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var notch: NotchWidgetController
    @EnvironmentObject private var activation: ActivationController
    @EnvironmentObject private var preferences: CompanionPreferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.islandPreview) private var preview
    @State private var page: MenuPage
    init(initialPage: String = "Companion") { _page = State(initialValue: MenuPage(rawValue: initialPage) ?? .companion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                CompanionCharacter(size: 40, avatar: preferences.avatar, animates: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sieghart").font(.system(size: 19, weight: .semibold))
                    Text(preferences.avatar.name).font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                Text(page.rawValue).font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            HStack(spacing: 4) {
                ForEach(MenuPage.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        Group {
                            if item == .companion { CompanionCharacter(size: 24, avatar: preferences.avatar, animates: false) }
                            else { Image(systemName: item.symbol).font(.system(size: 18)) }
                        }.frame(maxWidth: .infinity).frame(height: 42)
                            .foregroundStyle(page == item ? CompanionStyle.accent : CompanionStyle.muted)
                            .background(page == item ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).help(item.rawValue).accessibilityLabel(item.rawValue).accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }.padding(4).modifier(WorkspaceSurface(radius: 14))
            Group {
                switch page {
                case .companion:
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 22) {
                            CompanionCharacter(size: 76, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(assistant.hasActiveSession ? assistant.activityTitle : "Ready when you are.").font(.headline)
                                Text(assistant.hasActiveSession ? assistant.pomodoroTimeLabel : "A little company for your day.").font(.callout).foregroundStyle(CompanionStyle.muted)
                                Text("\(assistant.completedSessions) sessions done").font(.caption).foregroundStyle(CompanionStyle.accent)
                            }
                        }
                        Button("Show companion") { notch.show() }.buttonStyle(CompanionButtonStyle(primary: true))
                        Button(activation.isListening || activation.isPreparing ? "Cancel voice" : "Speak a command") { activation.toggleListening() }.buttonStyle(CompanionButtonStyle())
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .timers: TimerToolsView(onStart: { notch.showIsland() })
                case .ai:
                    VStack(alignment: .leading, spacing: 18) {
                        AIUsageSummary(compact: true)
                        Button("Open AI agents & charts") { notch.showAILimits() }.buttonStyle(CompanionButtonStyle(primary: true))
                    }.frame(maxHeight: .infinity, alignment: .top)
                case .audio:
                    if preview { AudioControlsView(compact: true).environmentObject(notch.audio) }
                    else { ScrollView { AudioControlsView(compact: true).environmentObject(notch.audio) }.scrollIndicators(.hidden) }
                case .avatars: CompanionAvatarPicker(selection: $preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion, compact: true)
                }
            }.frame(height: 300, alignment: .top)
            Divider().overlay(.white.opacity(0.1))
            HStack {
                Button { openWindow(id: "main"); notch.focusMainWindow() } label: { Label("Open Sieghart", systemImage: "gearshape") }.buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
            }.font(.caption).foregroundStyle(CompanionStyle.muted)
        }.padding(28).frame(width: 560).foregroundStyle(.white)
            .background { WorkspaceBackdrop() }.preferredColorScheme(.dark)
            .environment(\.workspaceGlass, true).environment(\.islandReduceMotion, preferences.usesReducedMotion).focusEffectDisabled()
    }
}
