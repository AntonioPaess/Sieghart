import SwiftUI

struct DisplayPowerView: View {
    @ObservedObject var controller: DisplayPowerViewModel
    @State private var page = 0
    @Environment(\.islandPreview) private var preview
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UtilityTabs(choices: [0, 1], selection: $page, title: { $0 == 0 ? "Displays" : "Sleep & playback" })
            if page == 0 {
                ForEach(controller.displays) { display in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Label(display.name, systemImage: display.builtIn ? "laptopcomputer" : "display").font(.headline); Spacer(); Text(display.builtIn ? "Built in" : "External").font(.caption).foregroundStyle(CompanionStyle.muted) }
                        if let brightness = display.brightness {
                            HStack { Text("Brightness"); Group { if preview { UtilityMeter(value: brightness) } else { Slider(value: Binding(get: { controller.displays.first { $0.id == display.id }?.brightness ?? brightness }, set: { controller.setBrightness($0, display: display) }), in: 0...1) } }; Text("\(Int(brightness * 100))%").monospacedDigit().frame(width: 40) }
                        } else { Text("Hardware brightness unavailable · software dimming is available when supported").font(.caption).foregroundStyle(CompanionStyle.muted) }
                        HStack { Text("Dimming"); Group { if preview { UtilityMeter(value: display.dimming) } else { Slider(value: Binding(get: { controller.displays.first { $0.id == display.id }?.dimming ?? 1 }, set: { controller.setDimming($0, display: display) }), in: 0.2...1) } }; Text("\(Int(display.dimming * 100))%").monospacedDigit().frame(width: 40) }
                        if display.hdrHeadroom > 1 { Text(String(format: "HDR headroom %.1f× · HDR content can use this; desktop brightness stays within the display's controls.", display.hdrHeadroom)).font(.caption).foregroundStyle(CompanionStyle.muted) }
                    }.font(.callout).padding(16).modifier(IslandControlSurface())
                }
                HStack { Button("Restore dimming") { controller.restoreBrightness() }; Spacer(); Button("Sleep displays") { controller.sleepDisplays() } }.buttonStyle(CompanionButtonStyle(compact: true))
            } else {
                UtilityToggle(title: "Disconnect Bluetooth devices during sleep", isOn: $controller.disconnectBluetoothOnSleep).toggleStyle(WorkspaceSwitchStyle())
                Text("Reconnect only devices Sieghart disconnected. Bluetooth stays on; keyboards and pointing devices may be disconnected too.").font(.caption).foregroundStyle(CompanionStyle.muted)
                Text(controller.bluetoothStatus).font(.caption)
                Divider()
                UtilityToggle(title: "Block Music launches after a playback key", isOn: $controller.blockMusicAfterPlayKey).toggleStyle(WorkspaceSwitchStyle())
                Text("Applies only to a new Music launch within two seconds of a detected playback key. Existing Music sessions are left running.").font(.caption).foregroundStyle(CompanionStyle.muted)
                if controller.blockMusicAfterPlayKey && !controller.musicBlockerReady { Button("Allow playback-key detection") { controller.allowMusicBlocker() }.buttonStyle(CompanionButtonStyle(compact: true)) }
            }
            if let error = controller.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onAppear { if !preview { controller.refresh() } }
    }
}
