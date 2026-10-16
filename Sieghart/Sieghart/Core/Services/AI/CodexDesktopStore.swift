import Foundation
import SQLite3

// The public app-server currently lists only a recent page. This read-only
// compatibility reader discovers the selected tree from Codex's persisted
// spawn edges, including children created by another desktop connection.
// No authentication files, unrelated transcripts, writes or writer locks.
enum CodexDesktopStore {
    struct Entry: Sendable {
        var session: CodingSession
        var snapshot: CodexRoomSnapshot?
        var messages: [CodingMessage] = []
    }
    static var directory: URL {
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"], configured.hasPrefix("/") {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }
    static func tree(_ rawRoot: String, directory: URL = directory, includeMessages: Bool = true) -> [Entry] {
        guard rawRoot.utf8.count < 200, !rawRoot.isEmpty,
              let state = Database(directory.appendingPathComponent("state_5.sqlite")) else { return [] }
        let rows = state.rows("""
            WITH RECURSIVE family(id, parent_id, depth) AS (
              SELECT ?, NULL, 0
              UNION ALL
              SELECT edges.child_thread_id, edges.parent_thread_id, family.depth + 1
              FROM thread_spawn_edges edges JOIN family ON edges.parent_thread_id = family.id
              WHERE family.depth < 8
              LIMIT 64
            )
            SELECT t.id, family.parent_id, t.source, t.agent_path, t.agent_nickname,
                   t.originator, t.cwd, COALESCE(t.name, t.title), t.updated_at,
                   t.rollout_path, t.history_mode
            FROM family JOIN threads t ON t.id = family.id
            ORDER BY family.depth, t.updated_at DESC LIMIT 64
            """, bindings: [rawRoot])
        let history = Database(directory.appendingPathComponent("thread_history_1.sqlite"))
        return rows.compactMap { row -> Entry? in
            guard row.count == 11, let rawID = row[0] else { return nil }
            let source = row[2].flatMap { try? JSONDecoder().decode(AgentJSON.self, from: Data($0.utf8)) } ?? .null
            let spawn = source["subagent"]["thread_spawn"]
            let path = row[3] ?? spawn["agent_path"].string
            let label = path.flatMap { $0.split(separator: "/").last.map(String.init) }
            var session = CodingSession(provider: .codex, providerID: rawID,
                title: String((row[7] ?? "Codex session").prefix(120)), directory: row[6] ?? "",
                updatedAt: row[8].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)),
                parentID: (row[1] ?? spawn["parent_thread_id"].string).map { "codex:" + $0 },
                agentName: label?.replacingOccurrences(of: "_", with: " ") ?? row[4], historyPath: row[9])
            session.externalOwner = row[5]?.contains("desktop") == true
            var snapshot: CodexRoomSnapshot?
            if let turn = history?.rows("SELECT status, started_at, completed_at, turn_id FROM thread_turns WHERE thread_id = ? ORDER BY started_at DESC, rollout_ordinal DESC LIMIT 1", bindings: [rawID]).first,
               let status = turn[0] {
                let state: CodingAgentState
                switch status {
                case "inProgress": state = .working
                case "completed": state = .completed
                case "interrupted": state = .interrupted
                case "failed": state = .failed
                default: state = .unknown
                }
                let stamp = (turn[2] ?? turn[1]).flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
                snapshot = CodexRoomSnapshot(state: state, task: session.title, lastSeen: stamp)
                session.state = state; session.turnID = state.busy ? turn[3] : nil
                // Long tool runs can be silent for minutes. Their persisted
                // in-progress turn is evidence; a 30-second silence is not idle.
                session.observed = state.busy || Date().timeIntervalSince(stamp) < 30
                if session.parentID == nil, session.externalOwner, !state.busy,
                   let updated = session.updatedAt, updated.timeIntervalSince(stamp) > 30 {
                    session.state = .unknown; session.observed = false
                    snapshot?.state = .unknown
                    snapshot?.detail = "Codex owns this chat. Its live parent status is unavailable; subagent activity is updated separately."
                }
            }
            var messages: [CodingMessage] = []
            if includeMessages, let history {
                // Filter before loading JSON: large command outputs never enter
                // the observer. Messages remain confined to this selected tree.
                let limit = rawID == rawRoot ? 24 : 2
                for item in history.rows("SELECT substr(item_json, 1, 65536) FROM thread_items WHERE thread_id = ? AND item_type IN ('userMessage', 'agentMessage') ORDER BY created_at_ms DESC LIMIT \(limit)", bindings: [rawID]).reversed() {
                    guard let text = item[0], let json = try? JSONDecoder().decode(AgentJSON.self, from: Data(text.utf8)),
                          let message = CodexCodingAgent.message(json) else { continue }
                    messages.append(message)
                }
            }
            if let message = messages.last(where: { $0.role == .assistant }) { snapshot?.detail = String(message.text.prefix(4000)) }
            if let task = messages.last(where: { $0.role == .user }) { snapshot?.task = String(task.text.prefix(1000)) }
            return Entry(session: session, snapshot: snapshot, messages: messages)
        }
    }
    private final class Database {
        let handle: OpaquePointer
        init?(_ url: URL) {
            var opened: OpaquePointer?
            guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
                  let opened else { if let opened { sqlite3_close(opened) }; return nil }
            handle = opened; sqlite3_busy_timeout(opened, 100)
        }
        deinit { sqlite3_close(handle) }
        func rows(_ sql: String, bindings: [String]) -> [[String?]] {
            var prepared: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else { return [] }
            defer { sqlite3_finalize(prepared) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (index, value) in bindings.enumerated() {
                _ = value.withCString { sqlite3_bind_text(prepared, Int32(index + 1), $0, -1, transient) }
            }
            var result: [[String?]] = []
            while result.count < 64, sqlite3_step(prepared) == SQLITE_ROW {
                result.append((0..<sqlite3_column_count(prepared)).map { column in
                    sqlite3_column_text(prepared, column).map { String(cString: $0) }
                })
            }
            return result
        }
    }
}
