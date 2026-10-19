import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.spending, .isolated)) @MainActor
  struct ChargeLedgerTests {
    @Test("G07.05 currency, provider, billing month, validation and identity persist")
    func ledger() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let model = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
      let prices = TokenPrices(
        inputUSD: 2, outputUSD: 8, cachedInputUSD: Decimal(string: "0.5"), cacheCreationUSD: 3)
      model.savePrices(prices, provider: .codex, exchangeRate: 5)
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      model.record(
        RecordedCharge(provider: .codex, date: now, amount: 20, currency: .USD, kind: .subscription)
      )
      model.record(
        RecordedCharge(provider: .codex, date: now, amount: 5, currency: .USD, kind: .api))
      model.record(
        RecordedCharge(provider: .codex, date: now, amount: 100, currency: .BRL, kind: .api))
      model.record(
        RecordedCharge(provider: .claude, date: now, amount: 500, currency: .USD, kind: .api))
      model.record(
        RecordedCharge(provider: .codex, date: now, amount: -99, currency: .USD, kind: .api))
      #expect(model.ledger.recorded(.codex, currency: .USD, month: now) == 25)
      #expect(model.ledger.recorded(.codex, currency: .BRL, month: now) == 100)
      #expect(
        model.ledger.recorded(.codex, currency: .USD, month: now.addingTimeInterval(-90 * 86400))
          == nil)
      let restored = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
      #expect(restored.ledger.prices[.codex] == prices && restored.ledger.usdToBRL == 5)
      #expect(restored.ledger.charges.count == 4)
      let first = try #require(model.ledger.charges.first).id
      model.removeCharge(id: first)
      #expect(model.ledger.recorded(.codex, currency: .USD, month: now) == 5)
    }

  }
}
