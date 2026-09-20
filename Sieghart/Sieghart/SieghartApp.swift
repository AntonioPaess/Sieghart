import SwiftUI

@main
struct SieghartApp: App {
    @StateObject private var sensor: SensorViewModel
    @StateObject private var assistant: AssistantViewModel

    init() {
        let assistant = AssistantViewModel()
        let sensor = SensorViewModel()
        sensor.onImpact = { impact in
            assistant.handle(impact: impact)
        }

        _sensor = StateObject(wrappedValue: sensor)
        _assistant = StateObject(wrappedValue: assistant)
    }

    var body: some Scene {
        WindowGroup("Sieghart") {
            ContentView()
                .environmentObject(sensor)
                .environmentObject(assistant)
        }

        MenuBarExtra("Sieghart", systemImage: "sparkles") {
            MenuBarView()
                .environmentObject(sensor)
                .environmentObject(assistant)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct ContentView: View {
    @EnvironmentObject private var sensor: SensorViewModel
    @EnvironmentObject private var assistant: AssistantViewModel

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

                Button(sensor.isRunning ? "Stop sensor" : "Start sensor") {
                    sensor.toggle()
                }
                .buttonStyle(.borderedProminent)
            }

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
                Text("v0.1.0")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(32)
        .frame(minWidth: 520, minHeight: 300)
    }
}

private struct MenuBarView: View {
    @EnvironmentObject private var sensor: SensorViewModel
    @EnvironmentObject private var assistant: AssistantViewModel

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
            Button(sensor.isRunning ? "Stop sensor" : "Start sensor") {
                sensor.toggle()
            }
            Button(assistant.pomodoroButtonLabel) {
                assistant.togglePomodoro()
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
    }
}
