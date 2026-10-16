import Foundation

@MainActor final class CodexCodingAgent: CodingAgentServing {
    let provider = AIProvider.codex
    private(set) var connected = false
    var onEvent: ((CodingAgentEvent) -> Void)?
    private let rpc: AgentRPCProcess
    private let executable: () -> URL?
    private var known: [String: CodingSession] = [:]
    private var approvals: [String: (wireID: AgentJSON, method: String, sessionID: String)] = [:]
    private var finishedTurns = Set<String>()
    private var workers: [String: CodingWorker] = [:]
    private var observations: [String: CodexRoomSnapshot] = [:]
    private var lastTreeRefresh = Date.distantPast
    private let desktopDirectory: URL
    private var observedMessages: [String: [CodingMessage]] = [:]
    // thread/start creates a loaded thread before its first user message is
    // materialized. The history pager rejects that valid empty conversation.
    private var emptyThreads = Set<String>()
    init(rpc: AgentRPCProcess = AgentRPCProcess(), executable: @escaping () -> URL? = LocalCodexUsage.executable,
         desktopDirectory: URL = CodexDesktopStore.directory) {
        self.rpc = rpc; self.executable = executable; self.desktopDirectory = desktopDirectory
        rpc.onMessage = { [weak self] in self?.receive($0) }
        rpc.onDisconnect = { [weak self] in self?.connected = false; self?.approvals.removeAll(); self?.onEvent?(.disconnected("Codex disconnected.")) }
    }
    func connect() async throws {
        guard !connected else { return }
        guard let executable = executable() else { throw CodingAgentError.unavailable("Install Codex or its CLI, sign in there, then connect.") }
        try rpc.start(executable, arguments: ["app-server", "--listen", "stdio://"])
        do {
            _ = try await rpc.request("initialize", params: .object(["clientInfo": .object(["name": .string("sieghart_ada"), "title": .string("Sieghart · Ada"), "version": .string("0.1.0")]), "capabilities": .object(["experimentalApi": .bool(true)])]))
            try rpc.send(.object(["method": .string("initialized"), "params": .object([:])]))
            let account = try await rpc.request("account/read", params: .object(["refreshToken": .bool(false)]))
            guard account["account"] != .null else { throw CodingAgentError.unavailable("Sign in through Codex or codex login, then reconnect Ada.") }
            connected = true
        } catch { rpc.stop(notify: false); throw error }
    }
    func disconnect() { connected = false; approvals.removeAll(); known.removeAll(); workers.removeAll(); observations.removeAll(); observedMessages.removeAll(); emptyThreads.removeAll(); lastTreeRefresh = .distantPast; finishedTurns.removeAll(); rpc.stop(notify: false) }
    func sessions() async throws -> [CodingSession] {
        let result = try await rpc.request("thread/list", params: .object(["limit": .number(100), "sortKey": .string("updated_at"), "useStateDbOnly": .bool(true), "sourceKinds": .array(["cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"].map(AgentJSON.string))]))
        let listed = result["data"].array.compactMap { value -> CodingSession? in
            guard var session = Self.session(value) else { return nil }
            if let current = known[session.id] {
                session.externalOwner = session.externalOwner || current.externalOwner
                if current.managed || current.observed { session.managed = current.managed; session.observed = current.observed; session.state = current.state; session.turnID = current.turnID; session.detail = current.detail }
            }
            known[session.id] = session; return session
        }
        for session in listed { publishWorker(session) }
        // A freshly created thread need not appear in the state DB until its
        // first turn. Keep the runtime-owned conversation visible on refresh.
        let listedIDs = Set(listed.map(\.id))
        let retained = known.values.filter { $0.managed && !listedIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
        return listed + retained
    }
    func messages(in session: CodingSession) async throws -> [CodingMessage] {
        guard !emptyThreads.contains(session.id) else { return [] }
        let result = try await rpc.request("thread/read", params: .object(["threadId": .string(session.providerID), "includeTurns": .bool(false)]))
        // Reading a saved transcript does not replace an attached turn's live state.
        if known[session.id]?.managed != true, let update = Self.session(result["thread"]) { merge(update) }
        // The newest CLI stores paginated history. Reading or resuming every
        // tool output in one response can disconnect an otherwise healthy chat.
        let page: AgentJSON
        do {
            page = try await rpc.request("thread/turns/list", params: .object(["threadId": .string(session.providerID), "limit": .number(30), "sortDirection": .string("desc"), "itemsView": .string("notLoaded")]))
        } catch CodingAgentError.unavailable(let reason) where reason.contains("unavailable before first user message") {
            // The first turn can be accepted before its history is persisted.
            // Other protocol/history errors still surface to the user.
            return []
        }
        var messages: [CodingMessage] = []
        for turn in page["data"].array.reversed() {
            guard let turnID = turn["id"].string else { continue }
            let items = try await rpc.request("thread/items/list", params: .object(["threadId": .string(session.providerID), "turnId": .string(turnID), "limit": .number(100), "sortDirection": .string("desc")]))
            for entry in items["data"].array.reversed() {
                let item = entry["item"]
                collab(item, live: false)
                if let message = Self.message(item) { messages.append(message) }
            }
        }
        return Array(messages.suffix(100))
    }
    func observeRoom(_ session: CodingSession) async throws {
        guard connected else { return }
        if Date().timeIntervalSince(lastTreeRefresh) >= 9 {
            lastTreeRefresh = .now
            _ = try await sessions() // Cached state DB metadata, includes child identities.
        }
        let directory = desktopDirectory, rawRoot = session.providerID
        let persisted = await Task.detached(priority: .utility) { CodexDesktopStore.tree(rawRoot, directory: directory) }.value
        guard connected, !Task.isCancelled else { return }
        for entry in persisted {
            var value = entry.session
            if let existing = known[value.id], existing.managed { continue }
            value.externalOwner = value.externalOwner || known[value.id]?.externalOwner == true
            if var snapshot = entry.snapshot {
                if let previous = observations[value.id] {
                    // Keep the legacy tail cursor: resetting it on each DB
                    // refresh would repeatedly parse hundreds of KB per agent.
                    snapshot.offset = previous.offset
                    if snapshot.lastSeen < previous.lastSeen {
                        // Turn status is authoritative. A later tool/content
                        // timestamp (or subsecond rounding) must not resurrect
                        // a completed persisted turn as still working.
                        snapshot.lastSeen = previous.lastSeen
                        if snapshot.detail.isEmpty { snapshot.detail = previous.detail }
                    }
                }
                observations[value.id] = snapshot; value.detail = snapshot.detail
                value.state = snapshot.state ?? value.state
            }
            if value != known[value.id] { known[value.id] = value; onEvent?(.session(value)) }
            publishWorker(value)
            for message in entry.messages where observedMessages[value.id]?.contains(message) != true {
                onEvent?(.message(sessionID: value.id, message))
            }
            observedMessages[value.id] = entry.messages
        }
        var entries = known.values.filter { rootID($0.id) == session.id }
        if !entries.contains(where: { $0.id == session.id }) { entries.append(session) }
        entries = Array(entries.prefix(32))
        let previous = observations
        let snapshots = await Task.detached(priority: .utility) {
            entries.compactMap { entry -> (String, CodexRoomSnapshot)? in
                guard let path = entry.historyPath, let snapshot = CodexRoomObservation.read(path, previous: previous[entry.id]) else { return nil }
                return (entry.id, snapshot)
            }
        }.value
        guard connected, !Task.isCancelled else { return }
        for (id, snapshot) in snapshots {
            observations[id] = snapshot
            guard var entry = known[id], let state = snapshot.state, !entry.managed else { continue }
            entry.state = state; entry.observed = entry.observed || Date().timeIntervalSince(snapshot.lastSeen) < 30
            entry.detail = snapshot.detail
            if entry.externalOwner, entry.parentID == nil, !state.busy,
               let updated = entry.updatedAt, updated.timeIntervalSince(snapshot.lastSeen) > 30 {
                entry.state = .unknown; entry.observed = false
                entry.detail = "Codex owns this chat. Its live parent status is unavailable; subagent activity is updated separately."
            }
            if known[id] != entry { known[id] = entry; onEvent?(.session(entry)) }
            if let parent = entry.parentID {
                let worker = CodingWorker(id: id, rootID: rootID(id), parentID: parent, provider: .codex,
                    name: entry.agentName ?? entry.title, task: snapshot.task.isEmpty ? workers[id]?.task ?? entry.title : snapshot.task,
                    state: entry.state, detail: snapshot.detail, live: entry.observed, threadID: id)
                if workers[id] != worker { workers[id] = worker; onEvent?(.worker(worker)) }
            }
        }
    }
    func create(in directory: String) async throws -> CodingSession {
        let result = try await rpc.request("thread/start", params: .object(["cwd": .string(directory), "approvalPolicy": .string("untrusted"), "sandbox": .string("workspace-write")]))
        guard var session = Self.session(result["thread"]) else { throw CodingAgentError.invalidResponse }
        emptyThreads.insert(session.id)
        if session.title == "Codex session" { session.title = "New Codex chat" }
        session.managed = true; session.state = .ready; merge(session); return session
    }
    func send(_ text: String, to session: CodingSession) async throws {
        guard connected, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 16_384 else { throw CodingAgentError.unavailable("Connect first and keep each message under 16 KB.") }
        var current = known[session.id] ?? session
        guard current.parentID == nil || current.managed else {
            throw CodingAgentError.unavailable("This subagent is controlled by its parent. Open Ada’s conversation to send instructions.")
        }
        if current.externalOwner && !current.managed {
            try await queue(text, to: current); return
        }
        if !current.managed {
            let result: AgentJSON
            do {
                result = try await rpc.request("thread/resume", params: .object(["threadId": .string(session.providerID), "excludeTurns": .bool(true), "approvalPolicy": .string("untrusted"), "sandbox": .string("workspace-write")]))
            } catch CodingAgentError.unavailable(let reason) where reason.contains("already has an active writer") {
                current.externalOwner = true; known[current.id] = current; onEvent?(.session(current))
                try await queue(text, to: current); return
            }
            guard let resumed = Self.session(result["thread"]) else { throw CodingAgentError.invalidResponse }
            current = resumed; current.managed = true; merge(current)
        }
        let input: AgentJSON = .array([.object(["type": .string("text"), "text": .string(text)])])
        if current.state == .working, let turn = current.turnID {
            _ = try await rpc.request("turn/steer", params: .object(["threadId": .string(current.providerID), "expectedTurnId": .string(turn), "input": input]))
        } else {
            let result = try await rpc.request("turn/start", params: .object(["threadId": .string(current.providerID), "input": input, "approvalPolicy": .string("untrusted")]))
            emptyThreads.remove(session.id)
            let turn = result["turn"]["id"].string
            if let turn, !finishedTurns.contains(turn) {
                current = known[session.id] ?? current
                current.turnID = turn; current.state = current.state == .waiting ? .waiting : .working
                current.managed = true; merge(current)
            }
        }
    }
    private func queue(_ text: String, to session: CodingSession) async throws {
        let clientID = UUID().uuidString.lowercased()
        do {
            let receipt = try await rpc.request("thread/queue/add", params: .object([
                "threadId": .string(session.providerID), "clientUserMessageId": .string(clientID),
                "input": .array([.object(["type": .string("text"), "text": .string(text), "textElements": .array([])])])
            ]))
            guard let messageID = receipt["queuedSubmission"]["clientUserMessageId"].string,
                  receipt["queuedSubmission"]["id"].string != nil else { throw CodingAgentError.invalidResponse }
            onEvent?(.queued(sessionID: session.id, messageID: messageID))
        } catch CodingAgentError.unavailable(let reason) {
            if reason.contains("unknown variant") || reason.contains("Method not found") || reason.contains("queue is unavailable") {
                throw CodingAgentError.unavailable("This Codex version cannot receive queued messages from Ada. Update Codex, or send this message in its existing chat.")
            }
            throw CodingAgentError.unavailable(reason)
        }
    }
    func interrupt(_ session: CodingSession) async throws {
        guard let current = known[session.id], current.managed, let turn = current.turnID else { throw CodingAgentError.unavailable("Ada can interrupt only turns attached to this runtime.") }
        _ = try await rpc.request("turn/interrupt", params: .object(["threadId": .string(current.providerID), "turnId": .string(turn)]))
        // Wait for turn/completed with interrupted status; an RPC receipt is not completion.
    }
    func respond(to approval: CodingApproval, allow: Bool, answers: [String: String]) async throws {
        guard let entry = approvals[approval.id], entry.sessionID == approval.sessionID else { throw CodingAgentError.unavailable("This request has already been resolved.") }
        let (wireID, method) = (entry.wireID, entry.method)
        let result: AgentJSON
        if method == "item/tool/requestUserInput" {
            result = .object(["answers": .object(allow ? answers.mapValues { .object(["answers": .array([.string($0)])]) } : [:])])
        } else if method == "item/permissions/requestApproval" {
            result = .object(["permissions": .object([:]), "scope": .string("turn")])
        } else { result = .object(["decision": .string(allow && approval.canAllow ? "accept" : "decline")]) }
        try rpc.send(.object(["id": wireID, "result": result])); approvals[approval.id] = nil; onEvent?(.resolved(approvalID: approval.id))
    }
    private func merge(_ incoming: CodingSession) {
        var value = incoming
        if let previous = known[value.id] {
            value.managed = value.managed || previous.managed
            value.externalOwner = value.externalOwner || previous.externalOwner
            if value.state.busy { value.turnID = value.turnID ?? previous.turnID }
        }
        known[value.id] = value; onEvent?(.session(value))
        publishWorker(value)
    }
    private func rootID(_ id: String) -> String {
        var root = id, visited = Set<String>()
        while visited.insert(root).inserted, let parent = known[root]?.parentID { root = parent }
        return root
    }
    private func publishWorker(_ session: CodingSession) {
        guard let parent = session.parentID else { return }
        let old = workers[session.id]
        var worker = CodingWorker(id: session.id, rootID: rootID(session.id), parentID: parent, provider: .codex,
            name: session.agentName ?? old?.name ?? session.title, task: old?.task ?? session.title,
            state: session.state, detail: session.detail.isEmpty ? old?.detail ?? "" : session.detail, live: session.managed || session.observed, threadID: session.id)
        // Metadata refreshes never erase a live collab observation.
        if let old, old.live && !session.managed && !session.observed && session.state == .unknown { worker.state = old.state; worker.live = true }
        guard workers[worker.id] != worker else { return }
        workers[worker.id] = worker; onEvent?(.worker(worker))
    }
    private func collab(_ item: AgentJSON, live: Bool) {
        guard item["type"].string == "collabAgentToolCall", let rawSender = item["senderThreadId"].string else { return }
        let sender = "codex:" + rawSender, tool = item["tool"].string
        for rawID in item["receiverThreadIds"].array.compactMap(\.string) {
            let id = "codex:" + rawID, old = workers[id], stored = known[id]
            // A collaboration receipt does not prove the target finished.
            let report = item["agentsStates"][rawID], reported = report["status"].string
            let state: CodingAgentState
            switch reported {
            case "running": state = .working
            case "completed": state = .completed
            case "errored": state = .failed
            case "interrupted", "shutdown": state = .interrupted
            case "pendingInit": state = .ready
            default: state = old?.state ?? .unknown
            }
            let prompt = ["spawnAgent", "sendInput", "followupTask", "sendMessage"].contains(tool ?? "") ? item["prompt"].string : nil
            let worker = CodingWorker(id: id, rootID: old?.rootID ?? rootID(sender), parentID: stored?.parentID ?? old?.parentID ?? sender,
                provider: .codex, name: stored?.agentName ?? old?.name ?? "Agent " + String(rawID.prefix(6)),
                task: String((prompt ?? old?.task ?? stored?.title ?? "No task reported").prefix(1000)), state: state,
                detail: String((report["message"].string ?? old?.detail ?? "").prefix(4000)), live: live && reported != nil, threadID: id)
            if !live, let old, old.live { continue }
            workers[id] = worker; onEvent?(.worker(worker))
            if known[id] == nil {
                let child = CodingSession(provider: .codex, providerID: rawID, title: worker.name,
                    directory: known[sender]?.directory ?? "", state: state, parentID: worker.parentID, agentName: worker.name)
                known[id] = child; onEvent?(.session(child))
            }
        }
    }
    private func receive(_ packet: AgentJSON) {
        guard let method = packet["method"].string else { return }
        let params = packet["params"]
        if method == "serverRequest/resolved" {
            for (id, entry) in approvals where entry.wireID == params["requestId"] {
                approvals[id] = nil; onEvent?(.resolved(approvalID: id))
            }
            return
        }
        if method == "thread/started", let value = Self.session(params["thread"]) { merge(value); return }
        guard let rawID = params["threadId"].string else { return }
        let id = provider.rawValue + ":" + rawID
        var current = known[id] ?? CodingSession(provider: provider, providerID: rawID, title: "Codex session", directory: "")
        if packet["id"] != .null {
            guard ["item/tool/requestUserInput", "item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval"].contains(method) else {
                try? rpc.send(.object(["id": packet["id"], "error": .object(["code": .number(-32601), "message": .string("This request is not supported by Sieghart.")])]))
                current.state = .blocked; current.detail = "This tool needs a compatible Codex client."; merge(current); return
            }
            let approvalID = UUID().uuidString
            var approval = CodingApproval(id: approvalID, sessionID: id, title: "Codex needs your decision", detail: String((params["command"].string ?? params["reason"].string ?? method).prefix(4000)))
            if method == "item/tool/requestUserInput" {
                approval.questions = params["questions"].array.compactMap { value in
                    guard let questionID = value["id"].string else { return nil }
                    return CodingQuestion(id: questionID, title: value["header"].string ?? "Question", prompt: value["question"].string ?? "", options: value["options"].array.compactMap { $0["label"].string })
                }
            } else if !["item/commandExecution/requestApproval", "item/fileChange/requestApproval"].contains(method) {
                // Unsupported wider grants are denied, never silently approved.
                approval.canAllow = false; approval.detail = "This permission type is not supported here. Decline it or continue in Codex."
            }
            approvals[approvalID] = (packet["id"], method, id); current.state = .waiting; merge(current); onEvent?(.approval(approval)); return
        }
        switch method {
        case "thread/status/changed":
            let state = Self.state(params["status"])
            if state == .ready && [.completed, .interrupted, .failed].contains(current.state) { return }
            current.state = state; merge(current)
        case "turn/started": current.turnID = params["turn"]["id"].string; current.state = .working; current.managed = true; merge(current)
        case "turn/completed":
            if let turn = params["turn"]["id"].string { finishedTurns.insert(turn) }
            let state = params["turn"]["status"].string
            current.state = state == "completed" ? .completed : state == "interrupted" ? .interrupted : .failed
            current.detail = state == "failed" ? "The provider reported a failed turn." : ""; current.turnID = nil; merge(current)
            for (key, entry) in approvals where entry.sessionID == id { approvals[key] = nil; onEvent?(.resolved(approvalID: key)) }
        case "item/agentMessage/delta":
            if let text = params["delta"].string, let messageID = params["itemId"].string { onEvent?(.delta(sessionID: id, messageID: messageID, text: text)) }
        case "item/started", "item/completed":
            collab(params["item"], live: true)
            if let message = Self.message(params["item"]) {
                onEvent?(.message(sessionID: id, message))
                if var worker = workers[id] {
                    worker.detail = String(message.text.prefix(4000)); worker.live = true
                    workers[id] = worker; onEvent?(.worker(worker))
                }
            }
        case "error": current.state = .blocked; current.detail = "Codex reported a runtime error."; merge(current)
        default: break
        }
    }
    static func state(_ value: AgentJSON) -> CodingAgentState {
        switch value["type"].string {
        case "idle": .ready
        case "active": value["activeFlags"].array.contains(where: { ["waitingOnApproval", "waitingOnUserInput"].contains($0.string ?? "") }) ? .waiting : .working
        case "systemError": .blocked
        default: .unknown
        }
    }
    static func session(_ value: AgentJSON) -> CodingSession? {
        guard let id = value["id"].string else { return nil }
        let name = value["name"].string ?? value["preview"].string ?? "Codex session"
        let rawSource = value["source"].string.flatMap { try? JSONDecoder().decode(AgentJSON.self, from: Data($0.utf8)) } ?? value["source"]
        let spawn = rawSource["subAgent"]["thread_spawn"] == .null ? rawSource["subagent"]["thread_spawn"] : rawSource["subAgent"]["thread_spawn"]
        let parent = value["parentThreadId"].string ?? spawn["parent_thread_id"].string
        let agentName = spawn["agent_path"].string?.split(separator: "/").last.map { String($0).replacingOccurrences(of: "_", with: " ") } ?? value["agentNickname"].string ?? spawn["agent_nickname"].string
        var result = CodingSession(provider: .codex, providerID: id, title: String((name.isEmpty ? "Codex session" : name).prefix(120)), directory: value["cwd"].string ?? "", state: state(value["status"]), updatedAt: value["updatedAt"].number.map { Date(timeIntervalSince1970: $0) }, parentID: parent.map { "codex:" + $0 }, agentName: agentName, historyPath: value["path"].string)
        result.externalOwner = value["originator"].string?.contains("desktop") == true
        return result
    }
    nonisolated static func message(_ value: AgentJSON) -> CodingMessage? {
        guard let id = value["id"].string else { return nil }
        switch value["type"].string {
        case "userMessage":
            let text = value["content"].array.compactMap { $0["text"].string }.joined(separator: "\n")
            // A queue receipt carries clientUserMessageId; the final stored
            // item retains that identity as clientId alongside its server id.
            return CodingMessage(id: value["clientId"].string ?? id, role: .user, text: String(text.prefix(16_384)))
        case "agentMessage": return CodingMessage(id: id, role: .assistant, text: String((value["text"].string ?? "").prefix(32_768)))
        case "commandExecution": return CodingMessage(id: id, role: .tool, text: String((value["command"].string ?? "Command").prefix(300)) + " · " + (value["status"].string ?? "inProgress"))
        case "fileChange": return CodingMessage(id: id, role: .tool, text: "File changes · " + (value["status"].string ?? "inProgress"))
        default: return nil
        }
    }
    static func messages(_ thread: AgentJSON) -> [CodingMessage] {
        Array(thread["turns"].array.suffix(30).flatMap { $0["items"].array.compactMap(message) }.suffix(100))
    }
}
