import Foundation
import Testing

extension LogicTests {
    @Suite(.tags(.agentRoom)) @MainActor struct CodexProtocolDecodeTests {
        @Test("G17.06 — flags de aprovação e erro do sistema decodificam estado")
        func state() {
            #expect(CodexCodingAgent.state(.object(["type": .string("active"), "activeFlags": .array([.string("waitingOnApproval")])])) == .waiting)
            #expect(CodexCodingAgent.state(.object(["type": .string("systemError")])) == .blocked)
        }
    }
}

extension MacContractsTests {
    @Suite(.tags(.agentRoom, .localIntegration)) @MainActor struct CodexProtocolTests {
        @Test("G17.06 — handshake, lista e histórico paginado em stdio próprio")
        func discoveryAndHistory() async throws {
            let fixture = try IntegrationCodexFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session()
            #expect(fixture.backend.connected && session.state == .unknown)
            let stored = try await fixture.backend.sessions(); #expect(stored.count == 1)
            let history = try await fixture.backend.messages(in: session)
            #expect(history.first?.text == "Saved question")
        }
        @Test("G17.06 — stream fragmentado, terminal e refresh não deixam turno ativo")
        func streamAndTerminal() async throws {
            let fixture = try IntegrationCodexFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session()
            try await fixture.backend.send("fast", to: session)
            try await IntegrationWait.until { fixture.states.last?.state == .completed }
            #expect(fixture.states.last?.turnID == nil && fixture.texts.joined() == "Hello Ada")
            let refreshed = try await fixture.backend.sessions()
            #expect(refreshed.first { $0.id == session.id }?.state == .completed)
        }
        @Test("G17.06 — aprovação recusada recebe resolução e conclusão")
        func approval() async throws {
            let fixture = try IntegrationCodexFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session()
            try await fixture.backend.send("approval", to: session)
            try await IntegrationWait.until { !fixture.approvals.isEmpty }
            let approval = try #require(fixture.approvals.first)
            #expect(fixture.states.last?.state == .waiting && approval.sessionID == session.id)
            try await fixture.backend.respond(to: approval, allow: false, answers: [:])
            try await IntegrationWait.until { fixture.states.last?.state == .completed && fixture.resolved.contains(approval.id) }
        }
        @Test("G17.06 — interrupt limpa turno; request não suportado e erro preservam estado bloqueado")
        func interruptAndUnsupported() async throws {
            let fixture = try IntegrationCodexFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session()
            try await fixture.backend.send("hold", to: session)
            try await IntegrationWait.until { fixture.states.last?.state == .working }
            try await fixture.backend.interrupt(session)
            try await IntegrationWait.until { fixture.states.last?.state == .interrupted }
            #expect(fixture.states.last?.turnID == nil)
            try await fixture.backend.send("unsupported", to: session)
            try await IntegrationWait.until { fixture.states.last?.state == .blocked && fixture.states.last?.detail == "Codex reported a runtime error." }
        }
        @Test("G17.06 — eventos de workers preservam root, estado e prompt")
        func fleet() async throws {
            let fixture = try IntegrationCodexFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session(); try await fixture.backend.send("fleet", to: session)
            try await IntegrationWait.until { fixture.workers.contains { $0.id == "codex:child-4" && $0.state == .completed } }
            let latest = Dictionary(fixture.workers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            #expect(latest.count == 5 && latest.values.allSatisfy { $0.rootID == session.id })
            #expect(latest["codex:child-0"]?.state == .working && latest["codex:child-1"]?.state == .interrupted)
            #expect(latest["codex:child-4"]?.task == "Review the parser")
        }
        @Test("G17.06 — RPC broken/full stdin survives stop and restart")
        func stdinLifecycle() async throws {
            let directory = try IntegrationDirectory("rpc-stdin"); defer { directory.cleanup() }
            let rpc = AgentRPCProcess(); defer { rpc.stop(notify: false) }
            let closed = try directory.python("import os,time\nos.close(0)\nprint('{}', flush=True)\ntime.sleep(2)\n")
            try rpc.start(closed, arguments: [])
            try await Task.sleep(for: .milliseconds(150))
            try rpc.send(.object(["data": .string(String(repeating: "x", count: 200_000))]))
            try await IntegrationWait.until { !rpc.running }
            let stalled = try directory.python("import time\ntime.sleep(20)\n")
            for _ in 0..<4 {
                try rpc.start(stalled, arguments: [])
                try rpc.send(.object(["data": .string(String(repeating: "x", count: 200_000))]))
                rpc.stop(notify: false)
            }
            try await Task.sleep(for: .milliseconds(100))
            #expect(!rpc.running)
        }
        @Test("G17.06 — RPC timeout e cancelamento são bounded; disconnect encerra processo")
        func boundedRPC() async throws {
            let fixture = try IntegrationCodexFixture(); defer { fixture.cleanup() }
            _ = try await fixture.session()
            do { _ = try await fixture.rpc.request("timeout", timeout: .milliseconds(40)); Issue.record("Missing RPC timeout") }
            catch CodingAgentError.timedOut {}
            let task = Task { try await fixture.rpc.request("timeout") }; defer { task.cancel() }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            fixture.backend.disconnect(); #expect(!fixture.rpc.running)
            try fixture.rpc.start(fixture.script, arguments: [])
            do { _ = try await fixture.rpc.request("disconnect"); Issue.record("Missing RPC disconnect") }
            catch CodingAgentError.disconnected {}
            fixture.rpc.stop(notify: false)
        }
    }
    @Suite(.tags(.agentRoom, .localIntegration)) @MainActor struct ClaudeBridgeTests {
        @Test("G17.07 — SDK local lista/history e exige chave ao enviar")
        func discoveryAndMissingKey() async throws {
            let fixture = try IntegrationClaudeFixture(apiKey: ""); defer { fixture.cleanup() }
            try await fixture.backend.connect()
            let stored = try await fixture.backend.sessions(), session = try #require(stored.first)
            #expect(stored.count == 1 && session.state == .unknown)
            #expect(try await fixture.backend.messages(in: session).first?.text == "Fixture history")
            await #expect(throws: (any Error).self) { try await fixture.backend.send("hello", to: session) }
        }
        @Test("G17.07 — stream, IDs estáveis, histórico e refresh preservam conclusão")
        func streamingIdentityAndRefresh() async throws {
            let fixture = try IntegrationClaudeFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session()
            #expect(try await fixture.backend.messages(in: session).isEmpty)
            try await fixture.backend.send("success", to: session)
            try await IntegrationWait.until { fixture.latest?.state == .completed }
            #expect(fixture.text == "Hello Ada")
            let history = try await fixture.backend.messages(in: session)
            #expect(history.map(\.id) == fixture.liveIDs && history.count == 2)
            let refreshed = try await fixture.backend.sessions()
            #expect(refreshed.first { $0.id == session.id }?.state == .completed)
        }
        @Test("G17.07 — permissão e pergunta têm admissão e resolução próprias", arguments: ["permission", "question"])
        func requests(_ prompt: String) async throws {
            let fixture = try IntegrationClaudeFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session(); try await fixture.backend.send(prompt, to: session)
            try await IntegrationWait.until { fixture.request != nil }
            let request = try #require(fixture.request)
            #expect(fixture.latest?.state == .waiting)
            if prompt == "question" {
                #expect(request.questions.first?.id == "Choose a folder?")
                try await fixture.backend.respond(to: request, allow: true, answers: ["Choose a folder?": "src"])
            } else { try await fixture.backend.respond(to: request, allow: false, answers: [:]) }
            try await IntegrationWait.until { fixture.latest?.state == .completed && fixture.resolved }
        }
        @Test("G17.07 — texto multipart é consolidado igualmente em live e history")
        func multipart() async throws {
            let fixture = try IntegrationClaudeFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session(); try await fixture.backend.send("two-parts", to: session)
            try await IntegrationWait.until { fixture.latest?.state == .completed }
            #expect(fixture.finalText == "Hello Ada\n\nNext step")
            #expect(try await fixture.backend.messages(in: session).last?.text == fixture.finalText)
        }
        @Test("G17.07 — interrupção e query sem result terminam corretamente", arguments: ["hold", "no-result"])
        func interruptedOrMissingResult(_ prompt: String) async throws {
            let fixture = try IntegrationClaudeFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session(); try await fixture.backend.send(prompt, to: session)
            if prompt == "hold" {
                try await IntegrationWait.until { fixture.latest?.state == .working }
                try await fixture.backend.interrupt(session)
                try await IntegrationWait.until { fixture.latest?.state == .interrupted }
            } else { try await IntegrationWait.until { fixture.latest?.state == .failed } }
        }
        @Test("G17.07 — árvore de workers ignora conclusão antiga e saída filha não entra no chat raiz")
        func fleet() async throws {
            let fixture = try IntegrationClaudeFixture(); defer { fixture.cleanup() }
            let session = try await fixture.session(); try await fixture.backend.send("fleet", to: session)
            try await IntegrationWait.until { fixture.latest?.state == .completed && fixture.childWorkers.contains { $0.id.hasSuffix(":worker:child-4") } }
            let latest = Dictionary(fixture.childWorkers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            #expect(latest.count == 5 && latest.values.allSatisfy { $0.rootID == session.id })
            #expect(latest[session.id + ":worker:child-0"]?.state == .working)
            #expect(latest[session.id + ":worker:child-4"]?.state == .completed)
            #expect(try await fixture.backend.messages(in: session).contains { $0.text == "Child-only output" } == false)
        }
    }
    @Suite(.tags(.agentRoom, .newCodexChat, .localIntegration)) @MainActor struct NewCodexChatTests {
        @Test("A01 — criar chat vazio e refresh/seleção preservam thread sem ler history")
        func emptyCreationAndRefresh() async throws {
            let fixture = try IntegrationNewCodexFixture(); defer { fixture.cleanup() }
            let fresh = try await fixture.create(), room = fixture.room
            #expect(fresh.providerID == "fresh" && fresh.state == .ready && fresh.managed)
            #expect(room.page == .chat && room.notice == nil && room.messages.isEmpty && room.loadingID == nil)
            await room.refresh(.codex)
            #expect(room.selectedID == fresh.id && room.sessions.contains { $0.id == fresh.id })
            await room.select(fresh.id)
            let requests = try fixture.requests()
            #expect(!requests.contains("thread/read") && !requests.contains("thread/turns/list"))
        }
        @Test("A01 — primeiro envio rejeitado é retryable e seleção não requisita history")
        func rejectedFirstSend() async throws {
            let fixture = try IntegrationNewCodexFixture(); defer { fixture.cleanup() }
            let fresh = try await fixture.create(), room = fixture.room
            room.draft = "retryable failure"; await room.send()
            #expect(room.draft == "retryable failure" && room.selected?.state == .ready)
            #expect(room.notice == "Fixture first send rejected" && room.messages.isEmpty)
            await room.select(fresh.id)
            #expect(try fixture.requests().contains("thread/read") == false)
        }
        @Test("A01 — primeiro turno e corrida de persistência não duplicam nem apagam texto")
        func firstTurnAndPersistenceRace() async throws {
            let fixture = try IntegrationNewCodexFixture(); defer { fixture.cleanup() }
            let fresh = try await fixture.create(), room = fixture.room
            room.draft = "first question"; await room.send()
            try await IntegrationWait.until { room.selected?.state == .completed && room.messages.contains { $0.text == "First reply" } }
            #expect(room.selected?.turnID == nil && room.messages.filter { $0.text == "first question" }.count == 1)
            #expect(room.draft.isEmpty && room.notice == nil)
            #expect(try await fixture.service.messages(in: fresh).isEmpty)
            await room.select(fresh.id)
            #expect(room.notice == nil && room.messages.map(\.text) == ["first question", "First reply"])
            let persisted = try await fixture.service.sessions()
            #expect(persisted.first?.state == .completed && persisted.first?.managed == true)
        }
        @Test("A01 — erro normal de history continua visível")
        func ordinaryHistoryError() async throws {
            let fixture = try IntegrationNewCodexFixture(); defer { fixture.cleanup() }
            _ = try await fixture.create()
            let missing = CodingSession(provider: .codex, providerID: "missing", title: "Missing", directory: fixture.directory.url.path)
            do { _ = try await fixture.service.messages(in: missing); Issue.record("An ordinary history error must remain visible") }
            catch CodingAgentError.unavailable(let reason) { #expect(reason == "No such thread") }
        }
    }
}
