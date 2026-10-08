import SwiftUI

@main
struct SieghartApp: App {
    @NSApplicationDelegateAdaptor(ResidentAppDelegate.self) private var appDelegate
    @StateObject private var sensor: SensorViewModel
    @StateObject private var assistant: AssistantViewModel
    @StateObject private var notch: NotchWidgetViewModel
    @StateObject private var gestures: ImpactGestureCoordinator
    @StateObject private var activation: ActivationController
    @StateObject private var preferences: CompanionPreferences
    @StateObject private var codexUsage: CodexUsageViewModel
    @StateObject private var aiUsage: AIUsageViewModel

    init() {
        let preferences = CompanionPreferences()
        let codexUsage = CodexUsageViewModel()
        let aiUsage = AIUsageViewModel()
        let assistant = AssistantViewModel()
        let sensor = SensorViewModel()
        let notch = NotchWidgetViewModel(assistant: assistant, preferences: preferences)
        let gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        let activation = ActivationController(assistant: assistant, notch: notch)
        notch.activation = activation
        notch.codexUsage = codexUsage
        notch.aiUsage = aiUsage
        aiUsage.startMonitoring(codex: codexUsage)
        notch.observeAIActivity()
        notch.restoreSessionPresence()
        notch.clipboard.start()
        notch.middleClick.start()
        sensor.onImpact = { impact in
            guard preferences.impactsEnabled else { return }
            assistant.registerImpact(impact)
            gestures.receive(impact)
        }
        if preferences.impactsEnabled { sensor.startIfNeeded() }
        _sensor = StateObject(wrappedValue: sensor)
        _assistant = StateObject(wrappedValue: assistant)
        _notch = StateObject(wrappedValue: notch)
        _gestures = StateObject(wrappedValue: gestures)
        _activation = StateObject(wrappedValue: activation)
        _preferences = StateObject(wrappedValue: preferences)
        _codexUsage = StateObject(wrappedValue: codexUsage)
        _aiUsage = StateObject(wrappedValue: aiUsage)
        appDelegate.activation = activation
        appDelegate.clipboard = notch.clipboard
        appDelegate.onLaunch = {
            notch.startUtilities()
            if preferences.onboardingComplete && preferences.launchGreeting { notch.showWelcome() }
        }
        appDelegate.onTerminate = { notch.stopUtilities() }
    }

    var body: some Scene {
        WindowGroup("Sieghart", id: "main") {
            ContentView()
                .environmentObject(sensor)
                .environmentObject(assistant)
                .environmentObject(notch)
                .environmentObject(gestures)
                .environmentObject(activation)
                .environmentObject(preferences)
                .environmentObject(codexUsage)
                .environmentObject(aiUsage)
                .environmentObject(notch.audio)
        }
        .defaultSize(width: 1000, height: 680)
        .windowToolbarStyle(.unifiedCompact)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(assistant)
                .environmentObject(notch)
                .environmentObject(activation)
                .environmentObject(preferences)
                .environmentObject(codexUsage)
                .environmentObject(aiUsage)
                .environmentObject(notch.audio)
        } label: {
            if let image = CompanionArtwork.menuBarImage(for: preferences.avatar) {
                Image(nsImage: image).accessibilityLabel("Sieghart — \(preferences.avatar.name)")
            } else {
                Image(systemName: "face.smiling").accessibilityLabel("Sieghart")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
