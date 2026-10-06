import SwiftUI

// The app tab and notch use the same editor, choices, and saved session model.
struct FocusSessionEditor: View {
    @EnvironmentObject private var assistant: AssistantViewModel
    var onStart: () -> Void
    var onCancel: (() -> Void)? = nil
    @State private var minutes = 25.0
    @State private var shortBreak = 5
    @State private var longBreak = 15
    @State private var rounds = 4
    @State private var autoBreak = true

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Focus length").foregroundStyle(CompanionStyle.muted)
                Spacer()
                Text("\(Int(minutes)) minutes").fontWeight(.semibold)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<31) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Double(index) <= (minutes - 5) / 55 * 30 ? CompanionStyle.accent : CompanionStyle.separator)
                        .frame(height: index % 5 == 0 ? 24 : 12)
                }
            }.frame(height: 24).accessibilityHidden(true)
            VStack(spacing: 4) {
                Slider(value: $minutes, in: 5...60, step: 5).accessibilityLabel("Focus duration in minutes").accessibilityValue("\(Int(minutes)) minutes")
                HStack {
                    ForEach([5, 15, 25, 35, 45, 60], id: \.self) { value in
                        if value != 5 { Spacer() }
                        Text(value == 60 ? "60 min" : "\(value)")
                    }
                }.font(.caption2).foregroundStyle(CompanionStyle.muted)
            }
            HStack(spacing: 14) {
                choice("Short break", selection: $shortBreak, choices: AssistantViewModel.shortBreakLengths, suffix: "min")
                choice("Long break", selection: $longBreak, choices: AssistantViewModel.longBreakLengths, suffix: "min")
                choice("Rounds", selection: $rounds, choices: AssistantViewModel.roundCounts, suffix: "sessions")
            }
            Toggle("Start breaks automatically", isOn: $autoBreak).toggleStyle(.switch).controlSize(.small)
            HStack(spacing: 10) {
                if let onCancel { Button("Back", action: onCancel).buttonStyle(CompanionButtonStyle()).focusEffectDisabled() }
                Button {
                    assistant.startFocusSession(minutes: Int(minutes), shortBreak: shortBreak, longBreak: longBreak, rounds: rounds, autoBreak: autoBreak)
                    onStart()
                } label: {
                    Text(assistant.hasActiveSession ? "Start new focus" : "Start focus").frame(maxWidth: .infinity)
                }.buttonStyle(CompanionButtonStyle(primary: true)).focusEffectDisabled()
            }
        }
        .font(.callout)
        .onAppear {
            minutes = Double(assistant.focusMinutes); shortBreak = assistant.shortBreakMinutes
            longBreak = assistant.longBreakMinutes; rounds = assistant.sessionsPerCycle; autoBreak = assistant.autoStartBreaks
        }
    }

    private func choice(_ title: String, selection: Binding<Int>, choices: [Int], suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption2).foregroundStyle(CompanionStyle.muted)
            Picker(title, selection: selection) {
                ForEach(choices, id: \.self) { value in Text("\(value) \(suffix)").tag(value) }
            }.labelsHidden().pickerStyle(.menu).controlSize(.small)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
