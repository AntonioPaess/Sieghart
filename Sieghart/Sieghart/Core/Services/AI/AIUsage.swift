import Combine
import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude
    var id: String { rawValue }
    var title: String { self == .codex ? "Codex" : "Claude Code" }
    var assetName: String { self == .codex ? "CodexMark" : "ClaudeMark" }
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
    static func read(_ provider: AIProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser, codexHome: URL? = nil) -> LocalTokenUsage? {
        let root = provider == .codex
            ? (codexHome ?? home.appendingPathComponent(".codex")).appendingPathComponent("sessions")
            : home.appendingPathComponent(".claude/projects")
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        var files: [(URL, Date)] = []
        // Bound both discovery and reads. Never inspect auth, settings, or tools.
        for case let url as URL in enumerator {
            if files.count >= 5000 { break }
            guard url.pathExtension == "jsonl",
                  let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), info.isRegularFile == true else { continue }
            files.append((url, info.contentModificationDate ?? .distantPast))
        }
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
            for line in offset > 0 ? lines.dropFirst() : lines[...] {
                guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                let fields: [String: Any]
                let key: String
                let counts: [Int64]
                if provider == .codex {
                    guard record["type"] as? String == "event_msg",
                          let payload = record["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                          let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Any] else { continue }
                    fields = usage
                    let name = url.deletingPathExtension().lastPathComponent
                    // Rollout filenames end in the session UUID. Duplicate
                    // copies of a rollout must not double its cumulative total.
                    key = UUID(uuidString: String(name.suffix(36)))?.uuidString ?? url.path
                    let input = count(fields["input_tokens"]), cached = count(fields["cached_input_tokens"])
                    counts = [input, min(input, cached), min(input - min(input, cached), count(fields["cache_write_input_tokens"])), count(fields["output_tokens"])]
                } else {
                    guard record["type"] as? String == "assistant", let message = record["message"] as? [String: Any],
                          let id = message["id"] as? String, let usage = message["usage"] as? [String: Any] else { continue }
                    fields = usage; key = id
                    let fresh = count(fields["input_tokens"]), cached = count(fields["cache_read_input_tokens"]), created = count(fields["cache_creation_input_tokens"])
                    counts = [fresh + cached + created, cached, created, count(fields["output_tokens"])]
                }
                guard fields["input_tokens"] != nil || fields["output_tokens"] != nil else { continue }
                // Repeated cumulative Codex events and streamed Claude messages
                // replace their previous counter instead of adding it again.
                if let previous = counters[key] { counters[key] = zip(previous, counts).map { max($0, $1) } }
                else { counters[key] = counts }
                sessions.insert(provider == .codex ? key : url.path)
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
