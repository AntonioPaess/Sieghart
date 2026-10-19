import Foundation
import Testing

private func integrationRoomRecord(_ event: String, _ date: Date) -> String {
    "{\"timestamp\":\"\(ISO8601DateFormatter().string(from: date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(event)\"}}\n"
}

extension LogicTests {
    @Suite(.tags(.agentRoom)) @MainActor struct AgentObservationDecodeTests {
        @Test("G17.03 — terminal mais novo impede replay de tail ressuscitar trabalho")
        func terminalDoesNotReplay() {
            let now = Date(timeIntervalSince1970: 1_700_000_000), earlier = now.addingTimeInterval(-1)
            let active = CodexRoomObservation.parse(Data(integrationRoomRecord("task_started", earlier).utf8))
            #expect(active.state == .working)
            let finished = CodexRoomObservation.parse(Data(integrationRoomRecord("task_complete", now).utf8), previous: active)
            #expect(finished.state == .completed)
            #expect(CodexRoomObservation.parse(Data(integrationRoomRecord("task_started", earlier).utf8), previous: finished).state == .completed)
        }
        @Test("G17.03 — parentThreadId é subagente; forkedFromId não é parent")
        func parentAndFork() throws {
            let child = try #require(CodexCodingAgent.session(.object(["id": .string("child"), "parentThreadId": .string("fleet-root"), "agentNickname": .string("Review"), "cwd": .string("/private/tmp")])))
            #expect(child.parentID == "codex:fleet-root" && child.agentName == "Review")
            let fork = try #require(CodexCodingAgent.session(.object(["id": .string("fork"), "forkedFromId": .string("fleet-root")])))
            #expect(fork.parentID == nil)
        }
    }
    @Suite(.tags(.agentRoom)) @MainActor struct CodexMessageIdentityTests {
        @Test("G17.10 — clientId prevalece ao confirmar mensagem enfileirada; nome vem do agent_path")
        func clientIdentityAndSubagentSource() throws {
            let lower = try #require(CodexCodingAgent.session(.object(["id": .string("child"), "source": .string(#"{"subagent":{"thread_spawn":{"parent_thread_id":"parent","agent_path":"/root/fix_send"}}}"#)])))
            #expect(lower.parentID == "codex:parent" && lower.agentName == "fix send")
            let confirmed = try #require(CodexCodingAgent.message(.object(["id": .string("server-item"), "clientId": .string("queued-client-id"), "type": .string("userMessage"), "content": .array([.object(["type": .string("text"), "text": .string("Queued fixture text")])])])))
            #expect(confirmed.id == "queued-client-id" && confirmed.text == "Queued fixture text")
        }
    }
}

