import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

private final class NoUtilitySensor: AccelerometerProviding {
    var onSample: ((AccelerationSample) -> Void)?
    var isRunning = false
    func start() throws { fatalError("No sensor in previews") }
    func stop() {}
}
@MainActor private final class PreviewSystem: SystemSampling {
    var iteration = 0
    func read() -> MonitorReading {
        iteration += 1
        var r = MonitorReading()
        r.counters = SystemCounters(time: Double(iteration) * 2, cpu: [UInt64(iteration * 12), UInt64(iteration * 12), UInt64(iteration * 76), 0], received: UInt64(iteration * 32_000), sent: UInt64(iteration * 64_000), diskRead: UInt64(iteration * 82_000), diskWritten: UInt64(iteration * 12_000), diskIOAvailable: true)
        r.sampledAt = Date(timeIntervalSince1970: 1_801_947_600 + Double(iteration) * 2)
        r.gpu = 0.15; r.memoryTotal = 16_000_000_000; r.memoryUsed = 12_000_000_000; r.memoryPressure = "Normal"
        r.battery = 0.86; r.batteryHealth = 0.95; r.onAC = false; r.watts = 18.2; r.thermalState = "Normal"
        r.disks = [MonitorDisk(id: "/", name: "Macintosh HD", total: 512_000_000_000, free: 47_000_000_000)]
        return r
    }
}
@MainActor private final class PreviewAwake: AwakeBackend {
    func context() -> AwakeContext { AwakeContext() }
    func acquire(display: Bool) throws -> UInt32 { fatalError("No assertion in previews") }
    func release(_ token: UInt32) { fatalError("No assertion in previews") }
}
@MainActor private final class PreviewDisplay: DisplayPowerBackend {
    func displays() -> [DisplayInfo] { [DisplayInfo(id: 1, name: "Built-in Liquid Retina", builtIn: true, brightness: 0.65, hdrHeadroom: 2)] }
    func brightness(_ value: Double, display: CGDirectDisplayID) throws { fatalError("No brightness writes") }
    func dim(_ value: Double, display: CGDirectDisplayID) throws { fatalError("No gamma writes") }
    func restore() {}
    func sleepDisplays() throws { fatalError("No sleep") }
    func connectedBluetooth() -> [String] { [] }
    func disconnectBluetooth(_ id: String) throws { fatalError("No Bluetooth") }
    func reconnectBluetooth(_ id: String) throws { fatalError("No Bluetooth") }
}
@main struct UtilityPreview {
    @MainActor static func png<V: View>(_ view: V, _ name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.islandPreview, true)); renderer.scale = 2
        guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: URL(fileURLWithPath: "Sieghart/Design/Concepts/\(name).png"))
    }
    @MainActor static func main() async throws {
        let suite = "Sieghart.UtilityPreview.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = CompanionPreferences(defaults: defaults); prefs.onboardingComplete = true; prefs.avatar = .paperPal; prefs.appearance = .dark
        let monitor = SystemMonitor(backend: PreviewSystem()); for _ in 0..<30 { monitor.refresh() }
        let awake = KeepAwakeController(backend: PreviewAwake(), defaults: defaults)
        let display = DisplayPowerController(backend: PreviewDisplay(), defaults: defaults); display.refresh()
        let assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let notch = NotchWidgetController(assistant: assistant, preferences: prefs, monitor: monitor, keepAwake: awake, displayPower: display, managesWindows: false)
        let activation = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false)
        let sensor = SensorViewModel(reader: NoUtilitySensor()), gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        let codex = CodexUsageModel(defaults: defaults, load: { throw CocoaError(.fileReadNoSuchFile) })
        let ai = AIUsageModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
        for section in [AppSection.system, .keepAwake, .displayPower] {
            let view = ContentView(initialSection: section, scrollable: false).frame(width: 1020, height: 940)
                .environmentObject(prefs).environmentObject(assistant).environmentObject(notch).environmentObject(activation)
                .environmentObject(sensor).environmentObject(gestures).environmentObject(codex).environmentObject(ai)
            try png(view, "app-\(section == .system ? "system" : section == .keepAwake ? "keep-awake" : "display-power")-preview")
        }
        notch.showSystem()
        try png(NotchWidgetView(scrollable: false).environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(prefs).environmentObject(codex).environmentObject(ai), "island-system-preview")
        notch.showTools()
        try png(NotchWidgetView(scrollable: false).environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(prefs).environmentObject(codex).environmentObject(ai), "island-tools-sprint4-preview")
        let frames = 120
        guard let gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "Sieghart/Design/Concepts/companion-launch-greeting.gif") as CFURL, UTType.gif.identifier as CFString, frames, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<frames {
            let time = Double(frame) / 30
            let view = VStack(spacing: 10) {
                Text("A little hello.").font(.title3.weight(.semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(180)), count: 3), spacing: 8) {
                    ForEach(CompanionAvatar.allCases) { avatar in
                        VStack(spacing: 0) {
                            CompanionArrivalView(avatar: avatar, previewElapsed: time, size: 120).frame(width: 180, height: 180)
                            Text(avatar.name).font(.caption).foregroundStyle(CompanionStyle.muted)
                        }
                    }
                }
            }.padding(24).background(CompanionStyle.background).foregroundStyle(CompanionStyle.ink).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view); renderer.scale = 1.5
            guard let cg = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(gif, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 30]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
        print("Rendered production system/awake/display app pages, system island and 120-frame native greeting. All readings are fixtures; no window or device action.")
    }
}
