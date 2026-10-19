import Foundation
import SQLite3

struct AIUsagePoint: Codable, Sendable, Identifiable {
    let id: String
    let provider: AIProvider
    let date: Date
    let model: String
    let project: String
    let input: Int64
    let output: Int64
    let cached: Int64
    var cacheCreation: Int64 = 0
    var cacheCreationLong: Int64 = 0
    var serviceTier: String?
    var perRequest = true
    var total: Int64 { input + output }
}

struct AIWork: Sendable, Equatable, Identifiable {
    let id: String
    let provider: AIProvider
    let model: String
    let project: String
    let startedAt: Date
    let lastSeen: Date
    let output: Int64
    func isCurrent(at now: Date) -> Bool { startedAt <= now && now.timeIntervalSince(lastSeen) < 300 }
    func elapsed(at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct AIAnalytics: Sendable {
    var points: [AIUsagePoint] = []
    var work: [AIWork] = []
    var scannedFiles = 0
    var partial = true
    func filtered(provider: AIProvider, since: Date) -> [AIUsagePoint] { points.filter { $0.provider == provider && $0.date >= since } }
}

// Only select metadata, usage counters and lifecycle types from JSON records.
// No prompts, tool arguments, responses, credentials or conversation bodies are retained.
enum AIActivityParser {
    static func parse(_ url: URL, provider: AIProvider, now: Date = .now, knownWork: AIWork? = nil, fullHistory: Bool = false, usesResponseRecords: Bool = false) -> AIAnalytics {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return AIAnalytics() }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd() else { return AIAnalytics() }
        let offset = !fullHistory && length > 2_097_152 ? length - 2_097_152 : 0
        var project = "Local project", headerSession: String?
        // The first record identifies a Codex project; only its basename survives.
        try? handle.seek(toOffset: 0)
        if let head = try? handle.read(upToCount: 65_536), let first = head.split(separator: 10).first,
           let record = object(first), let payload = record["payload"] as? [String: Any], let cwd = payload["cwd"] as? String {
            project = URL(fileURLWithPath: cwd).lastPathComponent
            headerSession = payload["id"] as? String
        }
        // Recover the context immediately before the tail for historical
        // counters too, even when the turn is already complete.
        let older = provider == .codex && offset > 0 ? olderCodexState(handle, before: offset, length: length) : nil
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: fullHistory ? 67_108_864 : 2_097_152) else { return AIAnalytics() }
        let lines = data.split(separator: 10)
        var session = headerSession ?? LocalTokenReader.conversationID(for: url)
        let agyMeta = provider == .antigravity ? antigravityMetadata(for: url, session: session) : (stepModels: [], initialProject: nil)
        var model = older?.model ?? agyMeta.stepModels.first?.model ?? (provider == .antigravity ? "gemini-antigravity" : "Unknown model"), started: Date?, turnID: String?, lastSeen = Date.distantPast
        if provider == .antigravity && project == "Local project" { project = agyMeta.initialProject ?? "Antigravity" }
        let homeName = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        var sawLifecycle = false, serviceTier = older?.tier, sawResponseRecords = usesResponseRecords
        var output: Int64 = 0, previous: [Int64]?, points: [String: AIUsagePoint] = [:]
        let cutoff = now.addingTimeInterval(-(fullHistory ? 365 : 91) * 86400)
        for line in offset > 0 ? lines.dropFirst() : lines[...] {
            if Task.isCancelled || points.count >= 30000 { break }
            guard let record = object(line),
                  let timestamp = (record["timestamp"] as? String) ?? (record["created_at"] as? String),
                  let date = parseDate(timestamp) else { continue }
            let type = record["type"] as? String
            if provider == .codex {
                guard let payload = record["payload"] as? [String: Any] else { continue }
                if type == "session_meta", let identifier = payload["id"] as? String, !identifier.isEmpty { session = String(identifier.prefix(128)) }
                if type == "token_usage_record", let fields = payload["usage"] as? [String: Any] {
                    sawResponseRecords = true
                    lastSeen = max(lastSeen, date)
                    let values = counts(fields, claude: false)
                    if let recordedModel = payload["model"] as? String, !recordedModel.isEmpty { model = recordedModel }
                    let tier = payload["service_tier"] as? String ?? serviceTier
                    let response = payload["response_id"] as? String
                    let key = response.flatMap { $0.isEmpty ? nil : "codex:response:" + $0 } ?? "codex:response:\(session):\(timestamp)"
                    if date >= cutoff, date <= now, values[0] + values[1] > 0 {
                        if let old = points[key], old.total > values[0] + values[1] { continue }
                        let prior = points[key]?.output ?? 0
                        points[key] = AIUsagePoint(id: key, provider: provider, date: date, model: model, project: project, input: values[0], output: values[1], cached: values[2], cacheCreation: values[3], serviceTier: tier, perRequest: true)
                        output += max(0, values[1] - prior)
                    }
                    continue
                }
                if type == "turn_context" {
                    model = payload["model"] as? String ?? model
                    serviceTier = payload["service_tier"] as? String ?? serviceTier
                    if let cwd = payload["cwd"] as? String { project = URL(fileURLWithPath: cwd).lastPathComponent }
                }
                guard type == "event_msg", let event = payload["type"] as? String else { continue }
                if event == "thread_settings_applied", let settings = payload["thread_settings"] as? [String: Any], let tier = settings["service_tier"] as? String { serviceTier = tier }
                if event == "task_started" { sawLifecycle = true; started = date; turnID = payload["turn_id"] as? String; output = 0 }
                if ["task_complete", "turn_aborted"].contains(event) { sawLifecycle = true; started = nil; turnID = nil }
                lastSeen = max(lastSeen, date)
                guard !sawResponseRecords, event == "token_count", let info = payload["info"] as? [String: Any], let cumulative = info["total_token_usage"] as? [String: Any] else { continue }
                let current = counts(cumulative, claude: false)
                if previous == current { continue }
                var delta: [Int64]
                if let last = info["last_token_usage"] as? [String: Any] { delta = counts(last, claude: false) }
                else if let previous { delta = zip(current, previous).map { max(0, $0 - $1) } }
                else { delta = offset == 0 ? current : [0, 0, 0, 0] }
                if let previous, current[0] + current[1] <= previous[0] + previous[1] { continue }
                previous = current
                delta[2] = min(delta[0], delta[2]); delta[3] = min(delta[3], max(0, delta[0] - delta[2]))
                output += delta[1]
                guard date >= cutoff, date <= now, delta[0] + delta[1] > 0 else { continue }
                let id = "codex:total:\(session):\(current[0] + current[1])"
                points[id] = AIUsagePoint(id: id, provider: provider, date: date, model: model, project: project, input: delta[0], output: delta[1], cached: delta[2], cacheCreation: delta[3], serviceTier: serviceTier, perRequest: info["last_token_usage"] != nil)
            } else if provider == .claude {
                if let cwd = record["cwd"] as? String { project = URL(fileURLWithPath: cwd).lastPathComponent }
                if type == "user", started == nil { started = date; turnID = record["uuid"] as? String; output = 0 }
                if type == "system", record["subtype"] as? String == "turn_duration" { started = nil }
                lastSeen = max(lastSeen, date)
                guard type == "assistant", let message = record["message"] as? [String: Any] else { continue }
                model = message["model"] as? String ?? model
                if message["stop_reason"] as? String == "end_turn" { started = nil }
                guard let usage = message["usage"] as? [String: Any], let id = message["id"] as? String, date >= cutoff, date <= now else { continue }
                let count = counts(usage, claude: true)
                let key = "claude:\(id)"
                if let earlier = points[key], earlier.total >= count[0] + count[1] { continue }
                points[key] = AIUsagePoint(id: key, provider: provider, date: date, model: model, project: project, input: count[0], output: count[1], cached: count[2], cacheCreation: count[3], cacheCreationLong: min(count[3], Self.count((usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"])), serviceTier: usage["service_tier"] as? String)
                output = count[1]
            } else {
                if let cwd = record["cwd"] as? String, !cwd.isEmpty {
                    let candidate = URL(fileURLWithPath: cwd).lastPathComponent
                    if !candidate.isEmpty, candidate != homeName { project = candidate }
                } else if let calls = record["tool_calls"] as? [[String: Any]] {
                    for call in calls {
                        let args = (call["args"] as? [String: Any]) ?? (call["arguments"] as? [String: Any])
                        if let rawCwd = args?["Cwd"] as? String {
                            let cleaned = rawCwd.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                            let candidate = URL(fileURLWithPath: cleaned).lastPathComponent
                            if !cleaned.isEmpty, !candidate.isEmpty, candidate != homeName, UUID(uuidString: candidate) == nil {
                                project = candidate
                                break
                            }
                        }
                    }
                }
                let stepNum = (record["step_index"] as? NSNumber)?.intValue
                if let recordedModel = record["model"] as? String, !recordedModel.isEmpty {
                    model = recordedModel
                } else if let stepNum, !agyMeta.stepModels.isEmpty {
                    for entry in agyMeta.stepModels {
                        if entry.step <= stepNum { model = entry.model } else { break }
                    }
                }
                let status = record["status"] as? String
                let step = record["step_index"].map { "\($0)" } ?? timestamp
                if type == "USER_INPUT" || status == "RUNNING" {
                    if started == nil { started = date; turnID = step; output = 0 }
                }
                lastSeen = max(lastSeen, date)
                if type == "PLANNER_RESPONSE" || record["source"] as? String == "MODEL" {
                    if record["tool_calls"] == nil && status == "DONE" { started = nil }
                    let fresh = Self.count(record["input_tokens"]), cached = Self.count(record["cache_read_tokens"]), created = Self.count(record["cache_creation_tokens"]), out = Self.count(record["output_tokens"])
                    let totalInput = fresh + cached + created
                    guard date >= cutoff, date <= now, totalInput + out > 0 else { continue }
                    let key = "antigravity:\(session):\(step)"
                    if let earlier = points[key], earlier.total >= totalInput + out { continue }
                    points[key] = AIUsagePoint(id: key, provider: .antigravity, date: date, model: model, project: project, input: totalInput, output: out, cached: cached, cacheCreation: created)
                    output += out
                }
            }
        }
        // Long-running turns can start before the counter tail. Search only
        // lifecycle/context records in bounded older chunks; never infer work
        // from a recent file modification or token event alone.
        if provider == .codex, !sawLifecycle, offset > 0, now.timeIntervalSince(lastSeen) < 300 {
            if let knownWork {
                started = knownWork.startedAt; turnID = knownWork.id.split(separator: ":").last.map(String.init)
                if model == "Unknown model" { model = knownWork.model }
            } else if let state = older {
                started = state.started; turnID = state.turnID
                if model == "Unknown model", let known = state.model { model = known }
            }
        }
        var work: [AIWork] = []
        if let started, now.timeIntervalSince(started) < 8 * 3600, model != "codex-auto-review" {
            let task = AIWork(id: "\(session):\(turnID ?? "turn")", provider: provider, model: model, project: project, startedAt: started, lastSeen: lastSeen, output: output)
            if task.isCurrent(at: now) { work = [task] }
        }
        return AIAnalytics(points: Array(points.values), work: work, scannedFiles: 1)
    }
    private static func olderCodexState(_ handle: FileHandle, before offset: UInt64, length: UInt64) -> (started: Date?, turnID: String?, model: String?, tier: String?)? {
        var cursor = offset, model: String?, tier: String?, state: (Date?, String?)?, scanned: UInt64 = 0
        while cursor > 0 && scanned < 268_435_456 {
            let begin = cursor > 524_288 ? cursor - 524_288 : 0
            try? handle.seek(toOffset: begin)
            // Overlap gives complete metadata lines at chunk boundaries.
            guard let chunk = try? handle.read(upToCount: Int(min(length - begin, cursor - begin + 524_288))) else { break }
            let lines = chunk.split(separator: 10)
            for line in (begin > 0 ? lines.dropFirst() : lines[...]).reversed() {
                guard begin + UInt64(line.startIndex) < cursor else { continue }
                guard line.range(of: Data("task_started".utf8)) != nil || line.range(of: Data("task_complete".utf8)) != nil || line.range(of: Data("turn_aborted".utf8)) != nil || line.range(of: Data("turn_context".utf8)) != nil || line.range(of: Data("thread_settings_applied".utf8)) != nil else { continue }
                guard let record = object(line), let payload = record["payload"] as? [String: Any] else { continue }
                if tier == nil, (payload["type"] as? String) == "thread_settings_applied" { tier = (payload["thread_settings"] as? [String: Any])?["service_tier"] as? String }
                if model == nil, record["type"] as? String == "turn_context" { model = payload["model"] as? String; tier = tier ?? payload["service_tier"] as? String }
                if state == nil, record["type"] as? String == "event_msg", let type = payload["type"] as? String {
                    if type == "task_started", let stamp = record["timestamp"] as? String, let date = parseDate(stamp) { state = (date, payload["turn_id"] as? String) }
                    else if ["task_complete", "turn_aborted"].contains(type) { state = (nil, nil) }
                }
                if let state, model != nil { return (state.0, state.1, model, tier) }
            }
            scanned += cursor - begin; cursor = begin
        }
        if state != nil || model != nil { return (state?.0, state?.1, model, tier) }
        return nil
    }
    private static func object(_ line: Data.SubSequence) -> [String: Any]? { try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] }
    private static func count(_ value: Any?) -> Int64 {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, (0...1_000_000_000_000).contains(n.doubleValue) else { return 0 }
        return n.int64Value
    }
    private static func counts(_ fields: [String: Any], claude: Bool) -> [Int64] {
        let input = count(fields["input_tokens"]), output = count(fields["output_tokens"])
        let cache = count(fields[claude ? "cache_read_input_tokens" : "cached_input_tokens"])
        let creation = count(fields[claude ? "cache_creation_input_tokens" : "cache_write_input_tokens"])
        return [input + (claude ? cache + creation : 0), output, claude ? cache : min(input, cache), claude ? creation : min(max(0, input - cache), creation)]
    }
    static func parseDate(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }

    private static func antigravityMetadata(for url: URL, session: String) -> (stepModels: [(step: Int, model: String)], initialProject: String?) {
        let components = url.pathComponents
        guard let brainIdx = components.lastIndex(of: "brain"), brainIdx > 0 else { return ([], nil) }
        let agyRoot = URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(brainIdx))))
        let geminiRoot = agyRoot.deletingLastPathComponent()

        var initialProject: String?
        let summariesDB = geminiRoot.appendingPathComponent("antigravity/conversation_summaries.db")
        if FileManager.default.fileExists(atPath: summariesDB.path) {
            var db: OpaquePointer?
            if sqlite3_open_v2(summariesDB.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db {
                defer { sqlite3_close(db) }
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "SELECT project_id FROM conversation_summaries WHERE conversation_id = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK, let stmt {
                    defer { sqlite3_finalize(stmt) }
                    _ = session.withCString { sqlite3_bind_text(stmt, 1, $0, -1, nil) }
                    if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                        let pid = String(cString: cStr)
                        if !pid.isEmpty, pid != "outside-of-project" {
                            let projFile = geminiRoot.appendingPathComponent("config/projects/\(pid).json")
                            if let data = try? Data(contentsOf: projFile),
                               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let name = obj["name"] as? String, !name.isEmpty {
                                initialProject = URL(fileURLWithPath: name).lastPathComponent
                            }
                        }
                    }
                }
            }
        }

