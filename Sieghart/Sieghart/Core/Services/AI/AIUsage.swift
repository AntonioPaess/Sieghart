import Combine
import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude, antigravity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .antigravity: "Antigravity"
        }
    }
    var assetName: String {
        switch self {
        case .codex: "CodexMark"
        case .claude: "ClaudeMark"
        case .antigravity: "AntigravityMark"
        }
    }
}

struct LocalTokenUsage: Equatable, Sendable {
    // Input includes cache reads/writes; output includes reasoning tokens.
    // Cache and reasoning must never be added to those totals again.
    let input: Int64
    let cachedInput: Int64
    let cacheCreation: Int64
    let output: Int64
    let sessions: Int
    var total: Int64 { input + output }
}

enum LocalTokenReader {
    static func conversationID(for url: URL) -> String {
        if let uuid = url.pathComponents.reversed().first(where: { UUID(uuidString: $0) != nil }) {
            return uuid
        }
        let stem = url.deletingPathExtension().lastPathComponent
        if let uuid = UUID(uuidString: String(stem.suffix(36)))?.uuidString {
            return uuid
        }
        return url.path
    }

    static func discoverFiles(for provider: AIProvider, home: URL, codexHome: URL? = nil, antigravityHome: URL? = nil, includeArchived: Bool = false) -> [(URL, Date, Int)] {
        let manager = FileManager.default
        var candidates: [(URL, Date, Int)] = []
        if provider == .antigravity {
            let roots = antigravityHome.map { [$0.appendingPathComponent("brain")] }
                ?? [home.appendingPathComponent(".gemini/antigravity/brain"), home.appendingPathComponent(".gemini/antigravity-cli/brain")]
            for root in roots {
                guard let items = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
                for item in items.prefix(5000) {
                    let nested = item.appendingPathComponent(".system_generated/logs/transcript.jsonl")
                    let direct = item.appendingPathComponent("transcript.jsonl")
                    let targets = item.pathExtension == "jsonl" && item.lastPathComponent != "transcript_full.jsonl" ? [item] : [nested, direct]
                    for target in targets {
                        guard let info = try? target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]),
                              info.isRegularFile == true, info.isSymbolicLink != true else { continue }
                        candidates.append((target, info.contentModificationDate ?? .distantPast, info.fileSize ?? 0))
                        break
                    }
                }
            }
            return candidates
        }
        let codexRoot = codexHome ?? home.appendingPathComponent(".codex")
        let roots: [URL] = provider == .codex
            ? (includeArchived ? [codexRoot.appendingPathComponent("sessions"), codexRoot.appendingPathComponent("archived_sessions")] : [codexRoot.appendingPathComponent("sessions")])
            : [home.appendingPathComponent(".claude/projects")]
        for root in roots {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                if candidates.count >= 5000 { break }
                guard url.pathExtension == "jsonl",
                      let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                      info.isRegularFile == true, info.isSymbolicLink != true else { continue }
                candidates.append((url, info.contentModificationDate ?? .distantPast, info.fileSize ?? 0))
            }
        }
        return candidates
    }

    static func read(_ provider: AIProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser, codexHome: URL? = nil, antigravityHome: URL? = nil) -> LocalTokenUsage? {
        let files = discoverFiles(for: provider, home: home, codexHome: codexHome, antigravityHome: antigravityHome)
        let recent = files.sorted { $0.1 > $1.1 }.prefix(80).map(\.0)
        var counters: [String: [Int64]] = [:]
        var sessions = Set<String>()
        for url in recent {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let length = try? handle.seekToEnd() else { continue }
            let offset = length > 2_097_152 ? length - 2_097_152 : 0
            try? handle.seek(toOffset: offset)
            guard let tail = try? handle.readToEnd() else { continue }
            let lines = tail.split(separator: 10, omittingEmptySubsequences: true)
            let sessionID = conversationID(for: url)
            for line in offset > 0 ? lines.dropFirst() : lines[...] {
                guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                let fields: [String: Any]
                let key: String
                let counts: [Int64]
                switch provider {
                case .codex:
                    guard record["type"] as? String == "event_msg",
                          let payload = record["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                          let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Any] else { continue }
                    fields = usage
                    let name = url.deletingPathExtension().lastPathComponent
                    key = UUID(uuidString: String(name.suffix(36)))?.uuidString ?? url.path
                    let input = count(fields["input_tokens"]), cached = count(fields["cached_input_tokens"])
                    counts = [input, min(input, cached), min(input - min(input, cached), count(fields["cache_write_input_tokens"])), count(fields["output_tokens"])]
                case .claude:
                    guard record["type"] as? String == "assistant", let message = record["message"] as? [String: Any],
                          let id = message["id"] as? String, let usage = message["usage"] as? [String: Any] else { continue }
                    fields = usage; key = id
                    let fresh = count(fields["input_tokens"]), cached = count(fields["cache_read_input_tokens"]), created = count(fields["cache_creation_input_tokens"])
                    counts = [fresh + cached + created, cached, created, count(fields["output_tokens"])]
                case .antigravity:
                    guard record["type"] as? String == "PLANNER_RESPONSE" || record["source"] as? String == "MODEL" else { continue }
                    fields = record
                    let fresh = count(fields["input_tokens"]), cached = count(fields["cache_read_tokens"]), created = count(fields["cache_creation_tokens"]), out = count(fields["output_tokens"])
                    guard fresh + cached + created + out > 0 else { continue }
                    let step = fields["step_index"].map { "\($0)" } ?? (fields["created_at"] as? String ?? "")
                    key = "antigravity:\(sessionID):\(step)"
                    counts = [fresh + cached + created, cached, created, out]
                }
                guard fields["input_tokens"] != nil || fields["output_tokens"] != nil || fields["cache_read_tokens"] != nil else { continue }
                if let previous = counters[key] { counters[key] = zip(previous, counts).map { max($0, $1) } }
                else { counters[key] = counts }
                switch provider {
                case .codex: sessions.insert(key)
                case .claude: sessions.insert(url.path)
                case .antigravity: sessions.insert(sessionID)
                }
            }
        }
        guard !counters.isEmpty else { return nil }
        let sums = counters.values.reduce([Int64](repeating: 0, count: 4)) { total, entry in zip(total, entry).map(+) }
        return LocalTokenUsage(input: sums[0], cachedInput: sums[1], cacheCreation: sums[2], output: sums[3], sessions: sessions.count)
    }

    private static func count(_ value: Any?) -> Int64 {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 1_000_000_000_000 else { return 0 }
        return number.int64Value
    }
}

