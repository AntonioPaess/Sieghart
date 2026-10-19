import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.pricing, .logic))
  struct ExchangeQuoteTests {
    @Test("G09.03 dated USD to BRL sample retains its Decimal rate")
    func datedExchange() throws {
      let quote = try JSONDecoder().decode(
        ExchangeQuote.self,
        from: Data(
          "{\"date\":\"2026-10-06\",\"base\":\"USD\",\"quote\":\"BRL\",\"rate\":5.0712}".utf8))
      #expect(
        quote.valid && quote.rate == Decimal(string: "5.0712"),
        "Actual public USD/BRL response preserves date and decimal rate")
    }

  }
}