        var stepModels: [(step: Int, model: String)] = []
        let convDB = agyRoot.appendingPathComponent("conversations/\(session).db")
        if FileManager.default.fileExists(atPath: convDB.path) {
            var db: OpaquePointer?
            if sqlite3_open_v2(convDB.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db {
                defer { sqlite3_close(db) }
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "SELECT idx, data FROM gen_metadata ORDER BY idx", -1, &stmt, nil) == SQLITE_OK, let stmt {
                    defer { sqlite3_finalize(stmt) }
                    let stepTag = Data("last_step_index\u{12}".utf8)
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let idx = Int(sqlite3_column_int(stmt, 0))
                        let len = Int(sqlite3_column_bytes(stmt, 1))
                        guard len > 0, let raw = sqlite3_column_blob(stmt, 1) else { continue }
                        let blob = Data(bytes: raw, count: len)
                        guard let modelName = extractProtobufModel(from: blob) else { continue }
                        let stepIndex = extractStepIndex(from: blob, tag: stepTag) ?? idx
                        stepModels.append((step: stepIndex, model: modelName))
                    }
                }
            }
        }
        return (stepModels, initialProject)
    }

    private static func extractProtobufModel(from blob: Data) -> String? {
        let bytes = [UInt8](blob)
        guard bytes.count > 4 else { return nil }
        for i in 0..<(bytes.count - 3) {
            if bytes[i] == 0x9A && bytes[i + 1] == 0x01 {
                let length = Int(bytes[i + 2])
                guard length >= 5, length <= 64, i + 3 + length <= bytes.count else { continue }
                let slice = bytes[(i + 3)..<(i + 3 + length)]
                let valid = slice.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F }
                if valid, let str = String(bytes: slice, encoding: .utf8),
                   (str.hasPrefix("gemini-") || str.hasPrefix("claude-") || str.hasPrefix("gpt-")) {
                    return str
                }
            }
        }
        return nil
    }

    private static func extractStepIndex(from blob: Data, tag: Data) -> Int? {
        guard let range = blob.range(of: tag), range.upperBound < blob.endIndex else { return nil }
        let len = Int(blob[range.upperBound])
        let start = range.upperBound + 1
        guard len >= 1, len <= 8, start + len <= blob.endIndex else { return nil }
        guard let str = String(data: blob[start..<(start + len)], encoding: .utf8) else { return nil }
        return Int(str)
    }
}

