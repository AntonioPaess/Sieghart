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

extension MacContractsTests {
  @Suite(.tags(.pricing, .isolated)) @MainActor struct AntigravityPricingTests {
    @Test("G09.04 verified API equivalents reject unknown aliases and expire promotional rates")
    func verifiedRatesAndAliases() throws {
      let catalog = PriceCatalog.bundled(file: TestResources.priceCatalogURL)
      let now = try #require(AIActivityParser.parseDate("2026-10-19T12:00:00Z"))
      #expect(catalog.price(model: "gemini-4-argon", provider: .antigravity, now: now)?.rates.inputUSD == 2)
      #expect(catalog.price(model: "gemini-3.8-flash", provider: .antigravity, now: now)?.rates.outputUSD == Decimal(string: "3.75"))
      #expect(catalog.price(model: "claude-sonnet-5.5", provider: .antigravity, now: now)?.rates.cachedInputUSD == Decimal(string: "0.10"))
      for model in ["gemini-antigravity", "gemini-4-argon-high", "gpt-oss-120b"] {
        #expect(catalog.price(model: model, provider: .antigravity, now: now) == nil)
      }
      let expired = try #require(AIActivityParser.parseDate("2026-12-01T00:00:00Z"))
      #expect(catalog.price(model: "gemini-4-argon", provider: .antigravity, now: expired) == nil)
      #expect(catalog.price(model: "gemini-2.5-pro", provider: .antigravity, now: now)?.longContextThreshold == 200000)
      let store = try TestDefaults(); defer { store.cleanup() }
      let model = AIUsageViewModel(defaults: store.value, readClaude: { nil }, readAntigravity: { nil }, initialPrices: catalog, read: { _ in nil })
      let point = AIUsagePoint(id: "large-gemini", provider: .antigravity, date: now, model: "gemini-2.5-pro", project: "Fixture", input: 250000, output: 100000, cached: 0, perRequest: true)
      #expect(model.estimate([point], provider: .antigravity).usd == Decimal(string: "2.125"))
    }
    @Test("G09.04 upgrade discards unverified cached Antigravity prices while retaining other providers")
    func cacheMigration() throws {
      let store = try TestDefaults(); defer { store.cleanup() }
      let bad = ModelPrice(id: "gemini-antigravity", provider: .antigravity, input: "99", output: "99", source: "fixture", checked: "2026-10-19")
      let good = ModelPrice(id: "fixture-codex", provider: .codex, input: "1", output: "2", source: "fixture", checked: "2026-10-19")
      store.value.set(try JSONEncoder().encode(PriceCatalog(entries: [bad, good])), forKey: "integrations.modelPrices")
      let model = AIUsageViewModel(defaults: store.value, readClaude: { nil }, readAntigravity: { nil }, read: { _ in nil })
      #expect(!model.priceCatalog.entries.contains { $0.id == bad.id })
      #expect(model.priceCatalog.entries.contains { $0.id == good.id })
    }
  }
}
