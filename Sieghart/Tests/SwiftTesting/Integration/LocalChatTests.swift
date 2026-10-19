import Foundation
import Testing

@MainActor private final class IntegrationLocalEngine: LocalChatGenerating {
    var readiness: LocalChatReadiness = .available
    var calls = 0
    var configuration = AppleChatConfiguration()
    var histories: [[LocalChatMessage]] = []
    var shouldFail = false
    var gate: IntegrationGate?
    var snapshot: (@MainActor (String) -> Void)?
    func configure(_ value: AppleChatConfiguration) { configuration = value }
    func generate(history: [LocalChatMessage], persona: LocalChatPersona, onSnapshot: @escaping @MainActor (String) -> Void) async throws -> String {
        calls += 1; histories.append(history); snapshot = onSnapshot
        onSnapshot("A"); onSnapshot("A small step")
        await gate?.suspend()
        if shouldFail { throw LocalChatError.generationFailed("Fixture failure") }
        // Deliberately delivers after cancellation: the model owns admission.
        onSnapshot("A small step, together.")
        return "A small step, together."
    }
}

/// A failed expectation must still finish a suspended generator before the
/// defaults/store owned by its test are released.
@MainActor private func withLocalChatResources(_ models: [LocalChatViewModel], gates: [IntegrationGate] = [], operation: () async throws -> Void) async throws {
    func finish() async throws {
        models.forEach { $0.shutdown() }
        gates.forEach { $0.release() }
        try await IntegrationWait.until { models.allSatisfy { $0.generatingID == nil && !$0.loading } }
    }
    do { try await operation() }
    catch {
        do { try await finish() } catch { Issue.record(error, "Local chat cleanup did not complete") }
        throw error
    }
    try await finish()
}

extension LogicTests {
    @Suite(.tags(.localChat)) struct AppleChatEligibilityTests {
        @Test("G18.01 — OS anterior ao modelo impede todos os modos", arguments: [-1, 0, 14, 25, 26], AppleChatMode.allCases)
        func oldOS(_ major: Int, _ mode: AppleChatMode) {
            for entitlement in [false, true] {
            let result = AppleChatEligibility.prerequisite(for: mode, macOSMajor: major, hasPCCEntitlement: entitlement)
            #expect(result?.available == false)
            #expect(result?.reason?.contains("macOS 27") == true)
            }
        }
        @Test("G18.01 — modo local independe de entitlement PCC", arguments: [27, 28], [false, true])
        func onDevice(_ major: Int, _ entitlement: Bool) {
            #expect(AppleChatEligibility.prerequisite(for: .onDevice, macOSMajor: major, hasPCCEntitlement: entitlement) == nil)
        }
        @Test("G18.01 — PCC exige entitlement; nil apenas permite verificar disponibilidade depois", arguments: [27, 28])
        func cloud(_ major: Int) {
            let denied = AppleChatEligibility.prerequisite(for: .privateCloudThinking, macOSMajor: major, hasPCCEntitlement: false)
            #expect(denied?.available == false)
            #expect(denied?.reason?.contains("approved Private Cloud Compute entitlement") == true)
            #expect(AppleChatEligibility.prerequisite(for: .privateCloudThinking, macOSMajor: major, hasPCCEntitlement: true) == nil)
        }
    }
    @Suite(.tags(.localChat)) struct LocalChatContextTests {
        @Test("G18.03 — últimos seis pares e prompt atual, sem system antigo")
        func recentPairs() throws {
            var messages = [LocalChatMessage(role: .system, text: "Untrusted old system text")]
            for index in 0..<10 { messages += [.init(role: .user, text: "Q\(index)"), .init(role: .assistant, text: "A\(index)")] }
            messages.append(.init(role: .user, text: "Now"))
            let context = try LocalChatContext.prepare(messages)
            #expect(context.past.count == 12)
            #expect(context.past.first?.text == "Q4")
            #expect(context.prompt.text == "Now")
            #expect(!context.past.contains { $0.role == .system })
        }
        @Test("G18.03 — histórico acima do orçamento é descartado")
        func boundedHistory() throws {
            let context = try LocalChatContext.prepare([.init(role: .user, text: String(repeating: "x", count: 6_000)), .init(role: .assistant, text: String(repeating: "x", count: 6_000)), .init(role: .user, text: "Short")])
            #expect(context.past.isEmpty)
            #expect(context.prompt.text == "Short")
        }
        @Test("G18.03 — entrada acima de oito mil caracteres é rejeitada")
        func longInput() {
            #expect(throws: LocalChatError.inputTooLong) { try LocalChatContext.prepare([.init(role: .user, text: String(repeating: "x", count: 8_001))]) }
        }
    }
}

