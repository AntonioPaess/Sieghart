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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                CompanionCharacter(size: 30, avatar: preferences.avatar, animates: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sieghart").font(.system(size: 16, weight: .semibold))
                    Text(preferences.avatar.name).font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                Text(page.rawValue).font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            HStack(spacing: 4) {
                ForEach(MenuPage.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        Group {
                            if item == .companion { CompanionCharacter(size: 20, avatar: preferences.avatar, animates: false) }
                            else { Image(systemName: item.symbol).font(.system(size: 16)) }
                        }.frame(maxWidth: .infinity).frame(height: 34)
                            .foregroundStyle(page == item ? CompanionStyle.accentInk : CompanionStyle.muted)
                            .background(page == item ? CompanionStyle.edge.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).help(item.rawValue).accessibilityLabel(item.rawValue).accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }.padding(4).modifier(WorkspaceSurface(radius: 14))
            Group {
                switch page {
                case .companion:
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            CompanionCharacter(size: 60, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(assistant.hasActiveSession ? assistant.activityTitle : "Ready when you are.").font(.headline)
                                Text(assistant.hasActiveSession ? assistant.pomodoroTimeLabel : "A little company for your day.").font(.callout).foregroundStyle(CompanionStyle.muted)
                                Text("\(assistant.completedSessions) sessions done").font(.caption).foregroundStyle(CompanionStyle.accentInk)
                            }
                        }
                        HStack(spacing: 10) {
                            Button("Show companion") { notch.show() }.buttonStyle(CompanionButtonStyle(primary: true, compact: true))
                            Button(activation.isListening || activation.isPreparing ? "Cancel voice" : "Speak a command") { activation.toggleListening() }.buttonStyle(CompanionButtonStyle(compact: true))
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                case .timers: TimerToolsView(compact: true, onStart: { notch.showIsland() })
                case .ai:
                    AIUsageSummary(compact: true)
                case .audio:
                    if preview { AudioControlsView(compact: true).environmentObject(notch.audio) }
                    else { AudioControlsView(compact: true).environmentObject(notch.audio) }
                case .avatars: CompanionAvatarPicker(selection: $preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion, compact: true)
                }
            }.fixedSize(horizontal: false, vertical: true)
            Divider().overlay(CompanionStyle.edge.opacity(0.1))
            HStack {
                Button { openWindow(id: "main"); notch.focusMainWindow() } label: { Label("Open Sieghart", systemImage: "gearshape") }.buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
            }.font(.caption).foregroundStyle(CompanionStyle.muted)
        }.padding(20).frame(width: 380).foregroundStyle(CompanionStyle.ink)
            .background { WorkspaceBackdrop() }.preferredColorScheme(preferences.appearance.colorScheme)
            .environment(\.workspaceGlass, true).environment(\.surfaceGlassEnabled, preferences.windowGlass).environment(\.islandReduceMotion, preferences.usesReducedMotion).focusEffectDisabled()
    }
}