extension MacContractsTests {
    @Suite(.tags(.agentRoom)) @MainActor struct AgentFleetTests {
        @Test("G17.03 — workers por root/subárvore excluem alheios, seleção e disconnect", .tags(.isolated))
        func workersByRoom() async {
            let backend = IntegrationRoomBackend()
            let root = CodingSession(provider: .codex, providerID: "fleet-root", title: "Fleet", directory: "/private/tmp", state: .working, managed: true)
            let other = CodingSession(provider: .codex, providerID: "other-room", title: "Other", directory: "/private/tmp", state: .working, managed: true)
            backend.listed = [root, other]
            let room = AgentRoomViewModel(services: [.codex: backend]); defer { room.shutdown() }
            await room.connect(.codex); await room.select(root.id)
            for index in 0..<5 {
                backend.onEvent?(.worker(CodingWorker(id: "codex:worker-\(index)", rootID: root.id, parentID: index == 4 ? "codex:worker-0" : root.id, provider: .codex, name: "Worker \(index)", task: "Task \(index)", state: [.working, .waiting, .blocked, .completed, .working][index], live: true)))
            }
            backend.onEvent?(.worker(CodingWorker(id: "codex:unrelated", rootID: other.id, parentID: other.id, provider: .codex, name: "Other", task: "Other task", state: .working, live: true)))
            #expect(room.roomWorkers.count == 6 && !room.roomWorkers.contains { $0.id == "codex:unrelated" })
            #expect(room.roomWorkers.last?.parentID == "codex:worker-0")
            #expect(room.workers(in: root).count == 6 && room.workers(in: other).count == 2)
            await room.observeRooms([root.id, other.id, root.id]); #expect(backend.observedRoots == [root.id, other.id])
            await room.select(other.id); #expect(room.roomWorkers.count == 2)
            room.disconnect(.codex); #expect(room.roomWorkers.allSatisfy { !$0.live })
        }
        @Test("G17.03 — tail incremental mantém cache e aguarda newline antes de concluir", .tags(.localIntegration))
        func incrementalTail() throws {
            let directory = try IntegrationDirectory("observation"); defer { directory.cleanup() }
            let now = Date(timeIntervalSince1970: 1_700_000_000), earlier = now.addingTimeInterval(-1)
            let path = try directory.file("owned.jsonl", contents: integrationRoomRecord("task_started", earlier))
            let initial = try #require(CodexRoomObservation.read(path.path)), cached = try #require(CodexRoomObservation.read(path.path, previous: initial))
            #expect(initial.offset == cached.offset && initial.lastSeen == cached.lastSeen)
            let writer = try FileHandle(forWritingTo: path); defer { try? writer.close() }; try writer.seekToEnd()
            try writer.write(contentsOf: Data(integrationRoomRecord("task_complete", now).dropLast().utf8))
            let partial = try #require(CodexRoomObservation.read(path.path, previous: cached))
            #expect(partial.state == .working && partial.offset == cached.offset)
            try writer.write(contentsOf: Data([10])); try writer.close()
            let ended = try #require(CodexRoomObservation.read(path.path, previous: partial))
            #expect(ended.state == .completed && ended.offset > partial.offset)
        }
    }
    @Suite(.tags(.agentRoom, .localIntegration)) @MainActor struct CodexDesktopStoreTests {
        @Test("G17.09 — árvore SQLite selecionada, nomes, parent, estados e mensagens sem chat alheio")
        func treeAndTerminalUpdate() throws {
            let fixture = try IntegrationDesktopDatabase(); defer { fixture.cleanup() }
            let entries = CodexDesktopStore.tree(fixture.root, directory: fixture.folder)
            #expect(entries.count == 5 && entries.first?.session.title == "Actual selected chat")
            #expect(entries.first?.session.externalOwner == true)
            #expect(entries.filter { $0.session.observed && $0.session.state == .working }.count == 2)
            #expect(entries.first { $0.session.providerID == "active-a" }?.session.agentName == "parser work")
            #expect(entries.first { $0.session.providerID == "nested" }?.session.parentID == "codex:active-a")
            #expect(!entries.contains { $0.session.providerID == "unrelated" })
            #expect(entries.first { $0.session.providerID == "active-a" }?.messages.last?.text == "Actual fixture update")
            try fixture.sql("thread_history_1.sqlite", "UPDATE thread_turns SET status='completed',completed_at=210 WHERE thread_id='active-b';")
            let updated = CodexDesktopStore.tree(fixture.root, directory: fixture.folder)
            #expect(updated.filter { $0.session.observed && $0.session.state == .working }.count == 1)
        }
    }
    @Suite(.tags(.agentRoom, .localIntegration)) @MainActor struct CodexOwnershipTests {
        @Test("G17.10 — desktop-owned e writer-conflict enfileiram sem assumir writer; child exige dono")
        func queuesAndParentOwnership() async throws {
            let fixture = try IntegrationDesktopDatabase(); defer { fixture.cleanup() }
            let script = try fixture.directory.python(IntegrationDesktopFixture.fixture)
            let backend = CodexCodingAgent(executable: { script }, desktopDirectory: fixture.folder); defer { backend.disconnect() }
            var queued: [(String, String)] = [], workers: [String: CodingWorker] = [:], messages: [CodingMessage] = []
            backend.onEvent = { event in
                switch event {
                case .queued(let id, let messageID): queued.append((id, messageID))
                case .worker(let worker): workers[worker.id] = worker
                case .message(_, let message): messages.append(message)
                default: break
                }
            }
            try await backend.connect(); let listed = try await backend.sessions()
            try #require(listed.count == 2); #expect(listed[0].externalOwner)
            try await backend.send("A desktop queue message", to: listed[0])
            #expect(queued.count == 1 && queued[0].0 == "codex:" + fixture.root)
            try await backend.send("Writer-conflict fallback", to: listed[1])
            #expect(queued.count == 2 && queued[1].0 == "codex:writer-conflict")
            try await backend.observeRoom(listed[0])
            #expect(workers.count == 4 && workers.values.filter { $0.live && $0.state == .working }.count == 2)
            #expect(messages.contains { $0.text == "Actual fixture update" })
            let child = try #require(CodexDesktopStore.tree(fixture.root, directory: fixture.folder).first { $0.session.providerID == "active-a" }?.session)
            do { try await backend.send("Do not directly resume this child", to: child); Issue.record("Expected parent ownership guard") }
            catch CodingAgentError.unavailable(let reason) { #expect(reason.contains("controlled by its parent")) }
        }
        @Test("G17.10 — timestamp terminal persistido vence precisão maior do tail")
        func terminalTimestampWins() async throws {
            let fixture = try IntegrationDesktopDatabase(); defer { fixture.cleanup() }
            try fixture.sql("thread_history_1.sqlite", "UPDATE thread_turns SET status='completed',completed_at=210 WHERE thread_id='active-b';")
            let script = try fixture.directory.python(IntegrationDesktopFixture.fixture)
            let backend = CodexCodingAgent(executable: { script }, desktopDirectory: fixture.folder); defer { backend.disconnect() }
            var workers: [String: CodingWorker] = [:]
            backend.onEvent = { if case .worker(let value) = $0 { workers[value.id] = value } }
            try await backend.connect(); let root = try #require(try await backend.sessions().first)
            let tail = fixture.folder.appendingPathComponent("owned-tail.jsonl")
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let completionSecond = 1_700_000_000.0
            let record: [String: Any] = ["timestamp": formatter.string(from: Date(timeIntervalSince1970: completionSecond + 0.9)), "type": "response_item", "payload": ["type": "function_call", "name": "fixture_tool", "arguments": "{}"]]
            var data = try JSONSerialization.data(withJSONObject: record); data.append(10); try data.write(to: tail)
            let quoted = tail.path.replacingOccurrences(of: "'", with: "''")
            try fixture.sql("state_5.sqlite", "UPDATE threads SET rollout_path='\(quoted)' WHERE id='active-a';")
            try await backend.observeRoom(root); #expect(workers["codex:active-a"]?.state == .working)
            try fixture.sql("thread_history_1.sqlite", "UPDATE thread_turns SET status='completed',completed_at=\(Int(completionSecond)) WHERE thread_id='active-a';")
            try await backend.observeRoom(root)
            #expect(workers["codex:active-a"]?.state == .completed && workers.values.filter { $0.state == .working }.isEmpty)
        }
    }
}
