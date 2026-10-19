import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.pricing, .logic))
  struct PriceCatalogTests {
    @Test("G09.01 exact aliases, tier and router lookup use the versioned catalog")
    func versionedCatalog() throws {
      let catalog = PriceCatalog.bundled(file: TestResources.priceCatalogURL)
      #expect(catalog.entries.count >= 59, "Bundled official numeric price facts decode")
      #expect(
        catalog.price(model: "gpt-6.1-sol", provider: .codex)?.rates.inputUSD == 2,
        "Exact model rates are used")
      #expect(
        catalog.price(model: "gpt-6.1-sol-2026-10-05", provider: .codex)?.id == "gpt-6.1-sol",
        "Dated snapshots resolve documented base rates")
      #expect(
        catalog.price(model: "codex-auto-review", provider: .codex) == nil,
        "Internal models never inherit an invented price")
      #expect(
        catalog.price(model: "gpt-6.1-sol-unknown", provider: .codex) == nil,
        "Unverified aliases remain unpriced")
      #expect(
        catalog.price(model: "gpt-6.1-sol", provider: .codex, tier: "priority")?.rates.inputUSD
          == 4, "Known fast tier uses published tier rate")
      #expect(
        catalog.price(model: "openai/gpt-6.1-sol", provider: .codex, tier: "FAST")?.rates.inputUSD
          == 4, "Router prefix and case preserve the recorded Fast price")
    }

  }
}
