import Foundation

struct CodexRoomSnapshot: Sendable {
    var state: CodingAgentState?
    var task = ""
    var detail = ""
    var lastSeen = Date.distantPast
    var offset: UInt64 = 0
}
// Passive, bounded reading of the selected tree's official rollout paths. No
// inference, resume, hooks, keyboard injection or unrelated transcript scan.
enum CodexRoomObservation {
    static func read(_ path: String, previous: CodexRoomSnapshot? = nil) -> CodexRoomSnapshot? {
        guard path.hasPrefix("/"), path.hasSuffix(".jsonl"),
              let file = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? file.close() }
        guard let length = try? file.seekToEnd() else { return nil }
        let validPrevious = previous.flatMap { $0.offset <= length ? $0 : nil }
        if let validPrevious, validPrevious.offset == length { return validPrevious }
        let limit: UInt64 = validPrevious == nil ? 262_144 : 65_536
        let cursor = validPrevious?.offset ?? 0
        let start = max(cursor, length > limit ? length - limit : 0)
        try? file.seek(toOffset: start)
        guard let data = try? file.read(upToCount: Int(limit)) else { return nil }
        // Do not consume a record while another process is still writing it.
        let complete = data.lastIndex(of: 10).map { data.prefix($0 + 1) } ?? Data.SubSequence()
        var result = parse(Data(complete), dropsFirst: start > cursor, previous: validPrevious)
        result.offset = start + UInt64(complete.count)
        return result
    }
    static func parse(_ data: Data, dropsFirst: Bool = false, previous: CodexRoomSnapshot? = nil) -> CodexRoomSnapshot {
        var result = previous ?? CodexRoomSnapshot()
        let lines = data.split(separator: 10)
        for line in dropsFirst ? lines.dropFirst() : lines[...] {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = value["payload"] as? [String: Any],
                  let timestamp = value["timestamp"] as? String, let date = AIActivityParser.parseDate(timestamp), date >= result.lastSeen else { continue }
            result.lastSeen = date
            if value["type"] as? String == "event_msg" {
                switch payload["type"] as? String {
                case "task_started": result.state = .working
                case "task_complete": result.state = .completed
                case "turn_aborted": result.state = .interrupted
                case "user_message": result.task = String((payload["message"] as? String ?? "").prefix(1000))
                case "agent_message": result.detail = String((payload["message"] as? String ?? "").prefix(4000))
                default: break
                }
            }
            if value["type"] as? String == "response_item", payload["type"] as? String == "function_call" {
                let name = payload["name"] as? String ?? "Tool"
                var detail = name
                if let raw = payload["arguments"] as? String, raw.utf8.count < 65_536,
                   let fields = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                   let command = fields["cmd"] as? String ?? fields["command"] as? String { detail += " · " + String(command.prefix(300)) }
                result.detail = String(detail.prefix(4000))
            }
        }
        return result
    }
}