struct TokenPrices: Codable, Equatable, Sendable {
    var inputUSD: Decimal?
    var outputUSD: Decimal?
    var cachedInputUSD: Decimal?
    var cacheCreationUSD: Decimal?

    func estimate(_ usage: LocalTokenUsage?) -> Decimal? {
        guard let usage, let inputUSD, let outputUSD, inputUSD >= 0, outputUSD >= 0 else { return nil }
        let fresh = max(0, usage.input - usage.cachedInput - usage.cacheCreation)
        return (Decimal(fresh) * inputUSD + Decimal(usage.cachedInput) * (cachedInputUSD ?? inputUSD)
            + Decimal(usage.cacheCreation) * (cacheCreationUSD ?? inputUSD) + Decimal(usage.output) * outputUSD) / 1_000_000
    }
}

enum SpendCurrency: String, Codable, CaseIterable { case USD, BRL }
enum SpendKind: String, Codable, CaseIterable { case subscription = "Subscription", api = "API" }
struct RecordedCharge: Codable, Identifiable {
    var id = UUID()
    let provider: AIProvider
    let date: Date
    let amount: Decimal
    let currency: SpendCurrency
    let kind: SpendKind
    var externalID: String? = nil
    var source: String? = nil
}

struct AIUsageLedger: Codable {
    var prices: [AIProvider: TokenPrices] = [:]
    var charges: [RecordedCharge] = []
    var usdToBRL: Decimal?
    var exchangeRateDate: Date?
    var customPriceProviders: [AIProvider]?
    var customExchangeRate: Bool?

