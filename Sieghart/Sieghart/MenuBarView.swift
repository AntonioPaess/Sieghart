import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var notch: NotchWidgetController
    @EnvironmentObject private var activation: ActivationController
    @EnvironmentObject private var preferences: CompanionPreferences
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                CompanionCharacter(size: 44, avatar: preferences.avatar, animates: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sieghart").font(.system(size: 20, weight: .semibold))
                    Text(preferences.avatar.name).font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(assistant.isRunning ? .mint : CompanionStyle.accent)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(assistant.hasActiveSession ? assistant.activityTitle.uppercased() : "READY TO FOCUS")
                    Spacer()
                    Text(assistant.sessionCaption)
                }.font(.system(size: 10, weight: .semibold)).foregroundStyle(CompanionStyle.muted)
                HStack {
                    Text(assistant.hasActiveSession ? assistant.pomodoroTimeLabel : String(format: "%02d:00", assistant.focusMinutes))
                        .font(.system(size: 38, weight: .medium)).monospacedDigit()
                    Spacer()
                    if assistant.hasActiveSession {
                        Button { assistant.togglePomodoro() } label: {
                            Image(systemName: assistant.isRunning ? "pause.fill" : "play.fill")
                                .frame(width: 36, height: 36)
                        }.buttonStyle(CompanionButtonStyle(primary: true)).focusEffectDisabled()
                            .accessibilityLabel(assistant.pomodoroButtonLabel)
                    }
                }
                if assistant.hasActiveSession {
                    GeometryReader { geometry in
                        Capsule().fill(CompanionStyle.separator)
                            .overlay(alignment: .leading) {
                                Capsule().fill(CompanionStyle.accent)
                                    .frame(width: geometry.size.width * assistant.pomodoroProgress)
                            }
                    }.frame(height: 3)
                        .accessibilityLabel("Time remaining")
                        .accessibilityValue("\(Int(assistant.pomodoroProgress * 100)) percent")
                } else {
                    Text("Make room for one thing.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Button("Choose focus session") { notch.showFocusSetup() }
                    .buttonStyle(CompanionButtonStyle(primary: !assistant.hasActiveSession)).focusEffectDisabled()
            }.padding(16).background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            VStack(spacing: 8) {
                actionRow(notch.presentation == .island || !notch.isVisible ? "Show companion" : "Tuck away widget", symbol: "rectangle.topthird.inset.filled") { notch.toggle() }
                actionRow(activation.isListening || activation.isPreparing ? "Cancel voice" : "Speak a command", symbol: "mic.fill", detail: activation.voiceShortcut?.label) {
                    if activation.isListening || activation.isPreparing { activation.cancelVoiceCommand() }
                    else { activation.toggleListening() }
                }
                actionRow("Open Sieghart", symbol: "macwindow") { openWindow(id: "main"); notch.focusMainWindow() }
            }
            HStack {
                Text("\(assistant.completedSessions) sessions completed").font(.caption).foregroundStyle(CompanionStyle.muted)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption).foregroundStyle(CompanionStyle.muted).focusEffectDisabled()
            }
        }
        .padding(20).frame(width: 320)
        .foregroundStyle(.white)
        .background(CompanionStyle.background)
        .tint(CompanionStyle.accent).preferredColorScheme(.dark)
    }

    private func actionRow(_ title: String, symbol: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        CompanionInteraction(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(CompanionStyle.accent)
                Text(title).font(.callout.weight(.medium))
                Spacer()
                if let detail { Text(detail).font(.caption).foregroundStyle(CompanionStyle.muted) }
            }.padding(12).background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        }.accessibilityLabel(title)
    }
}
