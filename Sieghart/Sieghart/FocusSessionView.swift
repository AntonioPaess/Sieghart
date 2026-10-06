import SwiftUI

// The app tab and notch use the same editor, choices, and saved session model.
struct FocusSessionEditor: View {
    @EnvironmentObject private var assistant: AssistantViewModel
    @Environment(\.islandGlass) private var glass
    var onStart: () -> Void
    var onCancel: (() -> Void)? = nil
    @State private var minutes = 25.0
    @State private var shortBreak = 5
    @State private var longBreak = 15
    @State private var rounds = 4
    @State private var autoBreak = true
    @State private var choicePopover: String?

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Focus length").foregroundStyle(CompanionStyle.muted)
                Spacer()
                Text("\(Int(minutes)) minutes").fontWeight(.semibold)
            }
            if glass { durationRuler } else {
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
            }
            HStack(spacing: 14) {
                choice("Short break", selection: $shortBreak, choices: AssistantViewModel.shortBreakLengths, suffix: "min")
                choice("Long break", selection: $longBreak, choices: AssistantViewModel.longBreakLengths, suffix: "min")
                choice("Rounds", selection: $rounds, choices: AssistantViewModel.roundCounts, suffix: "sessions")
            }
            if glass {
                Button { autoBreak.toggle() } label: {
                    HStack {
                        Text("Start breaks automatically")
                        Spacer()
                        Capsule().fill(autoBreak ? CompanionStyle.accent : Color.white.opacity(0.15))
                            .frame(width: 36, height: 22)
                            .overlay(alignment: autoBreak ? .trailing : .leading) { Circle().fill(.white).frame(width: 16, height: 16).padding(3) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(autoBreak ? "On" : "Off")
            } else { Toggle("Start breaks automatically", isOn: $autoBreak).toggleStyle(.switch).controlSize(.small) }
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
            if glass {
                Button { choicePopover = title } label: {
                    HStack(spacing: 6) { Text("\(selection.wrappedValue) \(suffix)"); Spacer(minLength: 0); Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)) }
                        .padding(.horizontal, 10).padding(.vertical, 8).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(IslandButtonStyle()).accessibilityLabel(title)
                    .popover(isPresented: Binding(get: { choicePopover == title }, set: { if !$0 { choicePopover = nil } })) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(choices, id: \.self) { value in
                                Button("\(value) \(suffix)") { selection.wrappedValue = value; choicePopover = nil }
                                    .buttonStyle(.plain).padding(5)
                            }
                        }.padding(12)
                    }
            } else {
            Picker(title, selection: selection) {
                ForEach(choices, id: \.self) { value in Text("\(value) \(suffix)").tag(value) }
            }.labelsHidden().pickerStyle(.menu).controlSize(.small)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationRuler: some View {
        VStack(spacing: 12) {
            Text(String(format: "%02d:00", Int(minutes))).font(.system(size: 40, weight: .medium, design: .rounded)).monospacedDigit()
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 0) {
                        ForEach(0..<56) { index in
                            Rectangle().fill(Double(index + 5) <= minutes ? CompanionStyle.accent.opacity(0.8) : .white.opacity(0.25))
                                .frame(width: 1, height: (index + 5).isMultiple(of: 5) ? 26 : 12).frame(maxWidth: .infinity)
                        }
                    }
                    Capsule().fill(CompanionStyle.accent).frame(width: 3, height: 40)
                        .offset(x: max(0, (geometry.size.width - 3) * (minutes - 5) / 55))
                }.frame(height: 40).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let fraction = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                        minutes = min(60, max(5, ((5 + fraction * 55) / 5).rounded() * 5))
                    })
            }.frame(height: 40)
            HStack { Text("5 min"); Spacer(); Text("30"); Spacer(); Text("60 min") }.font(.caption2).foregroundStyle(CompanionStyle.muted)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Focus duration").accessibilityValue("\(Int(minutes)) minutes")
            .accessibilityAdjustableAction { direction in
                switch direction { case .increment: minutes = min(60, minutes + 5); case .decrement: minutes = max(5, minutes - 5); @unknown default: break }
            }
    }
}
