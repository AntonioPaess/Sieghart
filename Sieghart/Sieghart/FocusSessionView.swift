import SwiftUI

// Switching tools only changes the page. A session starts through Start.
struct TimerToolsView: View {
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var preferences: CompanionPreferences
    @Environment(\.islandPreview) private var preview
    var onStart: () -> Void
    @State private var minutes = 15.0
    @State private var focusMinutes = 25.0
    @State private var shortBreak = 5
    @State private var longBreak = 15
    @State private var rounds = 4
    @State private var autoBreak = true
    private var mode: TimerToolMode { assistant.selectedTimerMode }
    private var clock: UtilityClock { assistant.utilityClock }
    private var active: Bool { mode == .pomodoro ? assistant.hasActiveSession : clock.mode == mode && clock.phase != .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 22) {
                ForEach(TimerToolMode.allCases, id: \.self) { option in
                    Button { assistant.selectTimerMode(option) } label: {
                        Text(option.title).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(mode == option ? .white : CompanionStyle.muted)
                            .padding(.vertical, 9)
                            .overlay(alignment: .bottom) { if mode == option { Capsule().fill(CompanionStyle.accent).frame(height: 2) } }
                    }.buttonStyle(.plain).accessibilityAddTraits(mode == option ? .isSelected : [])
                }
                Spacer(minLength: 4)
                if !active { Button("Start", action: start).buttonStyle(CompanionButtonStyle(primary: true)) }
            }.accessibilityLabel("Timer mode")
            if active { activeSession }
            else {
                HStack(spacing: 28) {
                    if mode == .stopwatch {
                        CompanionCharacter(size: 56, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion)
                        Text("Count up at your own pace.").font(.callout).foregroundStyle(CompanionStyle.muted)
                        Spacer()
                    } else {
                        DurationRuler(value: mode == .pomodoro ? $focusMinutes : $minutes, range: mode == .pomodoro ? 5...60 : 1...180, step: mode == .pomodoro ? 5 : 1)
                    }
                    digits(mode == .pomodoro ? String(format: "%02d:00", Int(focusMinutes)) : mode == .timer ? String(format: "%02d:00", Int(minutes)) : "00:00.0")
                        .frame(width: mode == .stopwatch ? 145 : 120, alignment: .trailing)
                }.frame(height: 98)
                if mode == .pomodoro {
                    HStack(alignment: .top, spacing: 22) {
                        choice("Short break", selection: $shortBreak, values: AssistantViewModel.shortBreakLengths, suffix: "min")
                        choice("Long break", selection: $longBreak, values: AssistantViewModel.longBreakLengths, suffix: "min")
                        choice("Rounds", selection: $rounds, values: AssistantViewModel.roundCounts, suffix: "")
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Auto break").font(.caption2).foregroundStyle(CompanionStyle.muted)
                            Toggle("Auto break", isOn: $autoBreak).labelsHidden().toggleStyle(WorkspaceSwitchStyle()).accessibilityLabel("Start breaks automatically")
                        }
                    }
                } else if mode == .timer {
                    HStack(spacing: 12) {
                        ForEach([5, 15, 30, 60], id: \.self) { value in
                            Button("\(value) min") { minutes = Double(value) }
                                .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(Int(minutes) == value ? CompanionStyle.accent : CompanionStyle.muted)
                        }
                        Spacer()
                        if clock.hasSession && clock.mode != mode { Text("Start replaces the active stopwatch.").font(.caption2).foregroundStyle(CompanionStyle.muted) }
                    }
                }
            }
        }
        .onAppear {
            minutes = Double(clock.timerMinutes); focusMinutes = Double(assistant.focusMinutes)
            shortBreak = assistant.shortBreakMinutes; longBreak = assistant.longBreakMinutes
            rounds = assistant.sessionsPerCycle; autoBreak = assistant.autoStartBreaks
        }
        .onChange(of: minutes) { _, value in clock.setMinutes(Int(value)) }
    }
    private func start() {
        if mode == .pomodoro { assistant.startFocusSession(minutes: Int(focusMinutes), shortBreak: shortBreak, longBreak: longBreak, rounds: rounds, autoBreak: autoBreak) }
        else { clock.start(mode, minutes: Int(minutes)) }
        onStart()
    }
    private var activeSession: some View {
        let completed = mode != .pomodoro && clock.phase == .completed
        let running = mode == .pomodoro ? assistant.isRunning : clock.isRunning
        return VStack(spacing: 22) {
            HStack(spacing: 22) {
                CompanionCharacter(size: 58, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion, focusing: mode == .pomodoro && assistant.interval == .focus, mood: completed ? .celebrating : .idle)
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode == .pomodoro ? assistant.activityTitle : completed ? "Timer complete" : running ? mode.title : "Paused").font(.headline)
                    Text(mode == .pomodoro ? assistant.sessionCaption : mode == .timer ? "\(clock.timerMinutes) minute countdown" : "Elapsed time").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                digits(mode == .pomodoro ? assistant.pomodoroTimeLabel : clock.timeLabel)
            }.frame(height: 88)
            if mode != .stopwatch {
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.12)).overlay(alignment: .leading) {
                        Capsule().fill(CompanionStyle.accent).frame(width: geometry.size.width * (mode == .pomodoro ? assistant.pomodoroProgress : clock.progress))
                    }
                }.frame(height: 5).accessibilityLabel("Time remaining").accessibilityValue("\(Int((mode == .pomodoro ? assistant.pomodoroProgress : clock.progress) * 100)) percent")
            }
            HStack(spacing: 12) {
                Button(completed ? "New timer" : "Reset") { if mode == .pomodoro { assistant.resetPomodoro() } else { clock.reset() } }.buttonStyle(CompanionButtonStyle())
                if !completed {
                    Button(running ? "Pause" : "Resume") { if mode == .pomodoro { assistant.togglePomodoro() } else { clock.togglePause() } }.buttonStyle(CompanionButtonStyle(primary: true))
                }
                Spacer()
                if mode == .pomodoro {
                    Text("\(assistant.shortBreakMinutes) / \(assistant.longBreakMinutes) min breaks").font(.caption).foregroundStyle(CompanionStyle.muted)
                    Button("Finish") { assistant.finishPomodoroFromWidget() }.buttonStyle(CompanionButtonStyle())
                }
            }
        }
    }
    private func digits(_ value: String) -> some View { Text(value).font(.system(size: preferences.compactTimer ? 32 : 40, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(CompanionStyle.accent).lineLimit(1).minimumScaleFactor(0.7) }
    private func choice(_ title: String, selection: Binding<Int>, values: [Int], suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2).foregroundStyle(CompanionStyle.muted)
            if preview { Text("\(selection.wrappedValue)\(suffix) ⌄").font(.callout.weight(.semibold)).foregroundStyle(CompanionStyle.accent) }
            else {
                Menu { ForEach(values, id: \.self) { value in Button("\(value)\(suffix)") { selection.wrappedValue = value } } } label: {
                    HStack(spacing: 5) { Text("\(selection.wrappedValue)\(suffix)"); Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)) }.font(.callout.weight(.semibold)).foregroundStyle(CompanionStyle.accent)
                }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(title)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DurationRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    private var fraction: Double { (value - range.lowerBound) / (range.upperBound - range.lowerBound) }
    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let labels = range.upperBound == 60 ? [5, 15, 25, 35, 45, 60] : [1, 30, 60, 90, 120, 150, 180]
                ForEach(labels, id: \.self) { minute in
                    Text("\(minute)").font(.caption.weight(.medium)).foregroundStyle(CompanionStyle.muted)
                        .position(x: min(geometry.size.width - 10, max(10, geometry.size.width * (Double(minute) - range.lowerBound) / (range.upperBound - range.lowerBound))), y: 8)
                }
            }.frame(height: 16)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(0..<41) { index in
                            Capsule().fill(Double(index) / 40 <= fraction ? CompanionStyle.accent : CompanionStyle.accent.opacity(0.2))
                                .frame(width: 3, height: index.isMultiple(of: 5) ? 40 : 32).frame(maxWidth: .infinity)
                        }
                    }
                    Image(systemName: "triangle.fill").font(.system(size: 10)).foregroundStyle(CompanionStyle.accent)
                        .offset(x: max(0, (geometry.size.width - 10) * fraction), y: 30)
                }.frame(height: 44).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        let position = min(1, max(0, event.location.x / max(1, geometry.size.width)))
                        value = min(range.upperBound, max(range.lowerBound, ((range.lowerBound + position * (range.upperBound - range.lowerBound)) / step).rounded() * step))
                    })
            }.frame(height: 56)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Duration in minutes").accessibilityValue("\(Int(value)) minutes")
            .accessibilityAdjustableAction { direction in
                switch direction { case .increment: value = min(range.upperBound, value + step); case .decrement: value = max(range.lowerBound, value - step); @unknown default: break }
            }
    }
}
