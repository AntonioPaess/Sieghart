import AppKit
import Foundation
import Testing

extension MacContractsTests {
    @Suite(.tags(.agentRoom, .isolated)) @MainActor struct AgentRoomStateTests {
        @Test("G17.01 — construir não conecta; conectar e draft por sessão são explícitos")
        func explicitConnectionAndDrafts() async {
            let fixture = IntegrationRoomFixture(); defer { fixture.cleanup() }
            let room = fixture.room
            #expect(fixture.backend.connects == 0 && room.sessions.isEmpty)
            await room.create(.codex, directory: "/private/tmp")
            #expect(room.notice?.contains("Connect Codex") == true)
            await room.connect(.codex)
            #expect(room.selectedID == fixture.a.id && room.messages.count == 1)
            room.draft = "draft a"; await room.select(fixture.b.id); room.draft = "draft b"
            await room.select(fixture.a.id); #expect(room.draft == "draft a")
        }
        @Test("G17.01 — histórico tardio não troca seleção nem apaga deltas cumulativos")
        func staleHistoryAndDeltas() async throws {
            let fixture = IntegrationRoomFixture(), gate = IntegrationGate(); defer { gate.release(); fixture.cleanup() }
            let room = fixture.room, backend = fixture.backend
            await room.connect(.codex); backend.readGate = gate
            let read = Task { await room.select(fixture.a.id) }
            defer { read.cancel() }
            do { try await IntegrationWait.until { gate.entered } }
            catch { gate.release(); await read.value; throw error }
            backend.onEvent?(.delta(sessionID: fixture.a.id, messageID: "stream", text: "Hello "))
            backend.onEvent?(.delta(sessionID: fixture.a.id, messageID: "stream", text: "Ada"))
            await room.select(fixture.b.id); gate.release(); await read.value
            #expect(room.selectedID == fixture.b.id && room.transcripts[fixture.a.id]?.last?.text == "Hello Ada" && room.loadingID == nil)
            backend.onEvent?(.message(sessionID: fixture.a.id, CodingMessage(id: "stream", role: .assistant, text: "Hello Ada!")))
            #expect(room.transcripts[fixture.a.id]?.filter { $0.id == "stream" }.count == 1)
        }
        @Test("G17.01 — deltas no mesmo batch preservam ordem e disconnect encerra loading")
        func orderedBatchAndDisconnect() async throws {
            let fixture = IntegrationRoomFixture(), gate = IntegrationGate(); defer { gate.release(); fixture.cleanup() }
            let room = fixture.room, backend = fixture.backend
            await room.connect(.codex)
            backend.onEvent?(.delta(sessionID: fixture.b.id, messageID: "first", text: "1"))
            backend.onEvent?(.delta(sessionID: fixture.b.id, messageID: "second", text: "2"))
            room.flushDeltas(); #expect(room.transcripts[fixture.b.id]?.suffix(2).map(\.id) == ["first", "second"])
            backend.readGate = gate
            let read = Task { await room.select(fixture.a.id) }; defer { read.cancel() }
            do { try await IntegrationWait.until { gate.entered } }
            catch { gate.release(); await read.value; throw error }
            room.disconnect(.codex); gate.release(); await read.value
            #expect(room.loadingID == nil)
        }
        @Test("G17.01 — envio confirmado deduplica usuário e requests respondem uma vez")
        func receiptAndApprovals() async {
            let fixture = IntegrationRoomFixture(); defer { fixture.cleanup() }
            let room = fixture.room, backend = fixture.backend, a = fixture.a
            await room.connect(.codex); room.draft = "ask"; await room.send()
            #expect(room.messages.last?.text == "ask")
            backend.onEvent?(.message(sessionID: a.id, CodingMessage(id: "provider-user", role: .user, text: "ask")))
            #expect(room.messages.filter { $0.text == "ask" }.count == 1 && room.messages.last?.id == "provider-user")
            #expect(room.selected?.state == .ready && backend.sent == ["ask"])
            var working = a; working.state = .working; working.managed = true; working.turnID = "t"
            backend.onEvent?(.session(working)); #expect(room.activeCount == 1 && !room.canSend)
            var waiting = working; waiting.state = .waiting; backend.onEvent?(.session(waiting))
            let request = CodingApproval(id: "approval", sessionID: a.id, title: "Question", detail: "", questions: [CodingQuestion(id: "q", title: "Choose", prompt: "Which folder?")])
            backend.onEvent?(.approval(request))
            await room.respond(request, allow: true, answers: [:]); #expect(backend.responses.isEmpty)
            await room.respond(request, allow: true, answers: ["q": "src"])
            #expect(room.requests.isEmpty && backend.responses == [request.id])
            await room.respond(request, allow: true, answers: ["q": "src"]); #expect(backend.responses.count == 1)
            var done = working; done.state = .completed; done.turnID = nil; backend.onEvent?(.session(done))
            #expect(room.activeCount == 0 && room.selected?.state == .completed)
            backend.onEvent?(.session(working)); backend.onEvent?(.approval(request)); room.disconnect(.codex)
            #expect(room.connected.isEmpty && room.selected?.state == .blocked && room.requests.isEmpty)
        }
        @Test("G17.01 — falha/retry remove envio rejeitado e preserva draft novo")
        func rejectionAndRetry() async throws {
            let fixture = IntegrationRoomFixture(), gate = IntegrationGate(); defer { gate.release(); fixture.cleanup() }
            let room = fixture.room, backend = fixture.backend
            await room.connect(.codex); backend.failSend = true; backend.sendGate = gate; room.draft = "rejected"
            let send = Task { await room.send() }; defer { send.cancel() }
            do { try await IntegrationWait.until { gate.entered } }
            catch { gate.release(); await send.value; throw error }
            #expect(room.draft.isEmpty && room.messages.last?.text == "rejected" && room.sending.contains(fixture.a.id))
            room.draft = "new words"; gate.release(); await send.value
            #expect(room.draft == "new words" && !room.messages.contains { $0.text == "rejected" })
            let failure = try #require(room.sendFailures[fixture.a.id])
            room.draft = "restore me"; await room.send()
            #expect(room.draft == "restore me" && room.sendFailures[fixture.a.id] != failure)
        }
    }
    @Suite(.tags(.agentRoom, .isolated)) @MainActor struct AgentRoomPresentationTests {
        @Test("G17.02 — sala/chat fixos, drafts sobrevivem hide/reveal e conclusão respeita página")
        func pinnedPresentation() async throws {
            let isolated = try TestDefaults(); defer { isolated.cleanup() }
            isolated.value.set(["Companion", "Audio", "AI agents", "Timers", "Clipboard", "Calendar", "Team", "System", "Keep awake", "Display & power"], forKey: "island.tools")
            let fixture = IntegrationRoomFixture(); defer { fixture.cleanup() }
            let room = fixture.room
            await room.connect(.codex); room.draft = "Retained draft"
            let surface = try PresentationFixture(defaultsFixture: isolated, agentRoom: room, createActivation: false)
            let preferences = surface.preferences, assistant = surface.assistant, notch = surface.notch
            defer { surface.cleanup() }
            notch.showAgentRoom(); #expect(notch.presentation == .agentRoom && notch.isVisible)
            notch.collapseAfterPointerExit(); #expect(notch.isVisible && notch.presentation == .agentRoom)
            notch.hide(); notch.showAgentRoom(); #expect(room.draft == "Retained draft")
            room.page = .chat; try await IntegrationWait.until { notch.geometry.bodyHeight == 404 }
            notch.collapseAfterPointerExit(); #expect(notch.isVisible && notch.presentation == .agentRoom)
            assistant.startFocusSession(minutes: 5); assistant.finishPomodoroFromWidget()
            try await IntegrationWait.until { notch.latestCompletion != nil }
            #expect(notch.isVisible && notch.presentation == .agentRoom && room.page == .chat)
            assistant.resetPomodoro()
            for _ in 0..<20 { await Task.yield() }
            #expect(notch.presentation == .agentRoom)
            notch.showTools(); notch.collapseAfterPointerExit(); #expect(!notch.isVisible)
            notch.showAgentRoom(); #expect(room.page == .room)
            #expect(!preferences.toolActions.contains(.avatars) && !IslandToolAction.allCases.contains(.avatars))
        }
        @Test("G17.02 — reconnect explícito ao enviar e limite de 16 KB")
        func reconnectAndLimit() async {
            let fixture = IntegrationRoomFixture(); defer { fixture.cleanup() }
            await fixture.room.connect(.codex); fixture.room.disconnect(.codex)
            let before = fixture.backend.connects
            fixture.room.draft = "reconnect and send"; await fixture.room.send()
            #expect(fixture.backend.connects == before + 1 && fixture.backend.sent.last == "reconnect and send")
            fixture.room.draft = String(repeating: "a", count: 16_385); await fixture.room.send()
            #expect(fixture.room.notice?.contains("16 KB") == true && !fixture.room.draft.isEmpty)
        }
    }
    @Suite(.tags(.agentRoom, .isolated)) @MainActor struct AgentSendAdmissionTests {
        @Test("G17.05 — externo enfileira sem autoria; waiting salvo não vira request próprio")
        func externalQueueAndWaitingMetadata() async {
            let backend = IntegrationRoomBackend()
            var external = CodingSession(provider: .codex, providerID: "external", title: "Desktop work", directory: "/private/tmp", state: .working, observed: true, externalOwner: true)
            backend.listed = [external]; backend.queueReceipts = true
            let room = AgentRoomViewModel(services: [.codex: backend]); defer { room.shutdown() }
            await room.connect(.codex); room.draft = "Follow up on desktop work"
            #expect(room.canSend); await room.send(to: external.id)
            #expect(backend.sent == ["Follow up on desktop work"] && room.draft.isEmpty)
            #expect(room.messages.last?.id == "queued:1" && room.selected?.state == .working && room.selected?.managed == false)
            #expect(!room.sending.contains(external.id) && room.notice?.contains("Queued in Codex") == true)
            backend.onEvent?(.message(sessionID: external.id, CodingMessage(id: "queued:1", role: .user, text: "Follow up on desktop work")))
            #expect(room.messages.filter { $0.text == "Follow up on desktop work" }.count == 1)
            external.state = .waiting; backend.onEvent?(.session(external)); room.draft = "Resume through the owner"
            #expect(room.canSend); await room.send(); #expect(backend.sent.count == 2)
        }
        @Test("G17.05 — request próprio bloqueia; callback antigo não usa draft da nova seleção")
        func ownedRequestAndStaleSelection() async {
            let backend = IntegrationRoomBackend()
            let external = CodingSession(provider: .codex, providerID: "external", title: "Attached", directory: "/private/tmp", state: .working, turnID: "owned-turn", managed: true)
            let other = CodingSession(provider: .codex, providerID: "other", title: "Other", directory: "/private/tmp")
            backend.listed = [external, other]
            let room = AgentRoomViewModel(services: [.codex: backend]); defer { room.shutdown() }
            await room.connect(.codex); room.draft = "Steer the attached turn"
            #expect(room.canSend); await room.send(); #expect(backend.sent.count == 1)
            backend.onEvent?(.approval(CodingApproval(id: "owned-approval", sessionID: external.id, title: "Allow?", detail: "")))
            room.draft = "Keep this draft"; #expect(!room.canSend); await room.send()
            #expect(backend.sent.count == 1 && room.draft == "Keep this draft" && room.notice?.contains("pending request") == true)
            await room.select(other.id); room.draft = "Another chat's draft"; await room.send(to: external.id)
            #expect(backend.sent.count == 1 && room.draft == "Another chat's draft" && room.drafts[external.id] == "Keep this draft")
        }
        @Test("G17.05 — Claude trabalhando bloqueia queries sobrepostas")
        func claudeAlreadyWorking() async {
            let backend = IntegrationRoomBackend(.claude)
            backend.listed = [CodingSession(provider: .claude, providerID: "running", title: "Running", directory: "/private/tmp", state: .working, managed: true)]
            let room = AgentRoomViewModel(services: [.claude: backend]); defer { room.shutdown() }
            await room.connect(.claude); room.draft = "Do not start overlapping queries"
            #expect(!room.canSend); await room.send()
            #expect(backend.sent.isEmpty && !room.draft.isEmpty && room.notice?.contains("still working") == true)
        }
    }
    @Suite(.tags(.agentRoom, .nativeView)) @MainActor struct AgentComposerTests {
        @Test("G17.04 — texto alterado atualiza draft e envia uma vez, novo contexto limpa")
        func composer() {
            let editor = AgentChatEditor(); var draft = "", sends = 0
            editor.changed = { draft = $0 }; editor.submit = { sends += 1 }
            editor.update(text: "", focusID: "owned"); editor.stringValue = "Typing without committing"
            editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            #expect(draft == "Typing without committing")
            editor.sendDraft(); #expect(sends == 1 && draft == editor.stringValue)
            editor.update(text: "", focusID: "other"); #expect(editor.stringValue.isEmpty)
        }
        @Test("G17.04 — field editor offscreen preserva texto ainda não notificado")
        func uncommittedNativeText() throws {
            let editor = AgentChatEditor(); var draft = "", sends = 0
            editor.changed = { draft = $0 }; editor.submit = { sends += 1 }; editor.update(text: "", focusID: "owned")
            let panel = NSPanel(contentRect: NSRect(x: -5000, y: -5000, width: 300, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            defer { panel.makeFirstResponder(nil); panel.contentView = nil; panel.close() }
            editor.frame = NSRect(x: 0, y: 0, width: 300, height: 28); panel.contentView = editor
            try #require(panel.makeFirstResponder(editor)); editor.selectText(nil)
            let native = try #require(editor.currentEditor() as? NSTextView)
            native.string = "Uncommitted native text"; editor.update(text: "", focusID: "owned")
            #expect(native.string == "Uncommitted native text")
            editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            #expect(draft == "Uncommitted native text")
            editor.sendDraft(); #expect(sends == 1 && draft == "Uncommitted native text")
        }
    }
}
