import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.pricing, .logic))
  struct PriceCatalogParserTests {
    @Test("G09.02 standard, batch and Claude cache durations stay distinct")
    func markdownTables() throws {
      let markdown = """
        ### Standard pricing data
        | Model | Short context input | Short context cached input | Short context cache writes | Short context output | Long context input | Long context cached input | Long context cache writes | Long context output |
        | gpt-fixture | $2.00 | $0.10 | $2.50 | $10.00 | $4.00 | $0.20 | $5.00 | $15.00 |
        ### Batch pricing data
        | Model | Short context input | Short context cached input | Short context cache writes | Short context output | Long context input | Long context cached input | Long context cache writes | Long context output |
        | gpt-fixture | $1.00 | $0.05 | - | $5.00 | - | - | - | - |
        """
      let parsed = PriceCatalog.parse(markdown, provider: .codex)
      #expect(
        parsed.count == 2 && parsed.first?.tier == nil && parsed.last?.tier == "batch",
        "Parser separates standard and batch sections")
      #expect(
        PriceCatalog.parse("Unexpected source format", provider: .codex).isEmpty,
        "Changed source format cannot fabricate rates")
      let claude = """
        | Model | Base input tokens | 5m cache writes | 1h cache writes | Cache hits and refreshes | Output tokens |
        | Claude Sonnet 4.6 | $3 / MTok | $3.75 / MTok | $6 / MTok | $0.30 / MTok | $15 / MTok |
        """
      let parsedClaude = PriceCatalog.parse(claude, provider: .claude)
      #expect(
        parsedClaude.first?.id == "claude-sonnet-4-6" && parsedClaude.first?.creationLong == "6",
        "Claude cache-write durations are distinct")
    }

  }
}
