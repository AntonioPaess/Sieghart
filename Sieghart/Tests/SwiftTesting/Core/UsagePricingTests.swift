import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.pricing, .isolated)) @MainActor
  struct UsagePricingTests {
    @Test("G09.04 only used providers appear, cache discounts and unpriced tokens survive")
    func modelEstimates() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let catalog = PriceCatalog.bundled(file: TestResources.priceCatalogURL)
      let point = AIUsagePoint(
        id: "one", provider: .codex, date: Date(timeIntervalSince1970: 1_800_000_000),
        model: "gpt-6.1-sol", project: "Fixture", input: 1_000_000, output: 100000, cached: 900000,
        perRequest: false)
      let usage = AIUsageViewModel(
        defaults: defaults, readClaude: { nil }, initialAnalytics: AIAnalytics(points: [point]),
        initialPrices: catalog, read: { _ in nil })
      let codex = CodexUsageViewModel(
        defaults: defaults, load: { throw CodexUsageError.unavailable })
      codex.enabled = true
      usage.claudeEnabled = true
      #expect(
        usage.usedProviders(codex: codex) == [.codex],
        "An installed/enabled unused Claude cannot display its logo")
      let value = usage.estimate([point], provider: .codex)
      #expect(
        value.usd == Decimal(string: "1.29") && value.pricedTokens == 1_100_000,
        "Automatic per-model prices discount cached input exactly")
      var long = point
      long.perRequest = true
      #expect(
        usage.estimate([long], provider: .codex).usd == Decimal(string: "2.08"),
        "Long request pricing is based on a request, not aggregated history")
      let unknown = AIUsagePoint(
        id: "missing", provider: .codex, date: Date(timeIntervalSince1970: 1_800_000_000),
        model: "codex-auto-review", project: "Fixture", input: 100, output: 10, cached: 0)
      let partial = usage.estimate([point, unknown], provider: .codex)
      #expect(
        partial.isLowerBound && partial.unpricedTokens == 110 && partial.usd == value.usd,
        "Unknown price yields a labeled lower bound, retaining every token")
    }

    @Test("G09.05 custom override, automatic restoration, persistence and disconnect")
    func priceOverride() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let catalog = PriceCatalog.bundled(file: TestResources.priceCatalogURL)
      let point = AIUsagePoint(
        id: "one", provider: .codex, date: Date(timeIntervalSince1970: 1_800_000_000),
        model: "gpt-6.1-sol", project: "Fixture", input: 1_000_000, output: 100000, cached: 900000,
        perRequest: false)
      let usage = AIUsageViewModel(
        defaults: defaults, readClaude: { nil }, initialAnalytics: AIAnalytics(points: [point]),
        initialPrices: catalog, read: { _ in nil })
      let codex = CodexUsageViewModel(
        defaults: defaults, load: { throw CodexUsageError.unavailable })
      codex.enabled = true
      usage.claudeEnabled = true
      let value = usage.estimate([point], provider: .codex)
      usage.savePrices(TokenPrices(inputUSD: 3, outputUSD: 6), provider: .codex, exchangeRate: 5)
      #expect(
        usage.usesCustomPrices(.codex) && usage.conversionRate == 5,
        "Custom prices remain an explicit optional override")
      usage.useAutomaticPrices(.codex)
      #expect(
        !usage.usesCustomPrices(.codex)
          && usage.estimate([point], provider: .codex).usd == value.usd,
        "Automatic source can be restored without losing charges")
      let restored = AIUsageViewModel(
        defaults: defaults, readClaude: { nil }, initialPrices: catalog, read: { _ in nil })
      #expect(!restored.usesCustomPrices(.codex), "Automatic preference persists")
      usage.disable(.codex, codex: codex)
      #expect(
        usage.usedProviders(codex: codex).isEmpty,
        "Disconnected providers disappear from the summary")
    }

  }
}
