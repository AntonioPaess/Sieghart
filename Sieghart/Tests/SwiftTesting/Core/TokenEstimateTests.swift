import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.spending, .logic))
  struct TokenEstimateTests {
    @Test("G07.03 Decimal prices and missing inputs remain exact")
    func decimalEstimates() throws {
      let sample = LocalTokenUsage(
        input: 1_000_000, cachedInput: 250_000, cacheCreation: 50_000, output: 500_000, sessions: 1)
      let prices = TokenPrices(
        inputUSD: 2, outputUSD: 8, cachedInputUSD: Decimal(string: "0.5"), cacheCreationUSD: 3)
      #expect(prices.estimate(sample) == Decimal(string: "5.675"))
      #expect(prices.estimate(nil) == nil)
      #expect(TokenPrices(inputUSD: nil, outputUSD: 8).estimate(sample) == nil)
    }

  }
}
