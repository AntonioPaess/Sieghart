import AppKit
import SwiftUI
import CoreAudio
@main struct WorkspacePreview {
    @MainActor static func save<V: View>(_ content: V, path: String) throws {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .dark)); renderer.scale = 2
        guard let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw NSError(domain: "Preview", code: 1) }
        try png.write(to: URL(fileURLWithPath: path))
    }
    @MainActor static func main() async throws {
        AIProviderResources.bundle = Bundle(path: "/private/tmp/sieghart-simple-build/Build/Products/Debug/Sieghart.app")!
        let suite = "Sieghart.WorkspacePreview.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CompanionPreferences(defaults: defaults); preferences.avatar = .paperPal; preferences.onboardingComplete = true; preferences.characterMotion = false
        let now = Date(), calendar = Calendar.current
        let data = Data("{\"rateLimitsByLimitId\":{\"codex\":{\"limitId\":\"codex\",\"planType\":\"plus\",\"primary\":{\"usedPercent\":36,\"windowDurationMins\":300,\"resetsAt\":\(now.addingTimeInterval(3600).timeIntervalSince1970)},\"secondary\":{\"usedPercent\":33,\"windowDurationMins\":10080,\"resetsAt\":\(now.addingTimeInterval(518400).timeIntervalSince1970)}}}}".utf8)
        let codex = CodexUsageModel(defaults: defaults, load: { try JSONDecoder().decode(CodexUsageResponse.self, from: data) }); codex.enabled = true; await codex.refresh()
        let start = calendar.startOfDay(for: now)
        var points: [AIUsagePoint] = []
        for hour in [9,10,12,13,14,17,18,20] {
            let date = start.addingTimeInterval(Double(hour) * 3600)
            let input = Int64(hour % 7 + 1) * 300000
            points.append(AIUsagePoint(id: "sample\(hour)", provider: .codex, date: date, model: hour.isMultiple(of: 2) ? "gpt-6.1-sol" : "gpt-6-sol", project: hour.isMultiple(of: 3) ? "Writing" : "Focus project", input: input, output: input / 10, cached: input * 9 / 10))
        }
        let work = AIWork(id: "example", provider: .codex, model: "gpt-6.1-sol", project: "Focus project", startedAt: now.addingTimeInterval(-3598), lastSeen: now, output: 118000)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let days = (0..<91).compactMap { index -> CodexAccountActivity.Day? in
            guard index % 4 != 0 else { return nil }
            let date = calendar.date(byAdding: .day, value: index - 90, to: start)!
            return CodexAccountActivity.Day(startDate: formatter.string(from: date), tokens: Int64(index % 11 + 1) * 1000000)
        }
        let account = CodexAccountActivity(summary: .init(lifetimeTokens: 800000000, peakDailyTokens: 11000000, currentStreakDays: 2), dailyUsageBuckets: days)
        let usage = AIUsageModel(defaults: defaults, initialAnalytics: AIAnalytics(points: points, work: [work], scannedFiles: 12), initialAccountActivity: account, initialPrices: PriceCatalog.bundled(file: URL(fileURLWithPath: "Sieghart/Sieghart/ModelTokenPrices.json")), read: { _ in nil })

        let assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let audio = AudioController(backend: PreviewAudio(), defaults: defaults); audio.refresh(); audio.enableApplications()
        for app in audio.state.apps { audio.setGain(app.id == "com.apple.Music" ? 0.7 : 1, app: app) }
        let notch = NotchWidgetController(assistant: assistant, preferences: preferences, audio: audio, managesWindows: false)
        let activation = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false)
        let sensor = SensorViewModel(reader: PreviewAccelerometer())
        let gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        notch.activation = activation; notch.codexUsage = codex; notch.aiUsage = usage
        for section in AppSection.allCases {
            let height: CGFloat = section == .appearance ? 990 : section == .activation ? 1000 : section == .aiLimits ? 1320 : 800
            let name = section == .aiLimits ? "ai" : section == .focus ? "timers" : section.rawValue.lowercased()
            let view = ContentView(initialSection: section, scrollable: false)
                .frame(width: 1050, height: height)
                .environmentObject(sensor).environmentObject(assistant).environmentObject(notch)
                .environmentObject(gestures).environmentObject(activation).environmentObject(preferences)
                .environmentObject(codex).environmentObject(usage).environmentObject(audio).environment(\.islandPreview, true)
            try save(view, path: "Sieghart/Design/Concepts/app-\(name)-preview.png")
        }
        try save(CompanionOnboardingView(scrollable: false).frame(width: 900, height: 720).environmentObject(codex).environmentObject(usage).environmentObject(preferences).environment(\.islandPreview, true), path: "Sieghart/Design/Concepts/onboarding-preview.png")
        notch.showIsland(); notch.setPointerInsideHoverZone(true)
        let compact = NotchWidgetView().environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(preferences).environmentObject(codex).environmentObject(usage).environmentObject(audio).environment(\.islandPreview, true)
        try save(VStack(spacing: 20) {
            Text("Compact island · Hover feedback without a selection outline").font(.caption).foregroundStyle(.black)
            compact
        }.padding(32).background(Color(white: 0.8)), path: "Sieghart/Design/Concepts/compact-hover-preview.png")
        func widget() -> some View {
            NotchWidgetView(scrollable: false).environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(preferences).environmentObject(codex).environmentObject(usage).environment(\.islandPreview, true)
        }
        for (name, show) in [("companion", notch.show), ("tools", notch.showTools), ("audio", notch.showAudio), ("avatars", notch.showAvatars), ("ai", notch.showAILimits)] {
            show()
            try save(widget().padding(30).background(Color(white: 0.3)), path: "Sieghart/Design/Concepts/island-\(name)-preview.png")
        }
        for mode in TimerToolMode.allCases {
            assistant.selectTimerMode(mode); notch.showTimer()
            try save(widget().padding(30).background(Color(white: 0.3)), path: "Sieghart/Design/Concepts/island-\(mode.rawValue)-preview.png")
        }
        for page in ["Companion", "Timers", "AI", "Audio", "Avatars"] {
            let view = MenuBarView(initialPage: page).environmentObject(assistant).environmentObject(notch).environmentObject(activation).environmentObject(preferences).environmentObject(codex).environmentObject(usage).environment(\.islandPreview, true)
            try save(view, path: "Sieghart/Design/Concepts/menu-\(page.lowercased())-preview.png")
        }
        try save(AIUsageView(initialHour: 14).environmentObject(preferences).environmentObject(codex).environmentObject(usage).environment(\.islandGlass, true).frame(width: 712).padding(28).background(Color(white: 0.07)), path: "Sieghart/Design/Concepts/ai-dashboard-detail-preview.png")
        print("Rendered six workspace pages, eight island panels, five menu tabs, onboarding and AI charts. Illustrative data only; no app window or hardware started.")
    }
}

