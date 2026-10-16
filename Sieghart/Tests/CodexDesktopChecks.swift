import Foundation
import SQLite3

@MainActor enum CodexDesktopChecks {
    static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owned-codex-desktop-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = "11111111-1111-4111-8111-111111111111"
        func sql(_ name: String, _ statements: String) {
            var database: OpaquePointer?
            precondition(sqlite3_open(folder.appendingPathComponent(name).path, &database) == SQLITE_OK)
            defer { sqlite3_close(database) }
            precondition(sqlite3_exec(database, statements, nil, nil, nil) == SQLITE_OK)
        }
        sql("state_5.sqlite", """
          CREATE TABLE threads(id TEXT PRIMARY KEY, source TEXT, agent_path TEXT, agent_nickname TEXT,
          originator TEXT, cwd TEXT, name TEXT, title TEXT, updated_at INTEGER, rollout_path TEXT, history_mode TEXT);
          CREATE TABLE thread_spawn_edges(parent_thread_id TEXT, child_thread_id TEXT PRIMARY KEY, status TEXT);
          INSERT INTO threads VALUES('\(root)', 'vscode', NULL, NULL, 'codex_work_desktop', '/private/tmp', 'Actual selected chat', '', 100, NULL, 'paginated');
          INSERT INTO threads VALUES('active-a', '{"subagent":{"thread_spawn":{"parent_thread_id":"\(root)","agent_path":"/root/parser_work"}}}', '/root/parser_work', 'Nickname', NULL, '/private/tmp', NULL, 'Parser task', 200, NULL, 'paginated');
          INSERT INTO threads VALUES('active-b', '{}', '/root/review_work', 'Nickname', NULL, '/private/tmp', NULL, 'Review task', 200, NULL, 'paginated');
          INSERT INTO threads VALUES('old-completed', '{}', '/root/old_work', NULL, NULL, '/private/tmp', NULL, 'Old task', 50, NULL, 'paginated');
          INSERT INTO threads VALUES('nested', '{}', '/root/nested_work', NULL, NULL, '/private/tmp', NULL, 'Nested task', 200, NULL, 'paginated');
          INSERT INTO threads VALUES('unrelated', '{}', NULL, NULL, NULL, '/private/tmp', 'Other chat', '', 300, NULL, 'paginated');
          INSERT INTO thread_spawn_edges VALUES('\(root)', 'active-a', 'open'), ('\(root)', 'active-b', 'open'), ('\(root)', 'old-completed', 'open'), ('active-a', 'nested', 'open');
          """)
        sql("thread_history_1.sqlite", """
          CREATE TABLE thread_turns(thread_id TEXT, turn_id TEXT, status TEXT, started_at INTEGER, completed_at INTEGER, rollout_ordinal INTEGER);
          CREATE TABLE thread_items(thread_id TEXT, item_type TEXT, created_at_ms INTEGER, item_json TEXT);
          INSERT INTO thread_turns VALUES('active-a','a','inProgress',100,NULL,1), ('active-b','b','inProgress',100,NULL,1),
          ('old-completed','c','completed',40,50,1), ('nested','n','completed',40,50,1), ('unrelated','u','inProgress',100,NULL,1);
          INSERT INTO thread_items VALUES('active-a','agentMessage',200,'{"id":"reply-a","type":"agentMessage","text":"Actual fixture update"}');
          INSERT INTO thread_items VALUES('unrelated','agentMessage',200,'{"id":"reply-u","type":"agentMessage","text":"Must not enter this room"}');
          """)
        let entries = CodexDesktopStore.tree(root, directory: folder)
        precondition(entries.count == 5 && entries.first?.session.title == "Actual selected chat")
        precondition(entries.first?.session.externalOwner == true)
        precondition(entries.filter { $0.session.observed && $0.session.state == .working }.count == 2)
        precondition(entries.first { $0.session.providerID == "active-a" }?.session.agentName == "parser work")
        precondition(entries.first { $0.session.providerID == "nested" }?.session.parentID == "codex:active-a")
        precondition(!entries.contains { $0.session.providerID == "unrelated" })
        precondition(entries.first { $0.session.providerID == "active-a" }?.messages.last?.text == "Actual fixture update")
        sql("thread_history_1.sqlite", "UPDATE thread_turns SET status='completed',completed_at=210 WHERE thread_id='active-b';")
        let updated = CodexDesktopStore.tree(root, directory: folder)
        precondition(updated.filter { $0.session.observed && $0.session.state == .working }.count == 1)
        let lower = CodexCodingAgent.session(.object(["id": .string("child"), "source": .string(#"{"subagent":{"thread_spawn":{"parent_thread_id":"parent","agent_path":"/root/fix_send"}}}"#)]))!
        precondition(lower.parentID == "codex:parent" && lower.agentName == "fix send")
        let confirmed = CodexCodingAgent.message(.object(["id": .string("server-item"), "clientId": .string("queued-client-id"), "type": .string("userMessage"), "content": .array([.object(["type": .string("text"), "text": .string("Queued fixture text")])])]))!
        precondition(confirmed.id == "queued-client-id" && confirmed.text == "Queued fixture text")

        let script = folder.appendingPathComponent("owned-runtime.py")
        try fixture.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let backend = CodexCodingAgent(executable: { script }, desktopDirectory: folder)
        var queued: [(String, String)] = [], workers: [String: CodingWorker] = [:]
        var messages: [CodingMessage] = []
        backend.onEvent = { event in
            switch event {
            case .queued(let id, let messageID): queued.append((id, messageID))
            case .worker(let worker): workers[worker.id] = worker
            case .message(_, let message): messages.append(message)
            default: break
            }
        }
        try await backend.connect()
        let listed = try await backend.sessions()
        precondition(listed[0].externalOwner)
        try await backend.send("A desktop queue message", to: listed[0])
        // The fixture rejects any attempt to resume the desktop-owned root.
        precondition(queued.count == 1 && queued[0].0 == "codex:" + root)
        try await backend.send("Writer-conflict fallback", to: listed[1])
        precondition(queued.count == 2 && queued[1].0 == "codex:writer-conflict")
        try await backend.observeRoom(listed[0])
        precondition(workers.count == 4 && workers.values.filter { $0.live && $0.state == .working }.count == 1)
        precondition(messages.contains { $0.text == "Actual fixture update" })
        // The observer's later content timestamp can be more precise than
        // the persisted completion timestamp. It must not preserve working.
        let tail = folder.appendingPathComponent("owned-tail.jsonl")
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let completionSecond = floor(Date().timeIntervalSince1970)
        let contentDate = Date(timeIntervalSince1970: completionSecond + 0.9)
        let record: [String: Any] = ["timestamp": formatter.string(from: contentDate), "type": "response_item", "payload": ["type": "function_call", "name": "fixture_tool", "arguments": "{}"]]
        var recordData = try JSONSerialization.data(withJSONObject: record); recordData.append(10)
        try recordData.write(to: tail)
        let quotedPath = tail.path.replacingOccurrences(of: "'", with: "''")
        sql("state_5.sqlite", "UPDATE threads SET rollout_path='\(quotedPath)' WHERE id='active-a';")
        try await backend.observeRoom(listed[0])
        precondition(workers["codex:active-a"]?.state == .working)
        sql("thread_history_1.sqlite", "UPDATE thread_turns SET status='completed', completed_at=\(Int(completionSecond)) WHERE thread_id='active-a';")
        try await backend.observeRoom(listed[0])
        precondition(workers["codex:active-a"]?.state == .completed)
        precondition(workers.values.filter { $0.state == .working }.isEmpty)
        let child = entries.first { $0.session.providerID == "active-a" }!.session
        do { try await backend.send("Do not directly resume this child", to: child); preconditionFailure("Expected parent ownership guard") }
        catch CodingAgentError.unavailable(let reason) { precondition(reason.contains("controlled by its parent")) }
        backend.disconnect()
    }
    static let fixture = #"""
    #!/usr/bin/python3
    import sys,json
    root='11111111-1111-4111-8111-111111111111'
    for line in sys.stdin:
      m=json.loads(line); method=m.get('method'); p=m.get('params',{}); result={}
      if method=='initialize': result={}
      elif method=='account/read': result={'account':{'type':'fixture'}}
      elif method=='thread/list':
        assert p['sortKey']=='updated_at' and 'subAgent' in p['sourceKinds']
        result={'data':[{'id':root,'name':'Actual selected chat','originator':'codex_work_desktop','status':{'type':'notLoaded'}},{'id':'writer-conflict','status':{'type':'notLoaded'}}]}
      elif method=='thread/resume':
        assert p['threadId']=='writer-conflict', 'Desktop root must queue without resuming'
        sys.stdout.write(json.dumps({'id':m['id'],'error':{'code':-32600,'message':'thread writer-conflict already has an active writer'}})+'\n');sys.stdout.flush();continue
      elif method=='thread/queue/add':
        assert p['threadId'] in [root,'writer-conflict'] and p['input'][0]['text']
        assert p['clientUserMessageId']
        result={'queuedSubmission':{'id':'queue-fixture','clientUserMessageId':p['clientUserMessageId'],'input':p['input']}}
      elif method=='turn/start': raise AssertionError('Never start a new writer for the desktop root')
      if 'id' in m: sys.stdout.write(json.dumps({'id':m['id'],'result':result})+'\n');sys.stdout.flush()
    """#
}
