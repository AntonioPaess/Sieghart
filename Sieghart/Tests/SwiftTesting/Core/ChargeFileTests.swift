import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.imports, .logic))
  struct ChargeFileTests {
    @Test("G11.03 BOM, CRLF, quoting, monetary precision, local day and JSON roundtrip")
    func csvAndJSON() throws {
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let csv =
        "\u{feff}reference,provider,date,amount,currency,kind\r\n\"invoice,001\",codex,2026-10-01,20.05,USD,Subscription\r\ninvoice-2,claude,2026-10-02,12.123456,BRL,API\r\n"
      let charges = try ChargeFile.decode(
        Data(csv.utf8), csv: true, source: "fixture.csv", now: now)
      #expect(
        charges.count == 2 && charges[0].externalID == "invoice,001"
          && charges[0].amount == Decimal(string: "20.05"))
      try #require(charges.count == 2)
      #expect(
        Calendar.current.component(.day, from: charges[0].date) == 1
          && Calendar.current.component(.month, from: charges[0].date) == 10,
        "Date-only invoices must keep their local billing month")
      let roundtrip = try ChargeFile.decode(
        ChargeFile.export(charges), csv: false, source: "export.json", now: now)
      #expect(try ChargeFile.additions(roundtrip, existing: charges).isEmpty)
    }

    @Test("G11.04 negative batch, malformed quotes and manual export preserve atomicity")
    func invalidFiles() throws {
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let csv =
        "\u{feff}reference,provider,date,amount,currency,kind\r\n\"invoice,001\",codex,2026-10-01,20.05,USD,Subscription\r\ninvoice-2,claude,2026-10-02,12.123456,BRL,API\r\n"
      let invalid = csv.replacingOccurrences(of: "12.123456", with: "-2")
      #expect(throws: (any Error).self) {
        _ = try ChargeFile.decode(Data(invalid.utf8), csv: true, source: "bad.csv", now: now)
      }
      #expect(throws: (any Error).self) {
        _ = try ChargeFile.decode(
          Data("reference,provider,date,amount,currency,kind\n\"unclosed".utf8), csv: true,
          source: "bad.csv", now: now)
      }
      let manual = RecordedCharge(
        provider: .codex, date: now, amount: 9, currency: .USD, kind: .api)
      let manualRoundtrip = try ChargeFile.decode(
        ChargeFile.export([manual]), csv: false, source: "export.json", now: now)
      #expect(try ChargeFile.additions(manualRoundtrip, existing: [manual]).isEmpty)
    }

  }
}
