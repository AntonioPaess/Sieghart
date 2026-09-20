import SwiftUI

@main
struct SieghartApp: App {
    @StateObject private var sensor = SensorViewModel()

    var body: some Scene {
        WindowGroup("Sieghart") {
            ContentView()
                .environmentObject(sensor)
        }

        MenuBarExtra("Sieghart", systemImage: "sparkles") {
            MenuBarView()
                .environmentObject(sensor)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct ContentView: View {
    @EnvironmentObject private var sensor: SensorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sieghart")
                        .font(.largeTitle.weight(.semibold))
                    Text("Seu parceiro de contexto para o Mac")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("O núcleo do projeto começa aqui.")
                .font(.title3)
            Text("Primeiro teste: transformar um impacto físico em uma ação útil.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label(sensor.status, systemImage: sensor.isRunning ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg")
                    .foregroundStyle(sensor.isRunning ? .green : .secondary)

                if let sample = sensor.lastSample {
                    Text("Aceleração: x \(sample.x.formatted(.number.precision(.fractionLength(2))))g · y \(sample.y.formatted(.number.precision(.fractionLength(2))))g · z \(sample.z.formatted(.number.precision(.fractionLength(2))))g")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let impact = sensor.lastImpact {
                    Text("Último impacto: \(impact.timestamp.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(sensor.isRunning ? "Parar sensor" : "Iniciar sensor") {
                    sensor.toggle()
                }
                .buttonStyle(.borderedProminent)
            }

            HStack {
                Label("Leitor experimental AppleSPUHIDDevice", systemImage: "exclamationmark.triangle")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sieghart", systemImage: "sparkles")
                .font(.headline)
            Text(sensor.status)
                .foregroundStyle(.secondary)
            Divider()
            Button(sensor.isRunning ? "Parar sensor" : "Iniciar sensor") {
                sensor.toggle()
            }
            Button("Abrir Sieghart") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Button("Sair") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
    }
}
