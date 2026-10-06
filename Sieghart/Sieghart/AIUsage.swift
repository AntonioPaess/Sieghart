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

struct TokenPrices: Codable, Equatable {
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
}

struct AIUsageLedger: Codable {
    var prices: [AIProvider: TokenPrices] = [:]
    var charges: [RecordedCharge] = []
    var usdToBRL: Decimal?
    var exchangeRateDate: Date?

    func recorded(_ provider: AIProvider, currency: SpendCurrency, month: Date, calendar: Calendar = .current) -> Decimal? {
        let entries = charges.filter { $0.provider == provider && $0.currency == currency && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        guard !entries.isEmpty else { return nil }
        return entries.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

// Claude's individual subscription quotas have no public local equivalent to
// Codex's account/rateLimits/read. An explicit dated report can supply them.
struct ClaudeLimitsReport: Codable {
    let capturedAt: Date
    let primary: ReportWindow?
    let secondary: ReportWindow?
    struct ReportWindow: Codable {
        let usedPercent: Double
        let windowDurationMins: Int
        let resetsAt: TimeInterval
        var window: CodexQuotaWindow { CodexQuotaWindow(usedPercent: usedPercent, windowDurationMins: windowDurationMins, resetsAt: resetsAt) }
    }
    func isValid(now: Date = .now) -> Bool {
        let windows = [primary, secondary].compactMap { $0 }
        return capturedAt <= now.addingTimeInterval(300) && !windows.isEmpty && windows.allSatisfy {
            $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) && $0.windowDurationMins > 0 && $0.resetsAt.isFinite && $0.resetsAt > 0
        }
    }
}

@MainActor final class AIUsageModel: ObservableObject {
    @Published var claudeEnabled: Bool {
        didSet { readRevision += 1; defaults.set(claudeEnabled, forKey: "integrations.claudeUsage"); if !claudeEnabled { tokens[.claude] = nil } }
    }
    @Published var automaticDetection: Bool { didSet { defaults.set(automaticDetection, forKey: "integrations.autoDetect") } }
    @Published private(set) var analytics = AIAnalytics()
    @Published private(set) var accountActivity: CodexAccountActivity?
    @Published private(set) var activityUpdatedAt: Date?
    @Published private(set) var accountUpdatedAt: Date?
    @Published private(set) var accountRefreshFailed = false
    @Published private(set) var tokens: [AIProvider: LocalTokenUsage] = [:]
    @Published private(set) var updatedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var ledger: AIUsageLedger
    @Published private(set) var claudeReport: ClaudeLimitsReport?
    private var readRevision = 0
    private var monitorTask: Task<Void, Never>?
    private let analyticsReader = AIAnalyticsReader()
    private let defaults: UserDefaults
    private let read: @Sendable (AIProvider) -> LocalTokenUsage?
    init(defaults: UserDefaults = .standard, initialAnalytics: AIAnalytics = AIAnalytics(), initialAccountActivity: CodexAccountActivity? = nil, read: @escaping @Sendable (AIProvider) -> LocalTokenUsage? = { provider in
        let configured = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        return LocalTokenReader.read(provider, codexHome: configured)
    }) {
        self.defaults = defaults; self.read = read
        analytics = initialAnalytics; accountActivity = initialAccountActivity
        automaticDetection = defaults.bool(forKey: "integrations.autoDetect")
        claudeEnabled = defaults.bool(forKey: "integrations.claudeUsage")
        ledger = defaults.data(forKey: "integrations.usageLedger").flatMap { try? JSONDecoder().decode(AIUsageLedger.self, from: $0) } ?? AIUsageLedger()
        claudeReport = defaults.data(forKey: "integrations.claudeReport").flatMap { try? JSONDecoder().decode(ClaudeLimitsReport.self, from: $0) }
    }

    func refresh(codexEnabled: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true; defer { isRefreshing = false }
        let revision = readRevision
        let reader = read, providers = AIProvider.allCases.filter { $0 == .codex ? codexEnabled : claudeEnabled }
        let result = await Task.detached(priority: .utility) {
            var result: [AIProvider: LocalTokenUsage] = [:]
            for provider in providers { result[provider] = reader(provider) }
            return result
        }.value
        guard !Task.isCancelled, revision == readRevision else { return }
        tokens = result.filter { $0.key != .claude || claudeEnabled }; updatedAt = .now
    }

    func startMonitoring(codex: CodexUsageModel) {
        guard monitorTask == nil else { return }
        monitorTask = Task { @MainActor [weak self, weak codex] in
            var lastCounters = Date.distantPast, lastAccount = Date.distantPast, lastDetection = Date.distantPast
            while !Task.isCancelled {
                guard let self, let codex else { return }
                if self.automaticDetection && Date().timeIntervalSince(lastDetection) >= 60 {
                    let detected = InstalledAIProviders.detect()
                    if detected.contains(.codex) && !codex.enabled { codex.enabled = true }
                    if detected.contains(.claude) && !self.claudeEnabled { self.claudeEnabled = true }
                    lastDetection = .now
                }
                let providers = AIProvider.allCases.filter { $0 == .codex ? codex.enabled : self.claudeEnabled }
                let result = await self.analyticsReader.read(providers: providers)
                let allowed = AIProvider.allCases.filter { $0 == .codex ? codex.enabled : self.claudeEnabled }
                self.analytics = AIAnalytics(points: result.points.filter { allowed.contains($0.provider) }, work: result.work.filter { allowed.contains($0.provider) }, scannedFiles: result.scannedFiles)
                self.activityUpdatedAt = .now
                if !codex.enabled { self.tokens[.codex] = nil; self.accountActivity = nil; self.accountUpdatedAt = nil; self.accountRefreshFailed = false }
                if Date().timeIntervalSince(lastCounters) >= 60 {
                    await self.refresh(codexEnabled: codex.enabled)
                    await codex.refresh()
                    lastCounters = .now
                }
                if codex.enabled && Date().timeIntervalSince(lastAccount) >= 300 {
                    let activity = await Task.detached(priority: .utility) { try? LocalCodexUsage.fetchActivity() }.value
                    if codex.enabled {
                        if let activity { self.accountActivity = activity; self.accountUpdatedAt = .now; self.accountRefreshFailed = false }
                        else { self.accountRefreshFailed = true }
                    }
                    lastAccount = .now
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    func stopMonitoring() { monitorTask?.cancel(); monitorTask = nil }
    func disable(_ provider: AIProvider, codex: CodexUsageModel) {
        automaticDetection = false; readRevision += 1
        if provider == .codex { codex.enabled = false; tokens[.codex] = nil; accountActivity = nil; accountUpdatedAt = nil; accountRefreshFailed = false }
        else { claudeEnabled = false }
        analytics.points.removeAll { $0.provider == provider }; analytics.work.removeAll { $0.provider == provider }
    }

    func savePrices(_ prices: TokenPrices, provider: AIProvider, exchangeRate: Decimal?) {
        ledger.prices[provider] = prices
        if ledger.usdToBRL != exchangeRate { ledger.usdToBRL = exchangeRate; ledger.exchangeRateDate = exchangeRate == nil ? nil : .now }
        persist()
    }
    func record(_ charge: RecordedCharge) {
        guard charge.amount > 0, charge.amount < 1_000_000_000 else { return }
        ledger.charges.append(charge); persist()
    }
    func removeCharge(id: UUID) { ledger.charges.removeAll { $0.id == id }; persist() }
    func importClaudeReport(_ data: Data) throws {
        guard data.count < 65_536 else { throw CodexUsageError.invalidResponse }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(ClaudeLimitsReport.self, from: data)
        guard report.isValid() else { throw CodexUsageError.invalidResponse }
        claudeReport = report; claudeEnabled = true
        defaults.set(try JSONEncoder().encode(report), forKey: "integrations.claudeReport")
    }
    func clearClaudeReport() { claudeReport = nil; defaults.removeObject(forKey: "integrations.claudeReport") }
    private func persist() { if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: "integrations.usageLedger") } }
}
