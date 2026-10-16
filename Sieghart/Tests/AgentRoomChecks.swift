import AppKit
import Foundation

@MainActor private final class RoomFixture: CodingAgentServing {
    let provider: AIProvider
    var connected = false
    var onEvent: ((CodingAgentEvent) -> Void)?
    var listed: [CodingSession] = []
    var history: [String: [CodingMessage]] = [:]
    var connects = 0, sent: [String] = [], responses: [String] = []
    var failSend = false
    var queueReceipts = false
    var observedRoots: [String] = []
    var readGate: CheckedContinuation<Void, Never>?
    var sendGate: CheckedContinuation<Void, Never>?
    var pauseRead = false, pauseSend = false
    init(_ provider: AIProvider = .codex) { self.provider = provider }
    func connect() { connects += 1; connected = true }
    func disconnect() { connected = false }
    func sessions() -> [CodingSession] { listed }
    func messages(in session: CodingSession) async -> [CodingMessage] {
        if pauseRead { pauseRead = false; await withCheckedContinuation { readGate = $0 } }
        return history[session.id] ?? []
    }
    func create(in directory: String) -> CodingSession { CodingSession(provider: provider, providerID: "created", title: "Created", directory: directory, state: .ready, managed: true) }
    func send(_ text: String, to session: CodingSession) async throws {
        sent.append(text)
        if pauseSend { pauseSend = false; await withCheckedContinuation { sendGate = $0 } }
        if failSend { throw CodingAgentError.unavailable("Fixture rejection") }
        if queueReceipts { onEvent?(.queued(sessionID: session.id, messageID: "queued:\(sent.count)")) }
    }
    func observeRoom(_ session: CodingSession) { observedRoots.append(session.id) }
    func interrupt(_ session: CodingSession) {}
    func respond(to approval: CodingApproval, allow: Bool, answers: [String: String]) { responses.append(approval.id); onEvent?(.resolved(approvalID: approval.id)) }
}