extension MacContractsTests {
    @Suite(.tags(.localChat, .isolated)) @MainActor struct LocalChatConfigurationTests {
        @Test("G18.02 — configuração PCC/deep, forwarding e restauração sem inferência")
        func configuration() throws {
            let isolated = try TestDefaults(); defer { isolated.cleanup() }
            let engine = IntegrationLocalEngine(), model = LocalChatViewModel(generator: IntegrationLocalEngine(), defaults: isolated.value)
            defer { model.shutdown() }
            #expect(model.configuration.mode == .privateCloudThinking && model.configuration.reasoning == .deep)
            let configured = LocalChatViewModel(generator: engine, defaults: isolated.value)
            defer { configured.shutdown() }
            configured.configure(mode: .onDevice, reasoning: .light)
            #expect(engine.configuration == configured.configuration && engine.calls == 0)
            let restoredEngine = IntegrationLocalEngine(), restored = LocalChatViewModel(generator: IntegrationLocalEngine(), defaults: isolated.value)
            defer { restored.shutdown() }
            #expect(restored.configuration.mode == .onDevice && restored.configuration.reasoning == .light)
            let forwarding = LocalChatViewModel(generator: restoredEngine, defaults: isolated.value)
            defer { forwarding.shutdown() }
            forwarding.configure(mode: .privateCloudThinking, reasoning: .deep)
            #expect(forwarding.configuration.mode.requiresNetwork && restoredEngine.configuration.reasoning == .deep && restoredEngine.calls == 0)
        }
    }
    @Suite(.tags(.localChat, .isolated)) @MainActor struct LocalChatConversationTests {
        @Test("G18.04 — criar não infere; streaming cumulativo e seleção/draft independentes")
        func streamingKeepsOriginalConversation() async throws {
            let isolated = try TestDefaults(); defer { isolated.cleanup() }
            let engine = IntegrationLocalEngine(), store = MemoryLocalChatStore(), gate = IntegrationGate()
            engine.gate = gate
            let model = LocalChatViewModel(generator: engine, store: store, defaults: isolated.value)
            let room = AgentRoomViewModel(services: [:], localChat: model)
            defer { room.shutdown() }
            try await withLocalChatResources([model], gates: [gate]) {
            #expect(room.connected.isEmpty && room.sessions.isEmpty && engine.calls == 0)
            let a = try #require(await model.create()), b = try #require(await model.create())
            #expect(engine.calls == 0 && model.conversations.count == 2)
            model.select(a); model.draft = "Explain this excerpt"; model.send(to: a)
            #expect(model.draft.isEmpty && model.generatingID == a && model.submitted[a] != nil)
            try await IntegrationWait.until { gate.entered }
            model.configure(mode: .onDevice)
            #expect(model.configuration.mode == .privateCloudThinking && engine.configuration.mode == .privateCloudThinking)
            // Explicitly drive the model's coalescing boundary; no wall-clock delay.
            try await IntegrationWait.until { model.selected?.messages.last?.text == "A small step" }
            #expect(model.selected?.messages.last?.text == "A small step")
            model.select(b); model.draft = "A different draft"; model.send(to: b)
            #expect(engine.calls == 1 && model.draft == "A different draft")
            gate.release(); try await IntegrationWait.until { model.generatingID == nil }
            #expect(model.selectedID == b && model.selected?.messages.isEmpty == true)
            let saved = await store.load()
            #expect(saved.first { $0.id == a }?.messages.map(\.text) == ["Explain this excerpt", "A small step, together."])
            model.select(a)
            #expect(model.draft.isEmpty && model.states[a] == .completed)
            }
        }
        @Test("G18.05 — restauração e falha/retry preservam o draft")
        func restoreAndFailure() async throws {
            let isolated = try TestDefaults(); defer { isolated.cleanup() }
            let engine = IntegrationLocalEngine(), store = MemoryLocalChatStore()
            let model = LocalChatViewModel(generator: engine, store: store, defaults: isolated.value)
            try await withLocalChatResources([model]) {
            let id = try #require(await model.create())
            model.select(id); model.draft = "First"; model.send(to: id)
            try await IntegrationWait.until { model.generatingID == nil }
            let restored = LocalChatViewModel(generator: IntegrationLocalEngine(), store: store, defaults: isolated.value)
            defer { restored.shutdown() }
            await restored.prepare()
            #expect(restored.conversations.first { $0.id == id }?.messages.count == 2)
            engine.shouldFail = true; model.draft = "Retry this"; model.send(to: id)
            try await IntegrationWait.until { model.generatingID == nil }
            #expect(model.draft == "Retry this" && model.failures[id] != nil && model.selected?.messages.count == 2)
            engine.shouldFail = false; model.send(to: id)
            try await IntegrationWait.until { model.generatingID == nil }
            #expect(model.selected?.messages.count == 4 && model.draft.isEmpty)
            }
        }
        @Test("G18.05 — stop ignora snapshots tardios e preserva novas palavras")
        func cancellation() async throws {
            let isolated = try TestDefaults(); defer { isolated.cleanup() }
            let engine = IntegrationLocalEngine(), gate = IntegrationGate(); engine.gate = gate
            let model = LocalChatViewModel(generator: engine, store: MemoryLocalChatStore(), defaults: isolated.value)
            try await withLocalChatResources([model], gates: [gate]) {
            let id = try #require(await model.create())
            model.select(id); model.draft = "Question"; model.send(to: id)
            try await IntegrationWait.until { gate.entered }
            model.draft = "Keep these new words"; model.stop()
            gate.release(); try await IntegrationWait.until { model.generatingID == nil }
            engine.snapshot?("A stale callback")
            #expect(model.draft == "Keep these new words" && model.states[id] == .interrupted && model.selected?.messages.isEmpty == true)
            }
        }
        @Test("G18.05 — indisponibilidade, limites e view antiga não iniciam geração; exclusão")
        func admissionAndDeletion() async throws {
            let isolated = try TestDefaults(); defer { isolated.cleanup() }
            let engine = IntegrationLocalEngine(), model = LocalChatViewModel(generator: IntegrationLocalEngine(), store: MemoryLocalChatStore(), defaults: isolated.value)
            try await withLocalChatResources([model]) {
            let a = try #require(await model.create()), b = try #require(await model.create())
            let unavailable = LocalChatViewModel(generator: engine, store: MemoryLocalChatStore(), defaults: isolated.value)
            defer { unavailable.shutdown() }
            let id = try #require(await unavailable.create()); unavailable.select(id); unavailable.draft = "Question"
            engine.readiness = .unavailable("Enable Apple Intelligence"); unavailable.send(to: id)
            #expect(engine.calls == 0 && unavailable.notice == "Enable Apple Intelligence" && !unavailable.canSend)
            engine.readiness = .available; await unavailable.prepare()
            unavailable.draft = String(repeating: "x", count: 8_001); unavailable.send(to: id)
            #expect(engine.calls == 0 && unavailable.notice == LocalChatError.inputTooLong.localizedDescription)
            model.select(b); model.draft = "Different chat"; model.send(to: a)
            #expect(model.draft == "Different chat" && model.generatingID == nil)
            await model.delete(a)
            #expect(!model.conversations.contains { $0.id == a })
            }
        }
    }
    @Suite(.tags(.localChat, .localIntegration)) struct LocalChatStorageTests {
        @Test("G18.06 — JSON vazio, roundtrip e permissão 0600")
        func roundTrip() async throws {
            let directory = try IntegrationDirectory("chat-store"); defer { directory.cleanup() }
            let url = directory.url.appendingPathComponent("Chat/history.json"), store = JSONLocalChatStore(url: url)
            #expect(try await store.load().isEmpty)
            let chat = LocalChatConversation(persona: .ada, title: "Fixture", messages: [.init(role: .user, text: "Question"), .init(role: .assistant, text: "Answer")])
            try await store.save([chat])
            #expect(try await JSONLocalChatStore(url: url).load() == [chat])
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let mode = try #require(attributes[.posixPermissions] as? NSNumber)
            #expect(mode.intValue & 0o777 == 0o600)
        }
        @Test("G18.06 — corrupção não é sobrescrita e IDs duplicados são rejeitados")
        func invalidHistory() async throws {
            let directory = try IntegrationDirectory("corrupt-chat"); defer { directory.cleanup() }
            let url = try directory.file("history.json", contents: "not a valid history"), bad = try Data(contentsOf: url)
            let chat = LocalChatConversation(persona: .ada, title: "Fixture")
            await #expect(throws: (any Error).self) { try await JSONLocalChatStore(url: url).save([chat]) }
            #expect(try Data(contentsOf: url) == bad)
            let duplicate = LocalChatConversation(id: chat.id, persona: .ada, title: "Duplicate")
            await #expect(throws: (any Error).self) { try await JSONLocalChatStore(url: directory.url.appendingPathComponent("other.json")).save([chat, duplicate]) }
        }
    }
}
