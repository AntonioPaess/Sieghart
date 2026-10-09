import SwiftUI

private enum MonitorPage: String, CaseIterable { case overview = "Overview", disks = "Disks", history = "History" }
struct SystemMonitorView: View {
    @ObservedObject var monitor: SystemMonitorViewModel
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