actor AIAnalyticsReader {
    private struct Cached { let modified: Date; let size: Int; let value: AIAnalytics }
    private var cache: [URL: Cached] = [:]
    private var files: [AIProvider: [URL]] = [:]
    private var discovered: [AIProvider: Date] = [:]
    private var history: [String: AIUsagePoint] = [:]
    private let home: URL
    private let codexHome: URL?
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, codexHome: URL? = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }) {
        self.home = home; self.codexHome = codexHome
    }
    func read(providers: [AIProvider], now: Date = .now) -> AIAnalytics {
        var scannedBytes = 0
        var result = AIAnalytics(), unique = history.filter { providers.contains($0.value.provider) && now.timeIntervalSince($0.value.date) <= 365 * 86400 }, work: [String: AIWork] = [:]
        for provider in providers {
            if discovered[provider].map({ now.timeIntervalSince($0) >= 60 }) ?? true {
                let candidates = LocalTokenReader.discoverFiles(for: provider, home: home, codexHome: codexHome)
                files[provider] = candidates.sorted { $0.1 > $1.1 }.prefix(80).map(\.0); discovered[provider] = now
            }
            for url in files[provider] ?? [] {
                var freshURL = url
                freshURL.removeAllCachedResourceValues()
                guard let info = try? freshURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { continue }
                let modified = info.contentModificationDate ?? .distantPast, size = info.fileSize ?? 0
                if cache[url]?.modified != modified || cache[url]?.size != size {
                    let old = cache[url]
                    let initial = old == nil || size < (old?.size ?? 0)
                    let scanAll = initial && size <= 67_108_864 && scannedBytes + size <= 536_870_912
                    scannedBytes += scanAll ? size : min(size, 2_097_152)
                    var updated = AIActivityParser.parse(url, provider: provider, now: now, knownWork: old?.value.work.first, fullHistory: scanAll, usesResponseRecords: !initial && (old?.value.points.contains { $0.id.hasPrefix("codex:response:") } ?? false))
                    if !initial, let old {
                        var retained = Dictionary(old.value.points.filter { now.timeIntervalSince($0.date) <= 365 * 86400 }.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.total >= b.total ? a : b })
                        for point in updated.points {
                            if let prior = retained[point.id], prior.total > point.total { continue }
                            retained[point.id] = point
                        }
                        updated.points = Array(retained.values.prefix(30000))
                    }
                    cache[url] = Cached(modified: modified, size: size, value: updated)
                }
                guard let reading = cache[url]?.value else { continue }
                result.scannedFiles += 1
                for point in reading.points {
                    if let existing = unique[point.id], existing.total > point.total || (existing.total == point.total && (existing.model != "Unknown model" || point.model == "Unknown model")) { continue }
                    unique[point.id] = point
                }
                for task in reading.work where task.isCurrent(at: now) { work[task.id] = task }
            }
        }
        files = files.filter { providers.contains($0.key) }; discovered = discovered.filter { providers.contains($0.key) }
        let retained = Set(files.values.flatMap { $0 }); cache = cache.filter { retained.contains($0.key) }
        history = history.filter { providers.contains($0.value.provider) }; result.points = unique.values.sorted { $0.date < $1.date }
        result.work = work.values.sorted { $0.startedAt > $1.startedAt }
        return result
    }
    // Explicit broader scan, off the main actor, bounded in files, bytes and
    // retained counters. Ordinary five-second polling remains a recent tail.
    func readFullHistory(providers: [AIProvider], now: Date = .now) -> AIAnalytics {
        var unique: [String: AIUsagePoint] = [:], scanned = 0, bytes = 0
        for provider in providers {
            let candidates = LocalTokenReader.discoverFiles(for: provider, home: home, codexHome: codexHome, includeArchived: true)
                .filter { $0.2 <= 67_108_864 }
            for (url, _, size) in candidates.sorted(by: { $0.1 > $1.1 }) {
                if Task.isCancelled || scanned >= 1000 || bytes + size > 536_870_912 || unique.count >= 30000 { break }
                let result = AIActivityParser.parse(url, provider: provider, now: now, fullHistory: true)
                scanned += 1; bytes += size
                for point in result.points {
                    if unique.count >= 30000 && unique[point.id] == nil { break }
                    if let old = unique[point.id], old.total > point.total || (old.total == point.total && old.model != "Unknown model") { continue }
                    unique[point.id] = point
                }
            }
        }
        guard !Task.isCancelled else { return AIAnalytics() }
        history = unique
        var result = read(providers: providers, now: now)
        result.scannedFiles = scanned
        return result
    }

}

enum InstalledAIProviders {
    static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Set<AIProvider> {
        var result = Set<AIProvider>()
        if LocalCodexUsage.executable() != nil || FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex/sessions").path) { result.insert(.codex) }
        let claudePaths = [ClaudePlanHistory.location(home: home).path, home.appendingPathComponent(".claude/projects").path, home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if claudePaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { result.insert(.claude) }
        let antigravityPaths = [
            home.appendingPathComponent(".gemini/antigravity/brain").path,
            home.appendingPathComponent(".gemini/antigravity/installation_id").path,
            "/Applications/Antigravity.app"
        ]
        if antigravityPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { result.insert(.antigravity) }
        return result
    }
}
