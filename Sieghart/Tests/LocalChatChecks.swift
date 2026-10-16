import Foundation

@MainActor private final class LocalEngineFixture: LocalChatGenerating {
    var readiness: LocalChatReadiness = .available
    var calls = 0
    var configuration = AppleChatConfiguration()
    func configure(_ configuration: AppleChatConfiguration) { self.configuration = configuration }
    var histories: [[LocalChatMessage]] = []
    var shouldFail = false, pause = false
    var gate: CheckedContinuation<Void, Never>?
    var snapshot: (@MainActor (String) -> Void)?
    func generate(history: [LocalChatMessage], persona: LocalChatPersona, onSnapshot: @escaping @MainActor (String) -> Void) async throws -> String {
        calls += 1; histories.append(history); snapshot = onSnapshot
        onSnapshot("A"); onSnapshot("A small step")
        if pause { await withCheckedContinuation { gate = $0 } }
        if shouldFail { throw LocalChatError.generationFailed("Fixture failure") }
        // Deliberately finish after cancellation as a misbehaving generator may.
        onSnapshot("A small step, together.")
        return "A small step, together."
    }
}

@main struct LocalChatChecks {
    @MainActor static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        preconditionFailure("Local chat fixture timed out")
    }
    @MainActor static func main() async throws {
        AppleChatEligibilityChecks.run()
        try await AdaGitHubChecks.run()
        try contextChecks()
        await configurationChecks()
        try await conversationChecks()
        try await storageChecks()
        print("PASS: local chat streaming, persistence, drafts, cancellation, isolation, bounds and unavailable-model states. No model inference or provider calls.")
    }
    @MainActor static func configurationChecks() async {
        let suite = "sieg.apple.configuration.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = LocalEngineFixture()
        let model = LocalChatViewModel(generator: engine, defaults: defaults)
        precondition(model.configuration.mode == .privateCloudThinking && model.configuration.reasoning == .deep)
        model.configure(mode: .onDevice, reasoning: .light)
        precondition(engine.configuration == model.configuration && engine.calls == 0)
        let restoredEngine = LocalEngineFixture(), restored = LocalChatViewModel(generator: restoredEngine, defaults: defaults)
        precondition(restored.configuration.mode == .onDevice && restored.configuration.reasoning == .light && restoredEngine.calls == 0)
        restored.configure(mode: .privateCloudThinking, reasoning: .deep)
        precondition(restored.configuration.mode.requiresNetwork && restoredEngine.configuration.reasoning == .deep)
    }
    static func contextChecks() throws {
        var messages = [LocalChatMessage(role: .system, text: "Untrusted old system text")]
        for index in 0..<10 {
            messages += [.init(role: .user, text: "Q\(index)"), .init(role: .assistant, text: "A\(index)")]
        }
        messages.append(.init(role: .user, text: "Now"))
        let context = try LocalChatContext.prepare(messages)
        precondition(context.past.count == 12 && context.past.first?.text == "Q4" && context.prompt.text == "Now")
        precondition(!context.past.contains { $0.role == .system })
        let large = try LocalChatContext.prepare([.init(role: .user, text: String(repeating: "x", count: 6_000)),
            .init(role: .assistant, text: String(repeating: "x", count: 6_000)), .init(role: .user, text: "Short")])
        precondition(large.past.isEmpty)
        do { _ = try LocalChatContext.prepare([.init(role: .user, text: String(repeating: "x", count: 8_001))]); preconditionFailure() }
        catch { precondition(error as? LocalChatError == .inputTooLong) }
    }
    @MainActor static func conversationChecks() async throws {
        let engine = LocalEngineFixture(), store = MemoryLocalChatStore()
        let model = LocalChatViewModel(generator: engine, store: store)
        let room = AgentRoomViewModel(services: [:], localChat: model)
        precondition(room.connected.isEmpty && room.sessions.isEmpty && engine.calls == 0)
        let a = await model.create()!, b = await model.create()!
        precondition(engine.calls == 0 && model.conversations.count == 2) // Creating never starts inference.
        model.select(a); model.draft = "Explain this excerpt"
        engine.pause = true; model.send(to: a)
        precondition(model.draft.isEmpty && model.generatingID == a && model.submitted[a] != nil)
        try await until { engine.gate != nil }
        model.configure(mode: .onDevice)
        precondition(model.configuration.mode == .privateCloudThinking && engine.configuration.mode == .privateCloudThinking)
        try await Task.sleep(for: .milliseconds(90))
        precondition(model.selected?.messages.last?.text == "A small step") // cumulative, not duplicated deltas
        model.select(b); model.draft = "A different draft"; model.send(to: b)
        precondition(engine.calls == 1 && model.draft == "A different draft")
        engine.gate?.resume(); engine.gate = nil
        try await until { model.generatingID == nil }
        precondition(model.selectedID == b && model.selected?.messages.isEmpty == true)
        let saved = await store.load()
        precondition(saved.first { $0.id == a }?.messages.map(\.text) == ["Explain this excerpt", "A small step, together."])
        let restored = LocalChatViewModel(generator: LocalEngineFixture(), store: store)
        await restored.prepare()
        precondition(restored.conversations.first { $0.id == a }?.messages.count == 2)
        model.select(a); precondition(model.draft.isEmpty && model.states[a] == .completed)
        engine.pause = false; engine.shouldFail = true; model.draft = "Retry this"; model.send(to: a)
        try await until { model.generatingID == nil }
        precondition(model.draft == "Retry this" && model.failures[a] != nil && model.selected?.messages.count == 2)
        engine.shouldFail = false; engine.pause = true; model.send(to: a)
        try await until { engine.gate != nil }
        model.draft = "Keep these new words"; model.stop()
        engine.gate?.resume(); engine.gate = nil
        try await until { model.generatingID == nil }
        try await Task.sleep(for: .milliseconds(90))
        precondition(model.draft == "Keep these new words" && model.states[a] == .interrupted && model.selected?.messages.count == 2)
        engine.readiness = .unavailable("Enable Apple Intelligence")
        let calls = engine.calls; model.send(to: a)
        precondition(engine.calls == calls && model.notice == "Enable Apple Intelligence" && !model.canSend)
        engine.readiness = .available; await model.prepare()
        model.draft = String(repeating: "x", count: 8_001); model.send(to: a)
        precondition(engine.calls == calls && model.notice == LocalChatError.inputTooLong.localizedDescription)
        // Sending to a stale view must never submit another conversation's draft.
        model.select(b); model.send(to: a); precondition(engine.calls == calls)
        await model.delete(a); precondition(!model.conversations.contains { $0.id == a })
        room.shutdown()
    }
    static func storageChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("local-chat-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Chat/history.json"), store = JSONLocalChatStore(url: url)
        let chat = LocalChatConversation(persona: .ada, title: "Fixture", messages: [.init(role: .user, text: "Question"), .init(role: .assistant, text: "Answer")])
        let initiallyEmpty = try await store.load()
        precondition(initiallyEmpty.isEmpty)
        try await store.save([chat])
        let restored = try await JSONLocalChatStore(url: url).load()
        precondition(restored == [chat])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue & 0o777 == 0o600)
        let bad = Data("not a valid history".utf8); try bad.write(to: url)
        let corrupt = JSONLocalChatStore(url: url)
        do { try await corrupt.save([chat]); preconditionFailure("Corrupt history was overwritten") } catch {}
        let preserved = try Data(contentsOf: url)
        precondition(preserved == bad)
        let duplicate = LocalChatConversation(id: chat.id, persona: .ada, title: "Duplicate")
        let separate = JSONLocalChatStore(url: directory.appendingPathComponent("other.json"))
        do { try await separate.save([chat, duplicate]); preconditionFailure("Duplicate identities accepted") } catch {}
    }
}
