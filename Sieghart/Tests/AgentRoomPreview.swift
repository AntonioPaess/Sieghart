import AppKit
import SwiftUI

@MainActor private final class RoomPreviewBackend: CodingAgentServing {
    let provider = AIProvider.codex
    var connected = false
    var onEvent: ((CodingAgentEvent) -> Void)?
    var values: [CodingSession] = []
    func connect() { connected = true }
    func disconnect() { connected = false }
    func sessions() -> [CodingSession] { values }
    func messages(in session: CodingSession) -> [CodingMessage] { [] }
    func create(in directory: String) -> CodingSession { values[0] }
    func send(_ text: String, to session: CodingSession) {}
    func interrupt(_ session: CodingSession) {}
    func respond(to approval: CodingApproval, allow: Bool, answers: [String: String]) {}
}
@main struct AgentRoomPreview {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: "Sieghart/Design/Validation/ada-room")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        AIProviderResources.bundle = Bundle(path: CommandLine.arguments.dropFirst().first ?? "/private/tmp/sieghart-s5-final/Build/Products/Debug/Sieghart.app")!
        let suite = "sieg.room.preview.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RoomPreviewBackend(), model = AgentRoomViewModel(services: [.codex: backend])
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
        notch.showAgentRoom(); try render(island(), "disconnected-widget")
        backend.values = [CodingSession(provider: .codex, providerID: "fixture", title: "Voice-command parser", directory: "/Preview/Sieg", state: .working, turnID: "fixture-turn", managed: true),
                          CodingSession(provider: .codex, providerID: "fixture-2", title: "Calendar layout", directory: "/Preview/Sieg", state: .completed, managed: true)]
        await model.connect(.codex)
        backend.onEvent?(.message(sessionID: "codex:fixture", CodingMessage(id: "u", role: .user, text: "Review the pause detection in this fixture project. Explain the next step.")))
        backend.onEvent?(.delta(sessionID: "codex:fixture", messageID: "a", text: "I’m tracing capture → silence detection → command dispatch. The transcript stays visible while I check the transition.")); model.flushDeltas()
        model.page = .chat
        for _ in 0..<30 { await Task.yield() }
        try render(island(), "working-widget")
        var waiting = backend.values[0]; waiting.state = .waiting; backend.onEvent?(.session(waiting))
        backend.onEvent?(.approval(CodingApproval(id: "preview-approval", sessionID: waiting.id, title: "Run the targeted checks?", detail: "swift test --filter VoicePauseChecks · Preview fixture")))
        try render(island(), "waiting-widget")
        backend.onEvent?(.resolved(approvalID: "preview-approval"))
        var done = waiting; done.state = .completed; backend.onEvent?(.session(done))
        backend.onEvent?(.message(sessionID: done.id, CodingMessage(id: "a", role: .assistant, text: "Review complete. The next step is to validate the silence threshold with a recorded fixture before changing capture behavior.")))
        try render(island(), "completed-widget")
        var coordinating = done; coordinating.state = .working; backend.onEvent?(.session(coordinating))
        let names = ["Parser", "Calendar", "Tests", "Review", "Research"]
        let tasks = ["Inspect the command parser", "Check calendar permissions", "Run the focused checks", "Review the final changes", "Compare local runtime events"]
        for index in 0..<5 {
            backend.onEvent?(.worker(CodingWorker(id: "codex:child-\(index)", rootID: done.id, parentID: done.id,
                provider: .codex, name: names[index], task: tasks[index], state: [.working, .waiting, .blocked, .completed, .working][index],
                detail: index == 0 ? "Reading the voice parser" : "", live: true)))
        }
        for (index, title) in ["Clipboard workflow", "Local AI notes", "Onboarding polish"].enumerated() {
            backend.onEvent?(.session(CodingSession(provider: .codex, providerID: "room-\(index)", title: title,
                directory: "/Preview/Sieg", state: .ready)))
        }
        model.page = .room
        for _ in 0..<30 { await Task.yield() }
        try render(island(), "workroom-widget")
        model.page = .chat
        for _ in 0..<30 { await Task.yield() }
        try render(island(), "chat-with-agents")
        backend.onEvent?(.session(done))
        model.disconnect(.codex)
        model.draft = "Reconnect and continue this question."
        try render(island(), "disconnected-draft-widget")
        try render(AgentRoomView(model: model).padding(30).frame(width: 850).background(Color.black), "completed-workspace")
        notch.showTools()
        try render(island(), "tools-without-team")
        model.shutdown()
        print("Rendered 9 Ada-room fixtures offscreen; no app or provider launched.")
    }
}
