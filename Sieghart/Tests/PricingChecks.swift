import Foundation

@main struct PricingChecks {
    @MainActor static func main() async throws {
        let catalog = PriceCatalog.bundled(file: URL(fileURLWithPath: "Sieghart/Sieghart/ModelTokenPrices.json"))
        expect(catalog.entries.count >= 59, "Bundled official numeric price facts decode")
        expect(catalog.price(model: "gpt-6.1-sol", provider: .codex)?.rates.inputUSD == 2, "Exact model rates are used")
        expect(catalog.price(model: "gpt-6.1-sol-2026-10-05", provider: .codex)?.id == "gpt-6.1-sol", "Dated snapshots resolve documented base rates")
        expect(catalog.price(model: "codex-auto-review", provider: .codex) == nil, "Internal models never inherit an invented price")
        expect(catalog.price(model: "gpt-6.1-sol-unknown", provider: .codex) == nil, "Unverified aliases remain unpriced")
        expect(catalog.price(model: "gpt-6.1-sol", provider: .codex, tier: "priority")?.rates.inputUSD == 4, "Known fast tier uses published tier rate")
        let markdown = """
        ### Standard pricing data
        | Model | Short context input | Short context cached input | Short context cache writes | Short context output | Long context input | Long context cached input | Long context cache writes | Long context output |
        | gpt-fixture | $2.00 | $0.10 | $2.50 | $10.00 | $4.00 | $0.20 | $5.00 | $15.00 |
        ### Batch pricing data
        | Model | Short context input | Short context cached input | Short context cache writes | Short context output | Long context input | Long context cached input | Long context cache writes | Long context output |
        | gpt-fixture | $1.00 | $0.05 | - | $5.00 | - | - | - | - |
        """
        let parsed = PriceCatalog.parse(markdown, provider: .codex)
        expect(parsed.count == 2 && parsed.first?.tier == nil && parsed.last?.tier == "batch", "Parser separates standard and batch sections")
        expect(PriceCatalog.parse("Unexpected source format", provider: .codex).isEmpty, "Changed source format cannot fabricate rates")
        let claude = """
        | Model | Base input tokens | 5m cache writes | 1h cache writes | Cache hits and refreshes | Output tokens |
        | Claude Sonnet 4.6 | $3 / MTok | $3.75 / MTok | $6 / MTok | $0.30 / MTok | $15 / MTok |
        """
        let parsedClaude = PriceCatalog.parse(claude, provider: .claude)
        expect(parsedClaude.first?.id == "claude-sonnet-4-6" && parsedClaude.first?.creationLong == "6", "Claude cache-write durations are distinct")
        let quote = try JSONDecoder().decode(ExchangeQuote.self, from: Data("{\"date\":\"2026-10-06\",\"base\":\"USD\",\"quote\":\"BRL\",\"rate\":5.0712}".utf8))
        expect(quote.valid && quote.rate == Decimal(string: "5.0712"), "Actual public USD/BRL response preserves date and decimal rate")
        let suite = "Sieghart.Pricing.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let point = AIUsagePoint(id: "one", provider: .codex, date: .now, model: "gpt-6.1-sol", project: "Fixture", input: 1000000, output: 100000, cached: 900000, perRequest: false)
        let usage = AIUsageModel(defaults: defaults, initialAnalytics: AIAnalytics(points: [point]), initialPrices: catalog, read: { _ in nil })
        let codex = CodexUsageModel(defaults: defaults, load: { throw CodexUsageError.unavailable }); codex.enabled = true
        usage.claudeEnabled = true
        expect(usage.usedProviders(codex: codex) == [.codex], "An installed/enabled unused Claude cannot display its logo")
        let value = usage.estimate([point], provider: .codex)
        expect(value.usd == Decimal(string: "1.29") && value.pricedTokens == 1100000, "Automatic per-model prices discount cached input exactly")
        var long = point; long.perRequest = true
        expect(usage.estimate([long], provider: .codex).usd == Decimal(string: "2.08"), "Long request pricing is based on a request, not aggregated history")
        let unknown = AIUsagePoint(id: "missing", provider: .codex, date: .now, model: "codex-auto-review", project: "Fixture", input: 100, output: 10, cached: 0)
        let partial = usage.estimate([point, unknown], provider: .codex)
        expect(partial.isLowerBound && partial.unpricedTokens == 110 && partial.usd == value.usd, "Unknown price yields a labeled lower bound, retaining every token")
        usage.savePrices(TokenPrices(inputUSD: 3, outputUSD: 6), provider: .codex, exchangeRate: 5)
        expect(usage.usesCustomPrices(.codex) && usage.conversionRate == 5, "Custom prices remain an explicit optional override")
        usage.useAutomaticPrices(.codex)
        expect(!usage.usesCustomPrices(.codex) && usage.estimate([point], provider: .codex).usd == value.usd, "Automatic source can be restored without losing charges")
        let restored = AIUsageModel(defaults: defaults, initialPrices: catalog, read: { _ in nil })
        expect(!restored.usesCustomPrices(.codex), "Automatic preference persists")
        usage.disable(.codex, codex: codex)
        expect(usage.usedProviders(codex: codex).isEmpty, "Disconnected providers disappear from the summary")
        print("PASS: automatic official model/tier pricing, cache arithmetic, long request handling, unpriced lower bounds, dated FX, custom override persistence and usage-based provider emblems")
    }
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { guard value() else { fatalError("FAIL: \(message)") } }
}
