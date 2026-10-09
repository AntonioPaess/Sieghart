import AppKit
import SwiftUI

private final class NoEditorSensor: AccelerometerProviding {
    var onSample: ((AccelerationSample) -> Void)?
    let isRunning = false
    func start() throws { fatalError("No sensor in a design preview") }
    func stop() {}
}

@main struct IslandEditorPreview {
    @MainActor static func main() throws {
        let suite = "Sieghart.IslandEditorPreview.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CompanionPreferences(defaults: defaults)
        preferences.onboardingComplete = true; preferences.avatar = .paperPal; preferences.characterMotion = false
        preferences.setRail(.none, at: 2); preferences.setRail(.none, at: 5)
        let assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let notch = NotchWidgetViewModel(assistant: assistant, preferences: preferences, managesWindows: false)
        let activation = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false)
        let sensor = SensorViewModel(reader: NoEditorSensor())
        let gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        let codex = CodexUsageViewModel(defaults: defaults, load: { throw CocoaError(.fileReadNoSuchFile) })
        let usage = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
        for appearance in [AppAppearance.dark, .light] {
            preferences.appearance = appearance
            let view = ContentView(initialSection: .dynamicIsland, scrollable: false)
                .frame(width: 1050, height: 1080)
                .environmentObject(preferences).environmentObject(assistant).environmentObject(notch)
                .environmentObject(activation).environmentObject(sensor).environmentObject(gestures)
                .environmentObject(codex).environmentObject(usage).environment(\.islandPreview, true)
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, appearance == .dark ? .dark : .light)); renderer.scale = 2
            guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: URL(fileURLWithPath: "Sieghart/Design/Concepts/app-island-editor-\(appearance.rawValue.lowercased())-preview.png"))
        }
        print("Rendered visual island editor in dark/light. No app window, clipboard, shortcuts or hardware started.")
    }
}
