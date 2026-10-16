import AppKit
import SwiftUI

@MainActor private final class PreviewLocalEngine: LocalChatGenerating {
    var readiness: LocalChatReadiness = .available
    var configuration = AppleChatConfiguration()
    var modelName: String { configuration.label }
    func configure(_ configuration: AppleChatConfiguration) { self.configuration = configuration }
    var gate: CheckedContinuation<Void, Never>?
    func generate(history: [LocalChatMessage], persona: LocalChatPersona, onSnapshot: @escaping @MainActor (String) -> Void) async throws -> String {
        onSnapshot("Let’s make this smaller. First, find the function that handles the button tap.")
        await withCheckedContinuation { gate = $0 }
        return "Let’s make this smaller. First, find the function that handles the button tap."
    }
}
@main struct LocalChatPreview {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst(2).first ?? "Sieghart/Design/Validation/ada-apple27")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        AIProviderResources.bundle = Bundle(path: CommandLine.arguments.dropFirst().first ?? "/private/tmp/sieghart-s5-room-gallery/Build/Products/Debug/Sieghart.app")!
        let suite = "sieg.local.preview.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = PreviewLocalEngine(), local = LocalChatViewModel(generator: engine)
        let model = AgentRoomViewModel(services: [:], localChat: local)
        let preferences = CompanionPreferences(defaults: defaults); preferences.onboardingComplete = true
        let assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let notch = NotchWidgetViewModel(assistant: assistant, preferences: preferences, calendar: IsolatedCalendarFixture.make(defaults: defaults), agentRoom: model, managesWindows: false)
        let activation = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false)
        let codex = CodexUsageViewModel(defaults: defaults, load: { throw CocoaError(.fileReadNoSuchFile) })
        let usage = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
        func render<V: View>(_ view: V, _ name: String) throws {
            let renderer = ImageRenderer(content: view.environment(\.islandPreview, true).environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: output.appendingPathComponent(name + ".png"))
        }
        func island() -> some View {
            NotchWidgetView(scrollable: false).environmentObject(notch).environmentObject(assistant).environmentObject(activation)
                .environmentObject(preferences).environmentObject(codex).environmentObject(usage).padding(36).background(Color(white: 0.16))
        }
        await local.prepare(); notch.showAgentRoom()
        try render(island(), "empty-rooms")
        let first = await local.create()!; model.page = .chat
        for _ in 0..<100 { if notch.geometry.bodyHeight == 404 { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(notch.geometry.bodyHeight == 404)
        try render(island(), "new-chat")
        local.draft = "I’m stuck wiring up this button. Where should I start?"
        local.send(to: first)
        for _ in 0..<100 { if engine.gate != nil { break }; await Task.yield() }
        try await Task.sleep(for: .milliseconds(90))
        try render(island(), "replying-chat")
        engine.gate?.resume(); engine.gate = nil
        for _ in 0..<100 { if local.generatingID == nil { break }; await Task.yield() }
        try render(island(), "completed-chat")
        engine.readiness = AppleChatEligibility.prerequisite(for: .privateCloudThinking, macOSMajor: 26, hasPCCEntitlement: false)!
        await local.prepare(); local.draft = "My draft stays here."
        try render(island(), "unavailable-chat")
        try render(AdaChatSettingsView(chat: local), "ada-settings-requires-macos27")
        try render(AdaGitHubConnectionView(model: local.github).background(CompanionStyle.background), "github-connection")
        engine.readiness = .available; await local.prepare()
        for _ in 0..<4 { _ = await local.create() }
        model.page = .room
        for _ in 0..<100 { if notch.geometry.bodyHeight == 450 { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(notch.geometry.bodyHeight == 450)
        try render(island(), "local-rooms")
        local.select(first); model.page = .chat
        try render(AgentRoomView(model: model, observesActivity: false).padding(30).frame(width: 850).background(Color.black), "local-workspace")
        local.configure(mode: .onDevice)
        try render(AgentRoomView(model: model, observesActivity: false).padding(30).frame(width: 850).background(Color.black), "offline-workspace")
        model.shutdown()
        print("Rendered 10 Apple 27 agent chat fixtures offscreen. No app, model, provider, Keychain or project access.")
    }
}
