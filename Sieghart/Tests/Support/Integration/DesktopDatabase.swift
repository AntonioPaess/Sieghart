import Foundation
import SQLite3
import Testing

@MainActor final class IntegrationDesktopDatabase {
    let directory: IntegrationDirectory
    var folder: URL { directory.url }
    let root = "11111111-1111-4111-8111-111111111111"
    init() throws {
        directory = try IntegrationDirectory("desktop-sqlite")
        try sql("state_5.sqlite", """
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
        try sql("thread_history_1.sqlite", """
          CREATE TABLE thread_turns(thread_id TEXT, turn_id TEXT, status TEXT, started_at INTEGER, completed_at INTEGER, rollout_ordinal INTEGER);
          CREATE TABLE thread_items(thread_id TEXT, item_type TEXT, created_at_ms INTEGER, item_json TEXT);
          INSERT INTO thread_turns VALUES('active-a','a','inProgress',100,NULL,1), ('active-b','b','inProgress',100,NULL,1),
          ('old-completed','c','completed',40,50,1), ('nested','n','completed',40,50,1), ('unrelated','u','inProgress',100,NULL,1);
          INSERT INTO thread_items VALUES('active-a','agentMessage',200,'{"id":"reply-a","type":"agentMessage","text":"Actual fixture update"}');
          INSERT INTO thread_items VALUES('unrelated','agentMessage',200,'{"id":"reply-u","type":"agentMessage","text":"Must not enter this room"}');
          """)
    }
    func sql(_ name: String, _ statements: String) throws {
        var pointer: OpaquePointer?
        try #require(sqlite3_open(folder.appendingPathComponent(name).path, &pointer) == SQLITE_OK)
        defer { sqlite3_close(pointer) }
        try #require(sqlite3_exec(pointer, statements, nil, nil, nil) == SQLITE_OK)
    }
    func cleanup() { directory.cleanup() }
}