@main struct AgentRoomChecks {
    @MainActor static func until(_ predicate: () -> Bool, file: StaticString = #fileID, line: UInt = #line) async throws {
        for _ in 0..<300 {
            if predicate() { return }; try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Fixture event did not arrive at \(file):\(line)")
    }
    @MainActor static func main() async throws {
        try await modelChecks()
        try await fleetChecks()
        try await composerChecks()
        AgentChatMotionChecks.run()
        try await sendAdmissionChecks()
        try await protocolChecks()
        try await CodexDesktopChecks.run()
        try await claudeChecks()
        print("Agent room: model, Codex RPC and Claude SDK bridge checks passed; no live provider calls.")
    }
    @MainActor static func modelChecks() async throws {
        let backend = RoomFixture()
        let a = CodingSession(provider: .codex, providerID: "a", title: "A", directory: "/private/tmp", state: .ready)
        let b = CodingSession(provider: .codex, providerID: "b", title: "B", directory: "/private/tmp", state: .unknown)
        backend.listed = [a, b]; backend.history[a.id] = [CodingMessage(id: "old", role: .user, text: "Saved question")]
        let room = AgentRoomViewModel(services: [.codex: backend])
        precondition(backend.connects == 0 && room.sessions.isEmpty) // No startup reads/runtime.
        await room.create(.codex, directory: "/private/tmp")
        precondition(room.notice?.contains("Connect Codex") == true)
        await room.connect(.codex); precondition(room.selectedID == a.id && room.messages.count == 1)
        room.draft = "draft a"; await room.select(b.id); room.draft = "draft b"
        await room.select(a.id); precondition(room.draft == "draft a")
        backend.pauseRead = true
        let read = Task { await room.select(a.id) }
        try await until { backend.readGate != nil }
        backend.onEvent?(.delta(sessionID: a.id, messageID: "stream", text: "Hello "))
        backend.onEvent?(.delta(sessionID: a.id, messageID: "stream", text: "Ada"))
        await room.select(b.id); backend.readGate?.resume(); backend.readGate = nil; await read.value
        precondition(room.selectedID == b.id && room.transcripts[a.id]?.last?.text == "Hello Ada" && room.loadingID == nil)
        backend.onEvent?(.message(sessionID: a.id, CodingMessage(id: "stream", role: .assistant, text: "Hello Ada!")))
        precondition(room.transcripts[a.id]?.filter { $0.id == "stream" }.count == 1)
        await room.select(a.id)
        room.draft = "ask"; await room.send()
        precondition(room.messages.last?.text == "ask")
        backend.onEvent?(.message(sessionID: a.id, CodingMessage(id: "provider-user", role: .user, text: "ask")))
        precondition(room.messages.filter { $0.text == "ask" }.count == 1 && room.messages.last?.id == "provider-user")
        precondition(room.selected?.state == .ready && backend.sent == ["ask"]) // Receipt alone does not start/complete.
        var working = a; working.state = .working; working.managed = true; working.turnID = "t"
        backend.onEvent?(.session(working)); precondition(room.activeCount == 1 && !room.canSend)
        var waiting = working; waiting.state = .waiting; backend.onEvent?(.session(waiting))
        let request = CodingApproval(id: "approval", sessionID: a.id, title: "Question", detail: "", questions: [CodingQuestion(id: "q", title: "Choose", prompt: "Which folder?")])
        backend.onEvent?(.approval(request))
        await room.respond(request, allow: true, answers: [:]); precondition(backend.responses.isEmpty)
        await room.respond(request, allow: true, answers: ["q": "src"]); precondition(room.requests.isEmpty && backend.responses == [request.id])
        await room.respond(request, allow: true, answers: ["q": "src"]); precondition(backend.responses.count == 1)
        var done = working; done.state = .completed; done.turnID = nil; backend.onEvent?(.session(done))
        precondition(room.activeCount == 0 && room.selected?.state == .completed)
        backend.failSend = true; backend.pauseSend = true; room.draft = "rejected"
        let send = Task { await room.send() }; try await until { backend.sendGate != nil }
        precondition(room.draft.isEmpty && room.messages.last?.text == "rejected" && room.sending.contains(a.id))
        room.draft = "new words"; backend.sendGate?.resume(); backend.sendGate = nil; await send.value
        precondition(room.draft == "new words")
        precondition(!room.messages.contains { $0.text == "rejected" })
        let failureID = room.sendFailures[a.id]
        precondition(failureID != nil)
        room.draft = "restore me"; await room.send(); precondition(room.draft == "restore me" && room.sendFailures[a.id] != failureID)
        backend.onEvent?(.session(working)); backend.onEvent?(.approval(request)); room.disconnect(.codex)
        precondition(room.connected.isEmpty && room.selected?.state == .blocked && room.requests.isEmpty)
        room.shutdown()
        // Preserve streamed message order across a single UI batch.
        backend.onEvent?(.delta(sessionID: b.id, messageID: "first", text: "1"))
        backend.onEvent?(.delta(sessionID: b.id, messageID: "second", text: "2"))
        room.flushDeltas(); precondition(room.transcripts[b.id]?.suffix(2).map(\.id) == ["first", "second"])
        // Disconnect while loading must release the reading indicator.
        await room.connect(.codex); backend.pauseRead = true
        let pending = Task { await room.select(a.id) }; try await until { backend.readGate != nil }
        room.disconnect(.codex); backend.readGate?.resume(); backend.readGate = nil; await pending.value
        precondition(room.loadingID == nil)
        let suite = "sieg.room.integration.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["Companion", "Audio", "AI agents", "Timers", "Clipboard", "Calendar", "Team", "System", "Keep awake", "Display & power"], forKey: "island.tools")
        let preferences = CompanionPreferences(defaults: defaults)
        let assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let notch = NotchWidgetViewModel(assistant: assistant, preferences: preferences,
            calendar: IsolatedCalendarFixture.make(defaults: defaults), agentRoom: room, managesWindows: false)
        notch.showAgentRoom(); precondition(notch.presentation == .agentRoom && notch.isVisible)
        notch.collapseAfterPointerExit(); precondition(notch.isVisible && notch.presentation == .agentRoom)
        let draft = room.draft; notch.hide(); notch.showAgentRoom(); precondition(room.draft == draft)
        room.page = .chat
        try await until { notch.geometry.bodyHeight == 404 }
        notch.collapseAfterPointerExit(); precondition(notch.isVisible && notch.presentation == .agentRoom)
        assistant.startFocusSession(minutes: 5)
        assistant.finishPomodoroFromWidget()
        try await until { notch.latestCompletion != nil }
        precondition(notch.isVisible && notch.presentation == .agentRoom && room.page == .chat)
        assistant.resetPomodoro()
        // Flush queued idle notifications before leaving the pinned chat.
        for _ in 0..<20 { try await Task.sleep(for: .milliseconds(1)) }
        precondition(notch.presentation == .agentRoom)
        notch.showTools(); notch.collapseAfterPointerExit(); precondition(!notch.isVisible)
        notch.showAgentRoom(); precondition(room.page == .room)
        precondition(!preferences.toolActions.contains(.avatars) && !IslandToolAction.allCases.contains(.avatars))
        backend.failSend = false
        room.draft = "reconnect and send"
        let beforeConnects = backend.connects
        await room.send()
        precondition(backend.connects == beforeConnects + 1 && backend.sent.last == "reconnect and send")
        room.draft = String(repeating: "a", count: 16_385); await room.send()
        precondition(room.notice?.contains("16 KB") == true && !room.draft.isEmpty)
        notch.stopUtilities()
    }
    @MainActor static func fleetChecks() async throws {
        let backend = RoomFixture()
        let root = CodingSession(provider: .codex, providerID: "fleet-root", title: "Fleet", directory: "/private/tmp", state: .working, managed: true)
        let other = CodingSession(provider: .codex, providerID: "other-room", title: "Other", directory: "/private/tmp", state: .working, managed: true)
        backend.listed = [root, other]
        let room = AgentRoomViewModel(services: [.codex: backend]); await room.connect(.codex); await room.select(root.id)
        for index in 0..<5 {
            backend.onEvent?(.worker(CodingWorker(id: "codex:worker-\(index)", rootID: root.id,
                parentID: index == 4 ? "codex:worker-0" : root.id, provider: .codex, name: "Worker \(index)", task: "Task \(index)",
                state: [.working, .waiting, .blocked, .completed, .working][index], live: true)))
        }
        backend.onEvent?(.worker(CodingWorker(id: "codex:unrelated", rootID: other.id, parentID: other.id, provider: .codex, name: "Other", task: "Other task", state: .working, live: true)))
        precondition(room.roomWorkers.count == 6 && !room.roomWorkers.contains { $0.id == "codex:unrelated" })
        precondition(room.roomWorkers.last?.parentID == "codex:worker-0")
        precondition(room.workers(in: root).count == 6 && room.workers(in: other).count == 2)
        await room.observeRooms([root.id, other.id, root.id])
        precondition(backend.observedRoots == [root.id, other.id])
        await room.select(other.id); precondition(room.roomWorkers.count == 2)
        room.disconnect(.codex); precondition(room.roomWorkers.allSatisfy { !$0.live })
        let now = Date(), earlier = now.addingTimeInterval(-1)
        func record(_ event: String, _ date: Date) -> String {
            "{\"timestamp\":\"\(ISO8601DateFormatter().string(from: date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(event)\"}}\n"
        }
        let active = CodexRoomObservation.parse(Data(record("task_started", earlier).utf8))
        precondition(active.state == .working)
        let finished = CodexRoomObservation.parse(Data(record("task_complete", now).utf8), previous: active)
        precondition(finished.state == .completed)
        let unchanged = CodexRoomObservation.parse(Data(record("task_started", earlier).utf8), previous: finished)
        precondition(unchanged.state == .completed) // Tail replay cannot resurrect old work.
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("owned-observation-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: path) }
        try record("task_started", earlier).write(to: path, atomically: true, encoding: .utf8)
        let initial = CodexRoomObservation.read(path.path)!
        let cached = CodexRoomObservation.read(path.path, previous: initial)!
        precondition(initial.offset == cached.offset && initial.lastSeen == cached.lastSeen)
        let writer = try FileHandle(forWritingTo: path); try writer.seekToEnd()
        let finalLine = record("task_complete", now)
        try writer.write(contentsOf: Data(finalLine.dropLast().utf8))
        let partial = CodexRoomObservation.read(path.path, previous: cached)!
        precondition(partial.state == .working && partial.offset == cached.offset)
        try writer.write(contentsOf: Data([10])); try writer.close()
        let ended = CodexRoomObservation.read(path.path, previous: partial)!
        precondition(ended.state == .completed && ended.offset > partial.offset)
        let parsed = CodexCodingAgent.session(.object(["id": .string("child"), "parentThreadId": .string("fleet-root"), "agentNickname": .string("Review"), "cwd": .string("/private/tmp")]))!
        precondition(parsed.parentID == root.id && parsed.agentName == "Review")
        let fork = CodexCodingAgent.session(.object(["id": .string("fork"), "forkedFromId": .string("fleet-root")]))!
        precondition(fork.parentID == nil) // A fork is not a child agent.
        room.shutdown()
    }
    @MainActor static func composerChecks() async throws {
        let editor = AgentChatEditor()
        var draft = "", sends = 0
        editor.changed = { draft = $0 }; editor.submit = { sends += 1 }
        editor.update(text: "", focusID: "owned")
        editor.stringValue = "Typing without committing"
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(draft == "Typing without committing")
        editor.sendDraft()
        precondition(sends == 1 && draft == editor.stringValue)
        editor.update(text: "", focusID: "other")
        precondition(editor.stringValue.isEmpty)
        let panel = NSPanel(contentRect: NSRect(x: -5000, y: -5000, width: 300, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        editor.frame = NSRect(x: 0, y: 0, width: 300, height: 28); panel.contentView = editor
        precondition(panel.makeFirstResponder(editor))
        editor.selectText(nil)
        guard let fieldEditor = editor.currentEditor() as? NSTextView else { preconditionFailure("Missing owned field editor") }
        fieldEditor.string = "Uncommitted native text"
        editor.update(text: "", focusID: "other") // Unrelated SwiftUI refresh before the edit notification.
        precondition(fieldEditor.string == "Uncommitted native text")
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(draft == "Uncommitted native text")
        editor.sendDraft(); precondition(sends == 2 && draft == "Uncommitted native text")
        panel.makeFirstResponder(nil); panel.close()
    }
    @MainActor static func sendAdmissionChecks() async throws {
        let codex = RoomFixture()
        var external = CodingSession(provider: .codex, providerID: "external", title: "Desktop work", directory: "/private/tmp", state: .working, observed: true, externalOwner: true)
        let other = CodingSession(provider: .codex, providerID: "other", title: "Other", directory: "/private/tmp")
        codex.listed = [external, other]; codex.queueReceipts = true
        let room = AgentRoomViewModel(services: [.codex: codex]); await room.connect(.codex)
        room.draft = "Follow up on desktop work"
        precondition(room.canSend) // External metadata must reach the owner-aware adapter.
        await room.send(to: external.id)
        precondition(codex.sent == ["Follow up on desktop work"] && room.draft.isEmpty)
        precondition(room.messages.last?.id == "queued:1" && room.selected?.state == .working && room.selected?.managed == false)
        precondition(!room.sending.contains(external.id) && room.notice?.contains("Queued in Codex") == true)
        codex.onEvent?(.message(sessionID: external.id, CodingMessage(id: "queued:1", role: .user, text: "Follow up on desktop work")))
        precondition(room.messages.filter { $0.text == "Follow up on desktop work" }.count == 1)
        external.state = .waiting; codex.onEvent?(.session(external))
        room.draft = "Resume through the owner"
        precondition(room.canSend) // A saved waiting label is not an approval owned by Ada.
        await room.send(); precondition(codex.sent.count == 2)
        codex.queueReceipts = false
        external.managed = true; external.state = .working; external.turnID = "owned-turn"
        codex.onEvent?(.session(external)); room.draft = "Steer the attached turn"
        precondition(room.canSend); await room.send(); precondition(codex.sent.count == 3)
        let approval = CodingApproval(id: "owned-approval", sessionID: external.id, title: "Allow?", detail: "")
        codex.onEvent?(.approval(approval)); room.draft = "Keep this draft"
        precondition(!room.canSend); await room.send()
        precondition(codex.sent.count == 3 && room.draft == "Keep this draft" && room.notice?.contains("pending request") == true)
        await room.select(other.id); room.draft = "Another chat's draft"
        await room.send(to: external.id)
        precondition(codex.sent.count == 3 && room.draft == "Another chat's draft" && room.drafts[external.id] == "Keep this draft")
        room.shutdown()
        let claude = RoomFixture(.claude)
        let running = CodingSession(provider: .claude, providerID: "running", title: "Running", directory: "/private/tmp", state: .working, managed: true)
        claude.listed = [running]
        let claudeRoom = AgentRoomViewModel(services: [.claude: claude]); await claudeRoom.connect(.claude)
        claudeRoom.draft = "Do not start overlapping queries"
        precondition(!claudeRoom.canSend); await claudeRoom.send()
        precondition(claude.sent.isEmpty && !claudeRoom.draft.isEmpty && claudeRoom.notice?.contains("still working") == true)
        claudeRoom.shutdown()
    }
    @MainActor static func protocolChecks() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sieg-room-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("runtime.py")
        try codexFixture.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        precondition(CodexCodingAgent.state(.object(["type": .string("active"), "activeFlags": .array([.string("waitingOnApproval")])])) == .waiting)
        precondition(CodexCodingAgent.state(.object(["type": .string("systemError")])) == .blocked)
        let rpc = AgentRPCProcess(), backend = CodexCodingAgent(rpc: rpc, executable: { script })
        var workers: [CodingWorker] = []
        var states: [CodingSession] = [], approvals: [CodingApproval] = [], resolved: [String] = [], texts: [String] = []
        backend.onEvent = { event in
            switch event {
            case .session(let value): states.append(value)
            case .worker(let value): workers.append(value)
            case .approval(let value): approvals.append(value)
            case .resolved(let id): resolved.append(id)
            case .delta(_, _, let text): texts.append(text)
            default: break
            }
        }
        try await backend.connect(); precondition(backend.connected)
        let stored = try await backend.sessions(); precondition(stored.count == 1 && stored[0].state == .unknown)
        let history = try await backend.messages(in: stored[0]); precondition(history.first?.text == "Saved question")
        let session = stored[0]
        try await backend.send("fast", to: session)
        try await until { states.last?.state == .completed }
        precondition(states.last?.turnID == nil && texts.joined() == "Hello Ada")
        let refreshed = try await backend.sessions(); precondition(refreshed.first(where: { $0.id == session.id })?.state == .completed)
        try await backend.send("approval", to: session)
        try await until { !approvals.isEmpty }
        precondition(states.last?.state == .waiting && approvals[0].sessionID == session.id)
        try await backend.respond(to: approvals[0], allow: false, answers: [:])
        try await until { states.last?.state == .completed && resolved.contains(approvals[0].id) }
        try await backend.send("hold", to: session)
        try await until { states.last?.state == .working }
        try await backend.interrupt(session)
        try await until { states.last?.state == .interrupted }
        precondition(states.last?.turnID == nil)
        try await backend.send("unsupported", to: session)
        try await until { states.last?.state == .blocked && states.last?.detail == "Codex reported a runtime error." }
        try await backend.send("fleet", to: session)
        try await until { workers.contains { $0.id == "codex:child-4" && $0.state == .completed } }
        let latestWorkers = Dictionary(workers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        precondition(latestWorkers.count == 5 && latestWorkers.values.allSatisfy { $0.rootID == session.id })
        precondition(latestWorkers["codex:child-0"]?.state == .working && latestWorkers["codex:child-1"]?.state == .interrupted)
        precondition(latestWorkers["codex:child-4"]?.task == "Review the parser")
        // No response: enforce bounded RPC wait and cancellation rather than hanging UI.
        do { _ = try await rpc.request("timeout", timeout: .milliseconds(40)); preconditionFailure("Missing timeout") }
        catch CodingAgentError.timedOut {}
        let cancel = Task { try await rpc.request("timeout") }; cancel.cancel()
        do { _ = try await cancel.value; preconditionFailure("Missing cancellation") } catch is CancellationError {}
        backend.disconnect(); precondition(!rpc.running)
        try rpc.start(script, arguments: [])
        do { _ = try await rpc.request("disconnect"); preconditionFailure("Missing disconnect") } catch CodingAgentError.disconnected {}
        rpc.stop(notify: false)
    }
    @MainActor static func claudeChecks() async throws {
        let node = ClaudeCodingAgent.nodeExecutable()
        precondition(!node.isEmpty, "Node required for the owned SDK fixture")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sieg-sdk-fixture-\(UUID())")
        let package = root.appendingPathComponent("node_modules/@anthropic-ai/claude-agent-sdk")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"name":"@anthropic-ai/claude-agent-sdk","type":"module","exports":"./index.mjs"}"#.write(to: package.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try claudeFixture.write(to: package.appendingPathComponent("index.mjs"), atomically: true, encoding: .utf8)
        var childWorkers: [CodingWorker] = []
        let backend = ClaudeCodingAgent(); var latest: CodingSession?, request: CodingApproval?, resolved = false, text = "", liveIDs: [String] = [], finalText = ""
        backend.onEvent = { event in
            switch event {
            case .session(let value): latest = value
            case .worker(let value): childWorkers.append(value)
            case .approval(let value): request = value
            case .resolved: resolved = true
            case .delta(_, _, let value): text += value
            case .message(_, let value): liveIDs.append(value.id); if value.role == .assistant { finalText = value.text }
            default: break
            }
        }
        backend.configure(node: node, sdkDirectory: root.path, apiKey: "")
        try await backend.connect()
        let stored = try await backend.sessions(); precondition(stored.count == 1 && stored[0].state == .unknown)
        let history = try await backend.messages(in: stored[0]); precondition(history[0].text == "Fixture history")
        do { try await backend.send("hello", to: stored[0]); preconditionFailure("Expected API key requirement") } catch {}
        backend.disconnect()
        backend.configure(node: node, sdkDirectory: root.path, apiKey: "owned-fixture-no-network")
        try await backend.connect()
        let session = try await backend.create(in: root.path)
        let empty = try await backend.messages(in: session); precondition(empty.isEmpty)
        try await backend.send("success", to: session)
        try await until { latest?.state == .completed }
        precondition(text == "Hello Ada")
        let firstHistory = try await backend.messages(in: session)
        precondition(firstHistory.map(\.id) == liveIDs && firstHistory.count == 2)
        let refreshed = try await backend.sessions(); precondition(refreshed.first(where: { $0.id == session.id })?.state == .completed)
        latest = nil; try await backend.send("permission", to: session)
        try await until { request != nil }
        precondition(latest?.state == .waiting)
        try await backend.respond(to: request!, allow: false, answers: [:])
        try await until { latest?.state == .completed && resolved }
        latest = nil; request = nil; resolved = false
        try await backend.send("question", to: session)
        try await until { request?.questions.isEmpty == false }
        precondition(request!.questions[0].id == "Choose a folder?")
        try await backend.respond(to: request!, allow: true, answers: ["Choose a folder?": "src"])
        try await until { latest?.state == .completed && resolved }
        latest = nil; try await backend.send("two-parts", to: session)
        try await until { latest?.state == .completed }
        precondition(finalText == "Hello Ada\n\nNext step")
        let partsHistory = try await backend.messages(in: session)
        precondition(partsHistory.last?.text == finalText)
        latest = nil; try await backend.send("hold", to: session)
        try await until { latest?.state == .working }
        try await backend.interrupt(session)
        try await until { latest?.state == .interrupted }
        latest = nil; try await backend.send("no-result", to: session)
        try await until { latest?.state == .failed }
        latest = nil; childWorkers.removeAll()
        try await backend.send("fleet", to: session)
        try await until { latest?.state == .completed && childWorkers.contains { $0.id.hasSuffix(":worker:child-4") } }
        let latestChildren = Dictionary(childWorkers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        precondition(latestChildren.count == 5)
        precondition(latestChildren.values.allSatisfy { $0.rootID == session.id })
        precondition(latestChildren[session.id + ":worker:child-0"]?.state == .working) // Stale earlier run completion was ignored.
        precondition(latestChildren[session.id + ":worker:child-4"]?.state == .completed)
        let mainHistory = try await backend.messages(in: session)
        precondition(!mainHistory.contains { $0.text == "Child-only output" })
        backend.disconnect()
    }
    static let codexFixture = #"""
    #!/usr/bin/python3
    import sys,json,time
    session={'id':'owned','preview':'Owned fixture','cwd':'/private/tmp','status':{'type':'idle'}}
    def out(x):
      raw=json.dumps(x)+'\n'
      # Split the UTF-8 frame to exercise incremental framing.
      sys.stdout.write(raw[:7]);sys.stdout.flush();sys.stdout.write(raw[7:]);sys.stdout.flush()
    def event(method,params):out({'method':method,'params':params})
    for line in sys.stdin:
      m=json.loads(line);method=m.get('method');p=m.get('params',{});result={}
      if method=='initialize':
        assert p['capabilities']['experimentalApi'] is True;result={}
      elif method=='account/read':result={'account':{'type':'fixture'}}
      elif method=='thread/list':result={'data':[dict(session,status={'type':'notLoaded'})]}
      elif method=='thread/read':
        assert p.get('includeTurns') is False;result={'thread':dict(session,turns=[])}
      elif method=='thread/turns/list':
        assert p.get('sortDirection')=='desc' and p.get('itemsView')=='notLoaded'
        result={'data':[{'id':'history-turn','items':[]}],'nextCursor':None}
      elif method=='thread/items/list':
        assert p.get('sortDirection')=='desc'
        result={'data':[{'turnId':'history-turn','item':{'id':'saved','type':'userMessage','content':[{'type':'text','text':'Saved question'}]}}]}
      elif method=='thread/resume':
        assert p.get('excludeTurns') is True;result={'thread':session}
      elif method=='thread/start':result={'thread':session}
      elif method=='turn/start':
        text=p['input'][0]['text'];turn={'id':text,'status':'inProgress'}
        event('turn/started',{'threadId':'owned','turn':turn})
        if text=='fast':
          event('item/agentMessage/delta',{'threadId':'owned','itemId':'reply','delta':'Hello '})
          event('item/agentMessage/delta',{'threadId':'owned','itemId':'reply','delta':'Ada'})
          event('turn/completed',{'threadId':'owned','turn':{'id':text,'status':'completed'}})
          event('thread/status/changed',{'threadId':'owned','status':{'type':'idle'}})
        elif text=='fleet':
          ids=['child-'+str(i) for i in range(5)]
          item={'id':'spawn','type':'collabAgentToolCall','tool':'spawnAgent','status':'completed','senderThreadId':'owned','receiverThreadIds':ids,'prompt':'Review the parser','agentsStates':{x:{'status':'running'} for x in ids}}
          event('item/completed',{'threadId':'owned','item':item})
          item={**item,'id':'wait','tool':'wait','agentsStates':{'child-0':{'status':'running'},'child-1':{'status':'interrupted'},'child-2':{'status':'errored'},'child-3':{'status':'pendingInit'},'child-4':{'status':'completed','message':'Review done'}}}
          event('item/completed',{'threadId':'owned','item':item})
          event('turn/completed',{'threadId':'owned','turn':{'id':text,'status':'completed'}})
        elif text=='approval':out({'id':42,'method':'item/commandExecution/requestApproval','params':{'threadId':'owned','command':'fixture command'}})
        elif text=='unsupported':out({'id':43,'method':'item/tool/call','params':{'threadId':'owned'}})
        result={'turn':turn}
      elif method=='turn/interrupt':
        event('turn/completed',{'threadId':'owned','turn':{'id':'hold','status':'interrupted'}})
        event('thread/status/changed',{'threadId':'owned','status':{'type':'idle'}})
      elif m.get('id')==42 and not method:
        assert m['result']['decision']=='decline'
        event('serverRequest/resolved',{'threadId':'owned','requestId':42})
        event('turn/completed',{'threadId':'owned','turn':{'id':'approval','status':'completed'}})
        continue
      elif m.get('id')==43 and not method:
        assert m['error']['code']==-32601
        event('turn/completed',{'threadId':'owned','turn':{'id':'unsupported','status':'failed'}})
        # Error notification must not erase terminal state in the adapter.
        event('error',{'threadId':'owned'})
        continue
      elif method=='timeout':continue
      elif method=='disconnect':sys.exit(0)
      if 'id' in m:out({'id':m['id'],'result':result})
    """#
    static let claudeFixture = #"""
    export async function listSessions(){return [{sessionId:'saved',summary:'Stored fixture',cwd:'/private/tmp'}];}
    const histories=new Map();
    export async function getSessionMessages(id){if(id==='saved')return [{uuid:'saved-msg',type:'user',message:{content:'Fixture history'}}];return histories.get(id)??[];}
    export async function* query({prompt:input,options}){
      const envelope=(await input[Symbol.asyncIterator]().next()).value;
      const prompt=envelope.message.content, reply='reply-'+envelope.uuid;
      if(!envelope.uuid)throw Error('Missing stable UUID');
      if(options.permissionMode!=='default'||options.settingSources.length!==0)throw Error('Fixture permissions');
      const id=options.resume??options.extraArgs['session-id'];
      histories.set(id,[...(histories.get(id)??[]),{uuid:envelope.uuid,type:'user',message:envelope.message}]);
      yield {type:'system',subtype:'init',session_id:id};
      if(prompt==='hold'){
        await new Promise((resolve,reject)=>{if(options.abortController.signal.aborted)return reject(Error('aborted'));options.abortController.signal.addEventListener('abort',()=>reject(Error('aborted')),{once:true});});return;
      }
      if(prompt==='permission')await options.canUseTool('Bash',{command:'fixture command'},{});
      if(prompt==='question'){
        const decision=await options.canUseTool('AskUserQuestion',{questions:[{question:'Choose a folder?',header:'Folder',options:[{label:'src'}]}]},{});
        if(decision.updatedInput.answers['Choose a folder?']!=='src')throw Error('Wrong question answer');
      }
      if(prompt==='no-result')return;
      if(prompt==='fleet'){
        yield {type:'system',subtype:'task_started',task_id:'shell',task_type:'local_bash',description:'Not an agent'};
        for(let i=0;i<5;i++){
          yield {type:'system',subtype:'task_started',task_id:'child-'+i,run_id:'new-'+i,task_type:'local_agent',description:'Review part '+i,parent_task_id:i===4?'child-0':undefined};
          yield {type:'system',subtype:'task_progress',task_id:'child-'+i,run_id:'new-'+i,description:'Review part '+i,last_tool_name:'Read'};
        }
        yield {type:'system',subtype:'task_notification',task_id:'child-0',run_id:'old-0',status:'completed',summary:'Stale completion'};
        yield {type:'assistant',agent_id:'child-4',parent_tool_use_id:'tool-child',message:{id:'child-msg',content:[{type:'text',text:'Child-only output'}]}};
        yield {type:'system',subtype:'task_notification',task_id:'child-4',run_id:'new-4',status:'completed',summary:'Review done'};
      }
      yield {type:'stream_event',event:{type:'message_start',message:{id:reply}}};
      yield {type:'stream_event',event:{delta:{type:'text_delta',text:'Hello Ada'}}};
      const assistant={uuid:'stored-'+envelope.uuid,type:'assistant',message:{id:reply,content:[{type:'text',text:'Hello Ada'}]}};
      histories.set(id,[...histories.get(id),assistant]);yield assistant;
      if(prompt==='two-parts'){
        const part={uuid:'part-'+envelope.uuid,type:'assistant',message:{id:reply,content:[{type:'text',text:'Next step'}]}};
        histories.set(id,[...histories.get(id),part]);yield part;
      }
      yield {type:'result',subtype:'success',is_error:false,result:'Hello Ada'};
    }
    """#
}

