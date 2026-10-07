import SwiftUI

private enum AudioPage: String, CaseIterable { case mixer = "Mixer", devices = "Devices", microphone = "Microphone" }
struct AudioControlsView: View {
    @EnvironmentObject private var audio: AudioController
    @Environment(\.islandPreview) private var preview
    @State private var page: AudioPage = .mixer
    @State private var unmutedGains: [String: Float] = [:]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                deviceMenu(input: false)
                Spacer()
                HStack(spacing: 14) {
                    ForEach(AudioPage.allCases, id: \.self) { choice in
                        Button(choice.rawValue) { page = choice }.buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(page == choice ? .white : CompanionStyle.muted)
                            .padding(.vertical, 7).overlay(alignment: .bottom) { if page == choice { Capsule().fill(CompanionStyle.accent).frame(height: 2) } }
                    }
                }
            }
            switch page {
            case .mixer: mixer
            case .devices:
                VStack(alignment: .leading, spacing: 20) {
                    Label("Output", systemImage: "speaker.wave.2").font(.headline)
                    deviceMenu(input: false)
                    Divider()
                    Label("Input", systemImage: "mic").font(.headline)
                    deviceMenu(input: true)
                    Text("Changes the Mac's default audio device.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }.frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            case .microphone:
                HStack(spacing: 30) {
                    volumeColumn("Input", symbol: "mic", value: audio.state.inputVolume, height: compact ? 96 : 160) { audio.setVolume($0, input: true) }
                    VStack(alignment: .leading, spacing: 16) {
                        deviceMenu(input: true)
                        if let muted = audio.state.inputMuted {
                            Button(muted ? "Unmute microphone" : "Mute microphone") { audio.muteInput(!muted) }.buttonStyle(CompanionButtonStyle(primary: muted))
                        } else { Text("This device doesn't provide a hardware mute control.").font(.caption).foregroundStyle(CompanionStyle.muted) }
                        Text("No microphone recording. These are device controls.").font(.caption).foregroundStyle(CompanionStyle.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error = audio.error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).lineLimit(3).help(error) }
        }.foregroundStyle(.white)
            .onAppear { if !preview { audio.observe() } }
            .onDisappear { if !preview { audio.stopObserving() } }
    }
    private var mixer: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 24) {
                volumeColumn("Master", symbol: "speaker.wave.2", value: audio.state.outputVolume, height: compact ? 96 : 160) { audio.setVolume($0) }
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: compact ? 161 : 225)
                Group {
                    if preview { applicationColumns }
                    else { ScrollView(.horizontal) { applicationColumns }.scrollIndicators(.hidden) }
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: compact ? 191 : 255)

            }
            HStack(spacing: 12) {
                Button(audio.perAppEnabled ? "Turn off app mixer" : "Enable app mixer") { if audio.perAppEnabled { audio.disableApplications() } else { audio.enableApplications() } }
                    .buttonStyle(CompanionButtonStyle(primary: !audio.perAppEnabled)).font(.caption)
                Text(audio.perAppEnabled ? "Apps connected to audio. Adjust a slider to apply a mix on this output." : "macOS asks to allow system audio when enabling saved mixes or first adjusting an app. Audio isn't saved.")
                    .font(.caption2).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var applicationColumns: some View {
        HStack(alignment: .top, spacing: 26) {
            if audio.state.apps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your audio apps appear here.").font(.headline)
                    Text("Play audio on this output to adjust an app separately.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }.frame(minWidth: 210, minHeight: compact ? 130 : 185, alignment: .center)
            }
            ForEach(audio.state.apps) { app in
                VStack(spacing: 12) {
                    if let icon = AudioAppIdentity.icon(for: app) { Image(nsImage: icon).resizable().scaledToFit().frame(width: 25, height: 25) }
                    else { Image(systemName: "waveform").font(.system(size: 24)).frame(height: 25) }
                    let gain = audio.routedApps.contains(app.id) ? audio.gains[app.id] ?? 1 : 1
                    VerticalAudioSlider(value: gain, height: compact ? 96 : 160, enabled: audio.perAppEnabled) { audio.setGain($0, app: app) }
                        .accessibilityLabel("\(app.name) volume")
                    HStack(spacing: 6) {
                        Text("\(Int(gain * 100))%").font(.caption.weight(.medium)).monospacedDigit()
                        Button {
                            if gain > 0 { unmutedGains[app.id] = gain; audio.setGain(0, app: app) }
                            else { audio.setGain(unmutedGains[app.id] ?? 1, app: app) }
                        } label: { Image(systemName: gain == 0 ? "speaker.slash" : "speaker.wave.2") }.buttonStyle(.plain).disabled(!audio.perAppEnabled).accessibilityLabel(gain == 0 ? "Unmute \(app.name)" : "Mute \(app.name)")
                    }.foregroundStyle(CompanionStyle.muted)
                    Text(app.name).font(.caption2).lineLimit(1).frame(width: 85).help(app.name + (app.isPlaying ? " · Playing" : " · Connected, currently silent"))
                }.frame(width: 85)
            }
        }.padding(.horizontal, 2)
    }
    private func volumeColumn(_ title: String, symbol: String, value: Float?, height: CGFloat, action: @escaping (Float) -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 23)).frame(height: 25)
            VerticalAudioSlider(value: value ?? 0, height: height, enabled: value != nil, onChange: action).accessibilityLabel("\(title) volume")
            Text(value.map { "\(Int($0 * 100))%" } ?? "Fixed").font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(CompanionStyle.muted)
            Text(title).font(.caption2)
        }.frame(width: 65)
    }
    private func deviceMenu(input: Bool) -> some View {
        let id = input ? audio.state.input : audio.state.output
        let current = audio.state.devices.first(where: { $0.id == id })
        let name = current?.name ?? "No \(input ? "input" : "output") device"
        return Group {
            if preview { Label(name + " ⌄", systemImage: current?.symbol ?? "speaker.wave.2").font(.callout.weight(.semibold)).lineLimit(1) }
            else {
                Menu {
                    ForEach(audio.state.devices.filter { input ? $0.inputChannels > 0 : $0.outputChannels > 0 }) { device in
                        Button { audio.selectDevice(device.id, input: input) } label: { Label(device.name + (device.id == id ? " ✓" : ""), systemImage: device.symbol) }
                    }
                } label: { Label(name, systemImage: current?.symbol ?? "speaker.wave.2").font(.callout.weight(.semibold)).lineLimit(1) }.menuStyle(.borderlessButton).accessibilityLabel(input ? "Input device" : "Output device").accessibilityValue(name)
            }
        }
    }
}
struct VerticalAudioSlider: View {
    let value: Float
    let height: CGFloat
    var enabled = true
    var onChange: (Float) -> Void
    var body: some View {
        Capsule().fill(.white.opacity(0.12))
            .overlay(alignment: .bottom) { Rectangle().fill(enabled ? .white.opacity(0.95) : .white.opacity(0.18)).frame(height: height * CGFloat(value)) }
            .frame(width: 36, height: height).clipShape(Capsule()).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in if enabled { onChange(Float(min(1, max(0, 1 - event.location.y / height)))) } })
            .accessibilityElement(children: .ignore).accessibilityValue(enabled ? "\(Int(value * 100)) percent" : "Unavailable")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                switch direction { case .increment: onChange(min(1, value + 0.05)); case .decrement: onChange(max(0, value - 0.05)); @unknown default: break }
            }
    }
}
