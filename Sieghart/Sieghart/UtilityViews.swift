import SwiftUI

private enum MonitorPage: String, CaseIterable { case overview = "Overview", disks = "Disks", history = "History" }
struct SystemMonitorView: View {
    @ObservedObject var monitor: SystemMonitor
    var compact = false
    @State private var page = MonitorPage.overview
    @Environment(\.islandPreview) private var preview
    private var reading: MonitorReading { monitor.reading }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UtilityTabs(choices: MonitorPage.allCases, selection: $page, title: { $0.rawValue })
            switch page {
            case .overview:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: compact ? 2 : 3), spacing: 12) {
                    metric("CPU", symbol: "cpu", value: percent(reading.cpu), progress: reading.cpu)
                    metric("GPU", symbol: "display", value: percent(reading.gpu), progress: reading.gpu)
                    metric("Memory", symbol: "memorychip", value: bytes(Double(reading.memoryUsed)), detail: "\(bytes(Double(reading.memoryTotal))) · \(reading.memoryPressure)", progress: reading.memoryTotal > 0 ? Double(reading.memoryUsed) / Double(reading.memoryTotal) : nil)
                        .help("Compressed \(bytes(Double(reading.compressedBytes))) · Cached \(bytes(Double(reading.cachedBytes))) · Swap \(reading.swapBytes.map { bytes(Double($0)) } ?? "Unavailable")")
                    metric("Network", symbol: "network", value: "↓ \(rate(reading.download))", detail: "↑ \(rate(reading.upload))")
                    metric("Battery", symbol: "battery.75percent", value: percent(reading.battery), detail: reading.battery == nil ? "No battery reported" : reading.charging ? "Charging" : reading.onAC ? "Power adapter" : "Battery power", progress: reading.battery)
                    metric("Power", symbol: "bolt", value: reading.watts.map { String(format: "%.1f W", $0) } ?? "Unavailable", detail: reading.batteryHealth.map { "Battery health \(percent($0))" } ?? "Battery draw, when reported")
                        .help("\(reading.batteryMinutes.map { "Estimated \($0) min" } ?? "No time estimate") · \(reading.batteryCycles.map { "\($0) cycles" } ?? "Cycles unavailable")")
                }
                Text("GPU, temperature and fan readings depend on your Mac. Unavailable readings are never estimated.").font(.caption).foregroundStyle(CompanionStyle.muted)
                Text("Thermal state: \(reading.thermalState)").font(.caption).foregroundStyle(CompanionStyle.muted)
            case .disks:
                if reading.disks.isEmpty { Text("No disk readings yet").foregroundStyle(CompanionStyle.muted) }
                ForEach(reading.disks) { disk in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Label(disk.name, systemImage: "internaldrive").font(.headline); Spacer(); Text("\(bytes(Double(disk.free))) free").monospacedDigit() }
                        UtilityMeter(value: Double(disk.total - disk.free) / Double(max(1, disk.total)))
                        Text("\(bytes(Double(disk.total))) capacity").font(.caption).foregroundStyle(CompanionStyle.muted)
                    }.padding(14).modifier(IslandControlSurface())
                }
                HStack { Label("Read \(rate(reading.diskReadRate))", systemImage: "arrow.down"); Spacer(); Text("Write \(rate(reading.diskWriteRate))") }.font(.caption).foregroundStyle(CompanionStyle.muted)
            case .history:
                Text("CPU · last two minutes").font(.headline)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(monitor.history.enumerated()), id: \.offset) { _, sample in
                        RoundedRectangle(cornerRadius: 2).fill(CompanionStyle.accent.opacity(sample.cpu == nil ? 0.15 : 0.9))
                            .frame(maxWidth: .infinity).frame(height: max(3, CGFloat(sample.cpu ?? 0) * 120))
                            .help("\(sample.sampledAt?.formatted(date: .omitted, time: .standard) ?? "") · CPU \(percent(sample.cpu)) · Memory \(bytes(Double(sample.memoryUsed))) · ↓ \(rate(sample.download)) · ↑ \(rate(sample.upload))")
                            .accessibilityLabel("CPU \(percent(sample.cpu)) at \(sample.sampledAt?.formatted(date: .omitted, time: .standard) ?? "unknown time")")
                    }
                }.frame(height: 124, alignment: .bottom)
                HStack { Text("2 minutes ago"); Spacer(); Text("Now · \(percent(reading.cpu))") }.font(.caption).foregroundStyle(CompanionStyle.muted)
                Text("Network since boot: ↓ \(bytes(Double(reading.counters.received))) · ↑ \(bytes(Double(reading.counters.sent)))").font(.caption)
                if !reading.localAddresses.isEmpty { Text("Local IP: \(reading.localAddresses.joined(separator: ", "))").font(.caption) }
                if !reading.peripherals.isEmpty { Text("USB: \(reading.peripherals.joined(separator: ", "))").font(.caption).foregroundStyle(CompanionStyle.muted) }
            }
            if let date = reading.sampledAt { Text("Updated \(date.formatted(date: .omitted, time: .standard)) · every 2 seconds").font(.caption).foregroundStyle(CompanionStyle.muted) }
        }.onAppear { if !preview { monitor.observe() } }.onDisappear { if !preview { monitor.stopObserving() } }
    }
    private func metric(_ title: String, symbol: String, value: String, detail: String? = nil, progress: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(CompanionStyle.muted)
            Text(value).font(.system(size: compact ? 21 : 28, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            if let progress { UtilityMeter(value: progress) }
            else { Color.clear.frame(height: 4) }
            Text(detail ?? " ").font(.system(size: 10)).foregroundStyle(CompanionStyle.muted).lineLimit(1)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).frame(height: 112).modifier(IslandControlSurface())
    }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0 * 100) } ?? "Unavailable" }
    private func bytes(_ value: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .decimal) }
    private func rate(_ value: Double?) -> String { value.map { bytes($0) + "/s" } ?? "Measuring…" }
}