    func recorded(_ provider: AIProvider, currency: SpendCurrency, month: Date, calendar: Calendar = .current) -> Decimal? {
        let entries = charges.filter { $0.provider == provider && $0.currency == currency && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        guard !entries.isEmpty else { return nil }
        return entries.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

// Claude desktop history supplies measured percentages; renewal dates are
// absent in that source. Dated reports can supply explicit renewal dates.
struct ClaudeLimitsReport: Codable, Sendable {
    let capturedAt: Date
    let primary: ReportWindow?
    let secondary: ReportWindow?
    var scoped: [ReportWindow]? = nil
    var planType: String? = nil
    struct ReportWindow: Codable, Sendable {
        let usedPercent: Double
        let windowDurationMins: Int
        let resetsAt: TimeInterval?
        var scope: String? = nil
        var window: CodexQuotaWindow { CodexQuotaWindow(usedPercent: usedPercent, windowDurationMins: windowDurationMins, resetsAt: resetsAt) }
    }
    func isValid(now: Date = .now) -> Bool {
        let windows = [primary, secondary].compactMap { $0 } + (scoped ?? [])
        return capturedAt <= now.addingTimeInterval(300) && !windows.isEmpty && windows.allSatisfy {
            $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) && $0.windowDurationMins > 0 && ($0.resetsAt.map { $0.isFinite && $0 > 0 } ?? true)
        }
    }
}

enum AntigravityPlanHistory {
    static func read(now: Date = .now) -> ClaudeLimitsReport? {
        for (port, token) in discoverEndpoints() {
            guard let url = URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 2.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.setValue(token, forHTTPHeaderField: "x-codeium-csrf-token")
            request.httpBody = Data("{}".utf8)
            let box = LockedDataBox()
            let semaphore = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { data, response, _ in
                if let http = response as? HTTPURLResponse, http.statusCode == 200, let data {
                    box.store(data)
                }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 2.2)
            if let data = box.load(), let report = parseUserStatus(data, now: now) {
                return report
            }
        }
        return nil
    }

    static func parseUserStatus(_ data: Data, now: Date = .now) -> ClaudeLimitsReport? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let status = (root["userStatus"] as? [String: Any]) ?? root
        let planInfo = (status["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any]
        let userTier = status["userTier"] as? [String: Any]
        let planName = (planInfo?["planName"] as? String) ?? (userTier?["name"] as? String)
        guard let cascade = status["cascadeModelConfigData"] as? [String: Any],
              let configs = cascade["clientModelConfigs"] as? [[String: Any]], !configs.isEmpty else { return nil }
        let activeEnum = ((cascade["defaultOverrideModelConfig"] as? [String: Any])?["modelOrAlias"] as? [String: Any])?["model"] as? String

        var shortWindows: [(enumID: String, label: String, modelId: String, window: ClaudeLimitsReport.ReportWindow)] = []
        var weeklyWindows: [(enumID: String, label: String, modelId: String, window: ClaudeLimitsReport.ReportWindow)] = []

        for config in configs {
            guard let quota = config["quotaInfo"] as? [String: Any],
                  let remaining = (quota["remainingFraction"] as? NSNumber)?.doubleValue,
                  remaining.isFinite else { continue }
            let used = max(0, min(100, ((1.0 - remaining) * 100.0).rounded()))
            let resetDate = (quota["resetTime"] as? String).flatMap { AIActivityParser.parseDate($0) }
            let resetsAt = resetDate?.timeIntervalSince1970
            let isWeekly = resetDate.map { $0.timeIntervalSince(now) > 36 * 3600 } ?? false
            let duration = isWeekly ? 10080 : 300
            let label = (config["label"] as? String) ?? "Model allowance"
            let modelId = (config["modelId"] as? String) ?? ""
            let enumID = ((config["modelOrAlias"] as? [String: Any])?["model"] as? String) ?? ""
            let family: String
            if modelId.hasPrefix("gemini-4-argon") { family = "Gemini 4 Argon" }
            else if modelId.hasPrefix("gemini-3.8-flash") || modelId.hasPrefix("gemini-3-8-flash") { family = "Gemini 3.8 Flash" }
            else if modelId.hasPrefix("claude-") { family = "Claude 5.5" }
            else { family = label }
            let win = ClaudeLimitsReport.ReportWindow(usedPercent: used, windowDurationMins: duration, resetsAt: resetsAt, scope: family)
            if isWeekly {
                weeklyWindows.append((enumID, family, modelId, win))
            } else {
                shortWindows.append((enumID, family, modelId, win))
            }
        }
        let primary = shortWindows.first(where: { $0.enumID == activeEnum })?.window
            ?? shortWindows.max(by: { $0.window.usedPercent < $1.window.usedPercent })?.window
            ?? weeklyWindows.first?.window
        let secondary = weeklyWindows.first(where: { $0.enumID == activeEnum })?.window
            ?? weeklyWindows.first?.window
        var seenScopes = Set<String>()
        var scoped: [ClaudeLimitsReport.ReportWindow] = []
        for item in (weeklyWindows + shortWindows) {
            if seenScopes.insert(item.label).inserted {
                scoped.append(item.window)
            }
        }
        guard primary != nil || secondary != nil else { return nil }
        return ClaudeLimitsReport(capturedAt: now, primary: primary, secondary: secondary, scoped: scoped.isEmpty ? nil : scoped, planType: planName)
    }

    private static func discoverEndpoints() -> [(Int, String)] {
        var results: [(Int, String)] = []
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        for line in output.split(separator: "\n") {
            let text = String(line)
            guard text.contains("language_server"), text.contains("--csrf_token") else { continue }
            let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let csrfIdx = parts.firstIndex(of: "--csrf_token"), csrfIdx + 1 < parts.count else { continue }
            let token = parts[csrfIdx + 1]
            if let bridgeArg = parts.first(where: { $0.hasPrefix("--host_bridge_url=") }),
               let portStr = bridgeArg.split(separator: ":").last,
               let bridgePort = Int(portStr) {
                results.append((bridgePort + 2, token))
                results.append((bridgePort + 1, token))
            }
        }
        return results
    }
}

private final class LockedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    func store(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func load() -> Data? { lock.lock(); defer { lock.unlock() }; return data }
}
