import Combine
import Foundation

@MainActor final class AIUsageViewModel: ObservableObject {
    @Published var claudeEnabled: Bool {
        didSet { readRevision += 1; defaults.set(claudeEnabled, forKey: "integrations.claudeUsage"); if !claudeEnabled { tokens[.claude] = nil; automaticClaudeReport = nil; claudeHistoryStatus = "Claude monitoring is off" } }
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
    @Published private(set) var priceCatalog: PriceCatalog
    @Published private(set) var exchangeQuote: ExchangeQuote?
    @Published private(set) var pricingRefreshing = false
    private var priceAttempts: [AIProvider: Date] = [:]
    private var exchangeAttempt = Date.distantPast
    @Published private(set) var claudeReport: ClaudeLimitsReport?
    @Published private(set) var automaticClaudeReport: ClaudeLimitsReport?
    @Published private(set) var claudeHistoryStatus = "No recent Claude desktop reading"
    @Published private(set) var historyIsReading = false
    @Published private(set) var historyStatus = "Recent sessions · Partial local history"
    private let readClaude: @Sendable () throws -> ClaudeLimitsReport?
    var effectiveClaudeReport: ClaudeLimitsReport? {
        guard claudeEnabled else { return nil }
        if let automatic = automaticClaudeReport, Date().timeIntervalSince(automatic.capturedAt) < 1800,
           claudeReport.map({ $0.capturedAt <= automatic.capturedAt }) ?? true { return automatic }
        return claudeReport
    }
    var claudeSource: String { effectiveClaudeReport?.capturedAt == automaticClaudeReport?.capturedAt && effectiveClaudeReport != nil ? "Claude desktop · Local history · Renewal time unavailable" : "Imported dated report" }
    private var historyTask: Task<Void, Never>?
    private var readRevision = 0
    private var monitorTask: Task<Void, Never>?
    private let analyticsReader = AIAnalyticsReader()
    private let defaults: UserDefaults
    private let read: @Sendable (AIProvider) -> LocalTokenUsage?
    init(defaults: UserDefaults = .standard, readClaude: @escaping @Sendable () throws -> ClaudeLimitsReport? = { try ClaudePlanHistory.read() }, initialAnalytics: AIAnalytics = AIAnalytics(), initialAccountActivity: CodexAccountActivity? = nil, initialPrices: PriceCatalog? = nil, read: @escaping @Sendable (AIProvider) -> LocalTokenUsage? = { provider in
        let configured = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        return LocalTokenReader.read(provider, codexHome: configured)
    }) {
        self.defaults = defaults; self.read = read; self.readClaude = readClaude
        let cache = defaults.data(forKey: "integrations.modelPrices").flatMap { try? JSONDecoder().decode(PriceCatalog.self, from: $0) }
        priceCatalog = initialPrices ?? cache ?? PriceCatalog.bundled()
        exchangeQuote = defaults.data(forKey: "integrations.exchangeQuote").flatMap { try? JSONDecoder().decode(ExchangeQuote.self, from: $0) }.flatMap { $0.valid ? $0 : nil }
        analytics = initialAnalytics; accountActivity = initialAccountActivity
        automaticDetection = defaults.bool(forKey: "integrations.autoDetect")
        claudeEnabled = defaults.bool(forKey: "integrations.claudeUsage")
        ledger = defaults.data(forKey: "integrations.usageLedger").flatMap { try? JSONDecoder().decode(AIUsageLedger.self, from: $0) } ?? AIUsageLedger()
        claudeReport = defaults.data(forKey: "integrations.claudeReport").flatMap { try? JSONDecoder().decode(ClaudeLimitsReport.self, from: $0) }
    }

    var hasPendingRead: Bool { isRefreshing || pricingRefreshing || historyIsReading }
    func hasCurrentWork(at now: Date) -> Bool { analytics.work.contains { $0.isCurrent(at: now) } }

    func refresh(codexEnabled: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true; defer { isRefreshing = false }
        let revision = readRevision
        let reader = read, claudeReader = readClaude, readsClaude = claudeEnabled, providers = AIProvider.allCases.filter { $0 == .codex ? codexEnabled : claudeEnabled }
        let result = await Task.detached(priority: .utility) {
            var result: [AIProvider: LocalTokenUsage] = [:]
            for provider in providers { result[provider] = reader(provider) }
            let quota: ClaudeLimitsReport?, failure: String?
            do { quota = readsClaude ? try claudeReader() : nil; failure = nil }
            catch { quota = nil; failure = error.localizedDescription }
            return (result, quota, failure)
        }.value
        guard !Task.isCancelled, revision == readRevision else { return }
        automaticClaudeReport = claudeEnabled ? result.1 : nil
        claudeHistoryStatus = result.2 ?? (result.1 == nil ? "No recent Claude desktop reading. Open Claude and enable its usage menu to refresh the local history." : "Claude desktop local history")
        tokens = result.0.filter { $0.key != .claude || claudeEnabled }; updatedAt = .now
    }

    func startMonitoring(codex: CodexUsageViewModel) {
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
                    await self.refreshPricing(providers: allowed)
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
    func stopMonitoring() { monitorTask?.cancel(); monitorTask = nil; historyTask?.cancel(); historyTask = nil }
    func expandHistory(codexEnabled: Bool) {
        guard !historyIsReading else { return }
        historyIsReading = true
        let revision = readRevision, providers = AIProvider.allCases.filter { $0 == .codex ? codexEnabled : claudeEnabled }
        historyTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.analyticsReader.readFullHistory(providers: providers)
            defer { self.historyIsReading = false; self.historyTask = nil }
            guard !Task.isCancelled, revision == self.readRevision else { return }
            self.analytics = result
            self.activityUpdatedAt = .now
            self.historyStatus = "Up to 1 year · \(result.scannedFiles) local files · \(result.points.count.formatted()) records · Partial local history"
        }
    }
    func cancelHistory() { historyTask?.cancel() }
    func disable(_ provider: AIProvider, codex: CodexUsageViewModel) {
        automaticDetection = false; readRevision += 1
        if provider == .codex { codex.enabled = false; tokens[.codex] = nil; accountActivity = nil; accountUpdatedAt = nil; accountRefreshFailed = false }
        else { claudeEnabled = false }
        analytics.points.removeAll { $0.provider == provider }; analytics.work.removeAll { $0.provider == provider }
    }

    func savePrices(_ prices: TokenPrices, provider: AIProvider, exchangeRate: Decimal?) {
        ledger.prices[provider] = prices
        ledger.customPriceProviders = Array(Set((ledger.customPriceProviders ?? []) + [provider]))
        ledger.customExchangeRate = exchangeRate != nil
        if ledger.usdToBRL != exchangeRate { ledger.usdToBRL = exchangeRate; ledger.exchangeRateDate = exchangeRate == nil ? nil : .now }
        persist()
    }
    // Presence is based on readings or recorded work, not installation alone.
    func usedProviders(codex: CodexUsageViewModel) -> [AIProvider] {
        AIProvider.allCases.filter { provider in
            let enabled = provider == .codex ? codex.enabled : claudeEnabled
            guard enabled else { return false }
            return (tokens[provider]?.total ?? 0) > 0 || analytics.points.contains { $0.provider == provider && $0.total > 0 } || analytics.work.contains { $0.provider == provider }
                || (provider == .codex ? codex.bucket != nil : effectiveClaudeReport != nil)
        }
    }
    func usesCustomPrices(_ provider: AIProvider) -> Bool { ledger.customPriceProviders?.contains(provider) == true }
    func useAutomaticPrices(_ provider: AIProvider) {
        ledger.customPriceProviders = (ledger.customPriceProviders ?? []).filter { $0 != provider }
        ledger.customExchangeRate = false; persist()
    }
    var conversionRate: Decimal? { ledger.customExchangeRate == true ? ledger.usdToBRL : exchangeQuote?.rate }
    var conversionDate: Date? { ledger.customExchangeRate == true ? ledger.exchangeRateDate : exchangeQuote.flatMap { AIActivityParser.parseDate($0.date + "T00:00:00Z") } }
    func estimate(_ points: [AIUsagePoint], provider: AIProvider) -> TokenEstimate {
        var result = TokenEstimate()
        for point in points where point.provider == provider {
            let usage = LocalTokenUsage(input: point.input, cachedInput: point.cached, cacheCreation: point.cacheCreation, output: point.output, sessions: 0)
            let custom = usesCustomPrices(provider) ? ledger.prices[provider] : nil
            let price = priceCatalog.price(model: point.model, provider: provider, tier: point.serviceTier)
            let rates = custom ?? price?.rates(long: point.perRequest && point.input > 272000)
            if var usd = rates?.estimate(usage) {
                if custom == nil, let price, point.cacheCreationLong > 0,
                   let hourly = price.creationLong.flatMap({ Decimal(string: $0) }), let short = rates?.cacheCreationUSD ?? rates?.inputUSD {
                    usd += Decimal(min(point.cacheCreationLong, point.cacheCreation)) * (hourly - short) / 1_000_000
                }
                result.usd += usd; result.pricedTokens += point.total
            } else { result.unpricedTokens += point.total }
        }
        return result
    }
    func refreshPricing(providers: [AIProvider], force: Bool = false) async {
        guard !providers.isEmpty, !pricingRefreshing else { return }
        let now = Date()
        let due = providers.filter { force || (now.timeIntervalSince(priceCatalog.fetched[$0] ?? .distantPast) >= 86400 && now.timeIntervalSince(priceAttempts[$0] ?? .distantPast) >= 3600) }
        let exchangeDue = ledger.customExchangeRate != true && (force || now.timeIntervalSince(exchangeAttempt) >= 86400)
        guard !due.isEmpty || exchangeDue else { return }
        pricingRefreshing = true; defer { pricingRefreshing = false }
        for provider in due {
            priceAttempts[provider] = now
            if let entries = try? await PricingSource.fetch(provider) {
                priceCatalog.entries.removeAll { $0.provider == provider }
                priceCatalog.entries += entries; priceCatalog.fetched[provider] = now
                if let data = try? JSONEncoder().encode(priceCatalog) { defaults.set(data, forKey: "integrations.modelPrices") }
            }
        }
        if exchangeDue {
            exchangeAttempt = now
            if let quote = try? await PricingSource.exchange() {
                exchangeQuote = quote
                if let data = try? JSONEncoder().encode(quote) { defaults.set(data, forKey: "integrations.exchangeQuote") }
            }
        }
    }
    func pricingDescription(_ provider: AIProvider) -> String {
        if usesCustomPrices(provider) { return "Custom average prices · API equivalent" }
        let date = priceCatalog.entries.filter { $0.provider == provider }.map(\.checked).max()
        return "Automatic model prices" + (date.map { " · \($0)" } ?? " · unavailable")
    }

    @discardableResult func importCharges(_ charges: [RecordedCharge]) throws -> Int {
        let additions = try ChargeFile.additions(charges, existing: ledger.charges)
        ledger.charges.append(contentsOf: additions); persist()
        return additions.count
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
