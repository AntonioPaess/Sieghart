import Foundation

struct AIUsagePoint: Sendable, Identifiable {
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
    static func parse(_ url: URL, provider: AIProvider, now: Date = .now, knownWork: AIWork? = nil) -> AIAnalytics {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return AIAnalytics() }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd() else { return AIAnalytics() }
        let offset = length > 2_097_152 ? length - 2_097_152 : 0
        var project = "Local project"
        // The first record identifies a Codex project; only its basename survives.
        try? handle.seek(toOffset: 0)
        if let head = try? handle.read(upToCount: 65_536), let first = head.split(separator: 10).first,
           let record = object(first), let payload = record["payload"] as? [String: Any], let cwd = payload["cwd"] as? String {
            project = URL(fileURLWithPath: cwd).lastPathComponent
        }
        // Recover the context immediately before the tail for historical
        // counters too, even when the turn is already complete.
        let older = provider == .codex && offset > 0 ? olderCodexState(handle, before: offset, length: length) : nil
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return AIAnalytics() }
        let lines = data.split(separator: 10)
        let session = UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.suffix(36)))?.uuidString ?? url.path
        var model = older?.model ?? "Unknown model", started: Date?, turnID: String?, lastSeen = Date.distantPast
        var sawLifecycle = false, serviceTier = older?.tier
        var output: Int64 = 0, previous: [Int64]?, points: [String: AIUsagePoint] = [:]
        let cutoff = now.addingTimeInterval(-91 * 86400)
        for line in offset > 0 ? lines.dropFirst() : lines[...] {
            guard let record = object(line), let timestamp = record["timestamp"] as? String, let date = parseDate(timestamp) else { continue }
            let type = record["type"] as? String
            if provider == .codex {
                guard let payload = record["payload"] as? [String: Any] else { continue }
                if type == "turn_context" {
                    model = payload["model"] as? String ?? model
                    serviceTier = payload["service_tier"] as? String
                    if let cwd = payload["cwd"] as? String { project = URL(fileURLWithPath: cwd).lastPathComponent }
                }
                guard type == "event_msg", let event = payload["type"] as? String else { continue }
                if event == "task_started" { sawLifecycle = true; started = date; turnID = payload["turn_id"] as? String; output = 0 }
                if ["task_complete", "turn_aborted"].contains(event) { sawLifecycle = true; started = nil; turnID = nil }
                lastSeen = max(lastSeen, date)
                guard event == "token_count", let info = payload["info"] as? [String: Any], let cumulative = info["total_token_usage"] as? [String: Any] else { continue }
                let current = counts(cumulative, claude: false)
                if previous == current { continue }
                let delta: [Int64]
                if let last = info["last_token_usage"] as? [String: Any] { delta = counts(last, claude: false) }
                else if let previous { delta = zip(current, previous).map { max(0, $0 - $1) } }
                else { delta = offset == 0 ? current : [0, 0, 0, 0] }
                previous = current
                output += delta[1]
                guard date >= cutoff, date <= now, delta[0] + delta[1] > 0 else { continue }
                let id = "\(session):\(timestamp):\(current[0]):\(current[1])"
                points[id] = AIUsagePoint(id: id, provider: provider, date: date, model: model, project: project, input: delta[0], output: delta[1], cached: delta[2], cacheCreation: delta[3], serviceTier: serviceTier, perRequest: info["last_token_usage"] != nil)
            } else {
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
                guard line.range(of: Data("task_started".utf8)) != nil || line.range(of: Data("task_complete".utf8)) != nil || line.range(of: Data("turn_aborted".utf8)) != nil || line.range(of: Data("turn_context".utf8)) != nil else { continue }
                guard let record = object(line), let payload = record["payload"] as? [String: Any] else { continue }
                if model == nil, record["type"] as? String == "turn_context" { model = payload["model"] as? String; tier = payload["service_tier"] as? String }
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
}

actor AIAnalyticsReader {
    private struct Cached { let modified: Date; let size: Int; let value: AIAnalytics }
    private var cache: [URL: Cached] = [:]
    private var files: [AIProvider: [URL]] = [:]
    private var discovered: [AIProvider: Date] = [:]
    private let home: URL
    private let codexHome: URL?
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, codexHome: URL? = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }) {
        self.home = home; self.codexHome = codexHome
    }
    func read(providers: [AIProvider], now: Date = .now) -> AIAnalytics {
        var result = AIAnalytics(), unique: [String: AIUsagePoint] = [:], work: [String: AIWork] = [:]
        for provider in providers {
            if discovered[provider].map({ now.timeIntervalSince($0) >= 60 }) ?? true {
                let root = provider == .codex ? (codexHome ?? home.appendingPathComponent(".codex")).appendingPathComponent("sessions") : home.appendingPathComponent(".claude/projects")
                var candidates: [(URL, Date)] = []
                if let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let url as URL in items {
                        guard candidates.count < 5000 else { break }
                        guard url.pathExtension == "jsonl", let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), info.isRegularFile == true else { continue }
                        candidates.append((url, info.contentModificationDate ?? .distantPast))
                    }
                }
                files[provider] = candidates.sorted { $0.1 > $1.1 }.prefix(80).map(\.0); discovered[provider] = now
            }
            for url in files[provider] ?? [] {
                var freshURL = url
                freshURL.removeAllCachedResourceValues()
                guard let info = try? freshURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { continue }
                let modified = info.contentModificationDate ?? .distantPast, size = info.fileSize ?? 0
                if cache[url]?.modified != modified || cache[url]?.size != size {
                    cache[url] = Cached(modified: modified, size: size, value: AIActivityParser.parse(url, provider: provider, now: now, knownWork: cache[url]?.value.work.first))
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
        result.points = unique.values.sorted { $0.date < $1.date }
        result.work = work.values.sorted { $0.startedAt > $1.startedAt }
        return result
    }
}

enum InstalledAIProviders {
    static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Set<AIProvider> {
        var result = Set<AIProvider>()
        if LocalCodexUsage.executable() != nil || FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex/sessions").path) { result.insert(.codex) }
        let claudePaths = [home.appendingPathComponent(".claude/projects").path, home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if claudePaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { result.insert(.claude) }
        return result
    }
}
