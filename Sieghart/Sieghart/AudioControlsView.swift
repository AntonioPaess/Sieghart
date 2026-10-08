import SwiftUI

private enum AudioPage: String, CaseIterable { case mixer = "Mixer", devices = "Devices", microphone = "Microphone" }
struct AudioControlsView: View {
    @EnvironmentObject private var audio: AudioController
    @Environment(\.islandPreview) private var preview
    @State private var page: AudioPage = .mixer
    @State private var unmutedGains: [String: Float] = [:]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            ViewThatFits(in: .horizontal) {
                HStack { deviceMenu(input: false); Spacer(); audioTabs }
                VStack(alignment: .leading, spacing: 8) { deviceMenu(input: false); audioTabs }
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
                    UtilityToggle(title: "Use preferred devices when they connect", isOn: $audio.automaticDevices).toggleStyle(WorkspaceSwitchStyle())
                    Text("Your manual choice stays until devices connect or disconnect. Preferences use device identity, including AirPods.").font(.caption).foregroundStyle(CompanionStyle.muted)
                    priorityList(input: false)
                    priorityList(input: true)
                }.frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            case .microphone:
                HStack(spacing: 30) {
                    volumeColumn("Input", symbol: "mic", value: audio.state.inputVolume, height: compact ? 80 : 160) { audio.setVolume($0, input: true) }
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
        }.foregroundStyle(CompanionStyle.ink)
            .onAppear { if !preview { audio.observe() } }
            .onDisappear { if !preview { audio.stopObserving() } }
    }
    private var audioTabs: some View {
        HStack(spacing: 14) {
            ForEach(AudioPage.allCases, id: \.self) { choice in
                Button(choice.rawValue) { page = choice }.buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(page == choice ? CompanionStyle.ink : CompanionStyle.muted)
                    .padding(.vertical, 7).overlay(alignment: .bottom) { if page == choice { Capsule().fill(CompanionStyle.accent).frame(height: 2) } }
            }
        }
    }
    private var mixer: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: compact ? 14 : 24) {
                volumeColumn("Master", symbol: "speaker.wave.2", value: audio.state.outputVolume, height: compact ? 80 : 160) { audio.setVolume($0) }
                Rectangle().fill(CompanionStyle.edge.opacity(0.1)).frame(width: 1, height: compact ? 145 : 225)
                Group {
                    if preview { GeometryReader { geometry in applicationColumns.frame(width: geometry.size.width, alignment: .leading).clipped() } }
                    else { ScrollView(.horizontal) { applicationColumns }.scrollIndicators(.hidden) }
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: compact ? 176 : 255)

            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button(audio.access == .requesting ? "Requesting access…" : audio.perAppEnabled ? "Turn off app mixer" : audio.access == .off ? "Enable app mixer" : "Retry app mixer") {
                        if audio.perAppEnabled { audio.disableApplications() }
                        else { Task { await audio.enableApplications() } }
                    }.buttonStyle(CompanionButtonStyle(primary: !audio.perAppEnabled, compact: compact)).disabled(audio.access == .requesting)
                    if audio.access == .requesting { ProgressView().controlSize(.small) }
                    if audio.access == .permissionRequired || audio.access == .failed || audio.perAppEnabled {
                        Button("Audio permission") { audio.openAudioPermissionSettings() }.buttonStyle(.plain).font(.caption)
                    }
                }
                Text(audio.perAppEnabled ? "Adjust an app below 100% to mix it on this output." : "Allow system audio in the macOS prompt. Audio stays local and isn't saved.")
                    .font(.caption2).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var applicationColumns: some View {
        HStack(alignment: .top, spacing: compact ? 18 : 26) {
            if audio.state.apps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your audio apps appear here.").font(.headline)
                    Text("Play audio on this output to adjust an app separately.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }.frame(minWidth: compact ? 200 : 210, minHeight: compact ? 130 : 185, alignment: .center)
            }
            ForEach(audio.visibleApps) { app in
                VStack(spacing: 12) {
                    HStack(spacing: 5) {
                        if let icon = AudioAppIdentity.icon(for: app) { Image(nsImage: icon).resizable().scaledToFit().frame(width: 25, height: 25) }
                        else { Image(systemName: "waveform").font(.system(size: 24)).frame(height: 25) }
                        Menu {
                            Button(audio.favoriteApps.contains(app.id) ? "Remove favorite" : "Favorite") { audio.toggleFavorite(app) }
                            Button("Move left") { audio.moveApp(app, direction: -1) }.disabled(!audio.canMoveApp(app, direction: -1))
                            Button("Move right") { audio.moveApp(app, direction: 1) }.disabled(!audio.canMoveApp(app, direction: 1))
                        } label: { Image(systemName: audio.favoriteApps.contains(app.id) ? "star.fill" : "ellipsis").font(.caption2) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("\(app.name) order and favorite")
                    }
                    let gain = audio.routedApps.contains(app.id) ? audio.gains[app.id] ?? 1 : 1
                    VerticalAudioSlider(value: gain, height: compact ? 80 : 160, enabled: audio.perAppEnabled && !app.processes.isEmpty) { audio.setGain($0, app: app) }
                        .accessibilityLabel("\(app.name) volume")
                    HStack(spacing: 6) {
                        Text(app.processes.isEmpty ? "Waiting" : "\(Int(gain * 100))%").font(.caption.weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        Button {
                            if gain > 0 { unmutedGains[app.id] = gain; audio.setGain(0, app: app) }
                            else { audio.setGain(unmutedGains[app.id] ?? 1, app: app) }
                        } label: { Image(systemName: gain == 0 ? "speaker.slash" : "speaker.wave.2") }.buttonStyle(.plain).disabled(!audio.perAppEnabled || app.processes.isEmpty).accessibilityLabel(gain == 0 ? "Unmute \(app.name)" : "Mute \(app.name)")
                    }.foregroundStyle(CompanionStyle.muted)
                    Text(app.name).font(.caption2).foregroundStyle(app.processes.isEmpty ? CompanionStyle.muted : CompanionStyle.ink).lineLimit(1).frame(width: compact ? 62 : 85).help(app.name + (app.isPlaying ? " · Playing" : app.processes.isEmpty ? " · Play audio to connect" : " · Connected, currently silent"))
                }.frame(width: compact ? 62 : 85)
            }
        }.padding(.horizontal, 2)
    }
    private func volumeColumn(_ title: String, symbol: String, value: Float?, height: CGFloat, action: @escaping (Float) -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 23)).frame(height: 25)
            VerticalAudioSlider(value: value ?? 0, height: height, enabled: value != nil, onChange: action).accessibilityLabel("\(title) volume")
            Text(value.map { "\(Int($0 * 100))%" } ?? "Fixed").font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(CompanionStyle.muted)
            Text(title).font(.caption2)
        }.frame(width: compact ? 48 : 65)
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
    private func priorityList(input: Bool) -> some View {
        let priority = input ? audio.inputPriority : audio.outputPriority
        let devices = audio.state.devices.filter { (input ? $0.inputChannels : $0.outputChannels) > 0 }.sorted { (priority.firstIndex(of: $0.uid) ?? 999) < (priority.firstIndex(of: $1.uid) ?? 999) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(input ? "Preferred microphones" : "Preferred outputs").font(.caption.weight(.semibold))
            ForEach(devices) { device in
                HStack {
                    Label(device.name, systemImage: device.symbol).font(.caption).lineLimit(1)
                    Spacer()
                    if let rank = priority.firstIndex(of: device.uid) { Text("\(rank + 1)").font(.caption).foregroundStyle(CompanionStyle.accentInk) }
                    Menu {
                        Button("Prefer / move up") { audio.preferDevice(device, input: input) }
                        Button("Move down") { audio.preferDevice(device, input: input, direction: 1) }
                        Button("Remove preference") { audio.removePriority(device, input: input) }.disabled(!priority.contains(device.uid))
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("\(device.name) priority")
                }
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
        Capsule().fill(CompanionStyle.edge.opacity(0.12))
            .overlay(alignment: .bottom) { Rectangle().fill(enabled ? CompanionStyle.edge.opacity(0.95) : CompanionStyle.edge.opacity(0.18)).frame(height: height * CGFloat(value)) }
            .frame(width: 36, height: height).clipShape(Capsule()).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in if enabled { onChange(Float(min(1, max(0, 1 - event.location.y / height)))) } })
            .accessibilityElement(children: .ignore).accessibilityValue(enabled ? "\(Int(value * 100)) percent" : "Unavailable")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                switch direction { case .increment: onChange(min(1, value + 0.05)); case .decrement: onChange(max(0, value - 0.05)); @unknown default: break }
            }
    }
}
