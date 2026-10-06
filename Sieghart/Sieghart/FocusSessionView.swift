import SwiftUI

// One surface for all three tools. Choosing a tab never starts or resets time.
struct TimerToolsView: View {
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var preferences: CompanionPreferences
    @Environment(\.islandReduceMotion) private var reduceMotion
    var onStart: () -> Void
    @State private var minutes = 15

    private var mode: TimerToolMode { assistant.selectedTimerMode }
    private var clock: UtilityClock { assistant.utilityClock }
    private var showsUtilitySession: Bool { clock.mode == mode && clock.phase != .idle }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(TimerToolMode.allCases, id: \.self) { option in
                    Button { assistant.selectTimerMode(option) } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .modifier(IslandControlSurface(selected: mode == option))
                    }.buttonStyle(IslandButtonStyle()).accessibilityAddTraits(mode == option ? .isSelected : [])
                }
            }.accessibilityLabel("Timer mode")
            if mode == .pomodoro {
                if assistant.hasActiveSession { activePomodoro }
                else { FocusSessionEditor(onStart: onStart) }
            } else if showsUtilitySession { activeUtility }
            else { utilitySetup }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: mode)
        .onAppear { minutes = clock.timerMinutes }
        .onChange(of: minutes) { _, value in clock.setMinutes(value) }
    }

    private var utilitySetup: some View {
        VStack(spacing: 20) {
            CompanionCharacter(size: 58, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion)
            Text(mode == .timer ? String(format: "%02d:00", minutes) : "00:00.0")
                .font(.system(size: 46, weight: .medium, design: .rounded)).monospacedDigit()
            if mode == .timer {
                HStack(spacing: 16) {
                    minuteButton("minus", label: "Decrease duration") { minutes = max(1, minutes - 1) }
                    Text("\(minutes) minutes").font(.callout).monospacedDigit().frame(maxWidth: .infinity)
                    minuteButton("plus", label: "Increase duration") { minutes = min(180, minutes + 1) }
                }
                HStack(spacing: 8) {
                    ForEach([5, 15, 30, 60], id: \.self) { value in
                        Button("\(value) min") { minutes = value }
                            .font(.caption).frame(maxWidth: .infinity).padding(.vertical, 9)
                            .modifier(IslandControlSurface(selected: minutes == value)).buttonStyle(IslandButtonStyle())
                    }
                }
            } else {
                Text("Count up at your own pace.").font(.callout).foregroundStyle(CompanionStyle.muted)
            }
            if clock.hasSession && clock.mode != mode {
                Text("Starting replaces the active \(clock.mode.title.lowercased()).").font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            Button {
                clock.start(mode, minutes: minutes)
                onStart()
            } label: { Label("Start \(mode.title.lowercased())", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(CompanionButtonStyle(primary: true))
        }
    }

    private var activeUtility: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                CompanionCharacter(size: 58, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion,
                                   mood: clock.phase == .completed ? .celebrating : .idle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(clock.phase == .completed ? "Timer complete" : clock.phase == .paused ? "Paused" : mode.title).font(.headline)
                    Text(mode == .timer ? "\(clock.timerMinutes) minute countdown" : "Elapsed time").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                if preferences.compactTimer { clockDigits(clock.timeLabel, size: 28) }
            }
            if !preferences.compactTimer { clockDigits(clock.timeLabel, size: 46) }
            if mode == .timer {
                GeometryReader { geometry in
                    Capsule().fill(CompanionStyle.separator).overlay(alignment: .leading) {
                        Capsule().fill(CompanionStyle.accent).frame(width: geometry.size.width * clock.progress)
                    }
                }.frame(height: 4).accessibilityLabel("Time remaining").accessibilityValue("\(Int(clock.progress * 100)) percent")
            }
            HStack(spacing: 10) {
                Button(clock.phase == .completed ? "New timer" : "Reset") { clock.reset() }
                    .buttonStyle(CompanionButtonStyle())
                if clock.phase != .completed {
                    Button { clock.togglePause() } label: {
                        Label(clock.isRunning ? "Pause" : "Resume", systemImage: clock.isRunning ? "pause.fill" : "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(CompanionButtonStyle(primary: true))
                }
            }
        }
    }

    private var activePomodoro: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                CompanionCharacter(size: 58, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion, focusing: assistant.interval == .focus)
                VStack(alignment: .leading, spacing: 4) {
                    Text(assistant.activityTitle).font(.headline)
                    Text(assistant.sessionCaption).font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                if preferences.compactTimer { clockDigits(assistant.pomodoroTimeLabel, size: 28) }
            }
            if !preferences.compactTimer { clockDigits(assistant.pomodoroTimeLabel, size: 46) }
            HStack(spacing: 10) {
                Button("Reset") { assistant.resetPomodoro() }.buttonStyle(CompanionButtonStyle())
                Button(assistant.isRunning ? "Pause" : "Resume") { assistant.togglePomodoro() }
                    .buttonStyle(CompanionButtonStyle(primary: true))
                Button("Finish") { assistant.finishPomodoroFromWidget() }.buttonStyle(CompanionButtonStyle())
            }
            Text("\(assistant.shortBreakMinutes) min short break · \(assistant.longBreakMinutes) min long break · \(assistant.sessionsPerCycle) rounds")
                .font(.caption).foregroundStyle(CompanionStyle.muted)
        }
    }

    private func minuteButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 38, height: 34).modifier(IslandControlSurface()) }
            .buttonStyle(IslandButtonStyle()).accessibilityLabel(label)
    }

    private func clockDigits(_ text: String, size: CGFloat) -> some View {
        Text(text).font(.system(size: size, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }
}

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