private final class PreviewAccelerometer: AccelerometerProviding {
    var onSample: ((AccelerationSample) -> Void)?
    let isRunning = false
    func start() throws { fatalError("A preview must not activate sensors") }
    func stop() {}
}

@MainActor private final class PreviewAudio: AudioBackend {
    var value = AudioSnapshot(devices: [AudioDeviceInfo(id: 1, name: "AirPods Pro", uid: "fixture.out", inputChannels: 1, outputChannels: 2, transport: kAudioDeviceTransportTypeBluetooth), AudioDeviceInfo(id: 2, name: "MacBook Pro Microphone", uid: "fixture.in", inputChannels: 1, outputChannels: 0), AudioDeviceInfo(id: 3, name: "MacBook Pro Speakers", uid: "fixture.speakers", inputChannels: 0, outputChannels: 2)], apps: [AudioApplicationInfo(id: "com.apple.Music", name: "Music", processes: [10], pid: 0), AudioApplicationInfo(id: "com.apple.Safari", name: "Safari", processes: [11], pid: 0), AudioApplicationInfo(id: "com.openai.codex", name: "ChatGPT", processes: [12], pid: 0)], output: 1, input: 2, outputVolume: 0.63, inputVolume: 0.8, inputMuted: false)
    func snapshot() -> AudioSnapshot { value }
    func setVolume(_ volume: Float, device: UInt32, input: Bool) throws { if input { value.inputVolume = volume } else { value.outputVolume = volume } }
    func setDefault(_ device: UInt32, input: Bool) throws { if input { value.input = device } else { value.output = device } }
    func setInputMuted(_ muted: Bool, device: UInt32) throws { value.inputMuted = muted }
    func setApplication(_ app: AudioApplicationInfo, gain: Float, output: AudioDeviceInfo) throws {}
    func retainApplications(_ ids: Set<String>) {}
    func stopApplications() {}
}
