import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.imports, .isolated)) @MainActor
  struct ChargeImportTests {
    @Test("G11.03 repeated charge import adds nothing")
    func idempotentImport() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let model = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let csv =
        "\u{feff}reference,provider,date,amount,currency,kind\r\n\"invoice,001\",codex,2026-10-01,20.05,USD,Subscription\r\ninvoice-2,claude,2026-10-02,12.123456,BRL,API\r\n"
      let charges = try ChargeFile.decode(
        Data(csv.utf8), csv: true, source: "fixture.csv", now: now)
      #expect(try model.importCharges(charges) == 2)
      #expect(try model.importCharges(charges) == 0)
      let roundtrip = try ChargeFile.decode(
        ChargeFile.export(charges), csv: false, source: "export.json", now: now)
      #expect(try ChargeFile.additions(roundtrip, existing: charges).isEmpty)
    }

    @Test("G11.04 conflicting reference rejects the whole import and source persists")
    func atomicConflict() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let model = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let csv =
        "\u{feff}reference,provider,date,amount,currency,kind\r\n\"invoice,001\",codex,2026-10-01,20.05,USD,Subscription\r\ninvoice-2,claude,2026-10-02,12.123456,BRL,API\r\n"
      let charges = try ChargeFile.decode(
        Data(csv.utf8), csv: true, source: "fixture.csv", now: now)
      _ = try model.importCharges(charges)
      var changed = csv.replacingOccurrences(of: "20.05", with: "20.06")
      let conflicts = try ChargeFile.decode(
        Data(changed.utf8), csv: true, source: "changed.csv", now: now)
      #expect(throws: (any Error).self) { _ = try model.importCharges(conflicts) }
      #expect(
        model.ledger.charges.count == 2
          && model.ledger.charges[0].amount == Decimal(string: "20.05"))
      let restored = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
      #expect(
        restored.ledger.charges.count == 2 && restored.ledger.charges.first?.source == "fixture.csv"
      )
    }

  }
}