struct KeepAwakeView: View {
    @ObservedObject var controller: KeepAwakeController
    var compact = false
    @State private var showsConditions = false
    @Environment(\.islandPreview) private var preview
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(controller.status, systemImage: controller.holding ? "cup.and.saucer.fill" : "moon.zzz").font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(controller.enabled ? "Stop" : "Start") { if controller.enabled { controller.stop() } else { controller.start() } }.buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
            }
            if let seconds = controller.remaining, controller.enabled { Text(Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))).monospacedDigit().font(.title2) }
            UtilityTabs(choices: AwakeMode.allCases, selection: $controller.request.mode, title: { $0.rawValue }).disabled(controller.enabled)
            switch controller.request.mode {
            case .duration:
                HStack { Text("Keep awake for"); Spacer(); Group { if preview { Text("\(controller.request.minutes) min ⌄").foregroundStyle(CompanionStyle.accentInk) } else { Picker("Duration", selection: $controller.request.minutes) { ForEach([5, 15, 30, 60, 120, 240, 480, 1440], id: \.self) { Text("\($0) min").tag($0) } }.labelsHidden().frame(width: 115) } } }.disabled(controller.enabled)
            case .until: DatePicker("Until", selection: $controller.request.until, displayedComponents: [.date, .hourAndMinute]).disabled(controller.enabled)
            case .indefinite: Text("Stays active until you stop it or quit Sieghart.").font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            UtilityToggle(title: "Keep display awake too", isOn: $controller.request.keepDisplay).toggleStyle(WorkspaceSwitchStyle())
            DisclosureGroup("Conditions & restoration", isExpanded: $showsConditions) {
                VStack(alignment: .leading, spacing: 12) {
                    UtilityToggle(title: "Only while connected to power", isOn: $controller.request.onlyOnAC)
                    UtilityToggle(title: "Only with an external display", isOn: $controller.request.externalDisplayOnly)
                    UtilityToggle(title: "Resume valid session on next launch", isOn: $controller.request.restoreOnLaunch)
                    Menu {
                        ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }, id: \.processIdentifier) { app in
                            Button {
                                guard let id = app.bundleIdentifier else { return }
                                if controller.request.applications.contains(id) { controller.request.applications.removeAll { $0 == id } } else { controller.request.applications.append(id) }
                            } label: { Label(app.localizedName ?? "App", systemImage: controller.request.applications.contains(app.bundleIdentifier ?? "") ? "checkmark" : "app") }
                        }
                        Divider(); Button("Any app") { controller.request.applications = [] }
                    } label: { Text(controller.request.applications.isEmpty ? "While any app is running" : "While selected apps run (\(controller.request.applications.count))") }
                    Text("Closing the lid still follows macOS hardware rules. For closed-lid work, use a supported docked setup with power and an external display.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }.padding(.top, 10).toggleStyle(WorkspaceSwitchStyle())
            }
            if let error = controller.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onChange(of: controller.request) { _, _ in controller.saveOptions() }
    }
}

struct DisplayPowerView: View {
    @ObservedObject var controller: DisplayPowerController
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

private struct UtilityMeter: View {
    var value: Double
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(CompanionStyle.edge.opacity(0.12))
                .overlay(alignment: .leading) { Capsule().fill(CompanionStyle.accent).frame(width: geometry.size.width * min(1, max(0, value))) }
        }.frame(height: 5).accessibilityHidden(true)
    }
}
private struct UtilityTabs<Choice: Hashable>: View {
    var choices: [Choice]
    @Binding var selection: Choice
    var title: (Choice) -> String
    var body: some View {
        HStack(spacing: 18) {
            ForEach(choices, id: \.self) { choice in
                Button { selection = choice } label: {
                    Text(title(choice)).font(.callout.weight(.semibold))
                        .foregroundStyle(selection == choice ? CompanionStyle.ink : CompanionStyle.muted)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { if selection == choice { Capsule().fill(CompanionStyle.accent).frame(height: 2) } }
                }.buttonStyle(.plain).accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

struct UtilityToggle: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(WorkspaceSwitchStyle())
        }
    }
}
