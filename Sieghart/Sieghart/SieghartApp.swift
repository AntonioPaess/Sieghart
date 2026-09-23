import SwiftUI

@main
struct SieghartApp: App {
    @StateObject private var sensor: SensorViewModel
    @StateObject private var assistant: AssistantViewModel
    @StateObject private var calendar: CalendarViewModel
    @StateObject private var notch: NotchWidgetController
    @StateObject private var gestures: ImpactGestureCoordinator

    init() {
        let assistant = AssistantViewModel()
        let sensor = SensorViewModel()
        let calendar = CalendarViewModel()
        let notch = NotchWidgetController(assistant: assistant, calendar: calendar)
        let gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        sensor.onImpact = { impact in
            assistant.registerImpact(impact)
            gestures.receive(impact)
        }

        _sensor = StateObject(wrappedValue: sensor)
        _assistant = StateObject(wrappedValue: assistant)
        _calendar = StateObject(wrappedValue: calendar)
        _notch = StateObject(wrappedValue: notch)
        _gestures = StateObject(wrappedValue: gestures)
    }

    var body: some Scene {
        WindowGroup("Sieghart") {
            ContentView()
                .environmentObject(sensor)
                .environmentObject(assistant)
                .environmentObject(calendar)
                .environmentObject(notch)
                .environmentObject(gestures)
        }

        MenuBarExtra("Sieghart", systemImage: "sparkles") {
            MenuBarView()
                .environmentObject(sensor)
                .environmentObject(assistant)
                .environmentObject(calendar)
                .environmentObject(notch)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct ContentView: View {
    @EnvironmentObject private var sensor: SensorViewModel
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var calendar: CalendarViewModel
    @EnvironmentObject private var notch: NotchWidgetController
    @EnvironmentObject private var gestures: ImpactGestureCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.purple)

                    VStack(alignment: .leading, spacing: 4) {
                    Text("Sieghart")
                        .font(.largeTitle.weight(.semibold))
                    Text("Your context partner for Mac")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("The project core starts here.")
                .font(.title3)
            Text("First test: turn a physical impact into a useful action.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label(sensor.status, systemImage: sensor.isRunning ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg")
                    .foregroundStyle(sensor.isRunning ? .green : .secondary)

                if let sample = sensor.lastSample {
                    Text("Acceleration: x \(sample.x.formatted(.number.precision(.fractionLength(2))))g · y \(sample.y.formatted(.number.precision(.fractionLength(2))))g · z \(sample.z.formatted(.number.precision(.fractionLength(2))))g")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text("Reports received: \(sensor.sampleCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let impact = sensor.lastImpact {
                    Text("Last impact: \(impact.timestamp.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(sensor.isRunning ? "Pause sensor" : "Resume sensor") {
                    sensor.toggle()
                }
                .buttonStyle(.borderedProminent)

                Text("The sensor starts automatically when Sieghart opens.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Impact actions", systemImage: "hand.tap")
                    .font(.headline)
                Text("Choose what one, two, or three impacts should do.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Default: two impacts start or pause Pomodoro; three impacts show the calendar.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                ImpactActionPicker(title: "One impact", selection: $gestures.singleImpactAction)
                ImpactActionPicker(title: "Two impacts", selection: $gestures.doubleImpactAction)
                ImpactActionPicker(title: "Three impacts", selection: $gestures.tripleImpactAction)
            }
            .padding(16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Calendar", systemImage: "calendar")
                        .font(.headline)
                    Spacer()
                    Text(calendar.accessState.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(calendar.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let nextEvent = calendar.nextEvent {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(nextEvent.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("\(nextEvent.relativeStart) · \(nextEvent.startDate.formatted(date: .omitted, time: .shortened)) · \(nextEvent.calendarTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(calendar.accessButtonLabel) {
                        calendar.requestAccessAndRefresh()
                    }
                    .buttonStyle(.bordered)
                    .disabled(calendar.isRequestingAccess)

                    if calendar.nextEvent?.hasLink == true {
                        Button("Open meeting link") {
                            calendar.openNextEventLink()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Pomodoro", systemImage: "timer")
                        .font(.headline)
                    Spacer()
                    Text(assistant.pomodoroPhase.title)
                        .foregroundStyle(.secondary)
                }

                Text(assistant.pomodoroTimeLabel)
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .monospacedDigit()

                Text(assistant.lastAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(assistant.pomodoroButtonLabel) {
                        assistant.togglePomodoro()
                    }
                    .buttonStyle(.bordered)

                    Button("Reset") {
                        assistant.resetPomodoro()
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Text("Impacts: \(assistant.impactCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                    Label("Experimental AppleSPUHIDDevice reader", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                Button(notch.isVisible ? "Hide notch widget" : "Show notch widget") {
                    notch.toggle()
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("v0.1.0")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(32)
        .frame(minWidth: 520, minHeight: 300)
        .onAppear {
            sensor.startIfNeeded()
            calendar.prepare()
        }
    }
}

private struct ImpactActionPicker: View {
    let title: String
    @Binding var selection: ImpactAction

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 110, alignment: .leading)
            Picker(title, selection: $selection) {
                ForEach(ImpactAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

private struct MenuBarView: View {
    @EnvironmentObject private var sensor: SensorViewModel
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var calendar: CalendarViewModel
    @EnvironmentObject private var notch: NotchWidgetController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sieghart", systemImage: "sparkles")
                .font(.headline)
            Text(sensor.status)
                .foregroundStyle(.secondary)
            Label("Pomodoro: \(assistant.pomodoroTimeLabel)", systemImage: "timer")
            Text(assistant.lastAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Label("Calendar", systemImage: "calendar")
                .font(.headline)
            Text(calendar.nextEvent.map { "\($0.relativeStart): \($0.title)" } ?? calendar.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button(sensor.isRunning ? "Pause sensor" : "Resume sensor") {
                sensor.toggle()
            }
            Button(assistant.pomodoroButtonLabel) {
                assistant.togglePomodoro()
            }
            Button(calendar.accessButtonLabel) {
                calendar.requestAccessAndRefresh()
            }
            if calendar.nextEvent?.hasLink == true {
                Button("Open meeting link") {
                    calendar.openNextEventLink()
                }
            }
            Button(notch.isVisible ? "Hide notch widget" : "Show notch widget") {
                notch.toggle()
            }
            Button("Open Sieghart") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .onAppear {
            sensor.startIfNeeded()
            calendar.prepare()
        }
    }
}
