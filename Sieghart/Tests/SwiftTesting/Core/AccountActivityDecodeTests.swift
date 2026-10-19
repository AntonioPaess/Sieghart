import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.activity, .logic))
  struct AccountActivityDecodeTests {
    @Test("G08.06 provider supplied daily totals and streak are preserved")
    func accountHeatmap() throws {
      let account = try JSONDecoder().decode(
        CodexAccountActivity.self,
        from: Data(
          "{\"summary\":{\"lifetimeTokens\":1200,\"peakDailyTokens\":1000,\"currentStreakDays\":2},\"dailyUsageBuckets\":[{\"startDate\":\"2026-10-05\",\"tokens\":1000}]}"
            .utf8))
      #expect(
        account.dailyUsageBuckets?.first?.tokens == 1000 && account.summary?.currentStreakDays == 2,
        "Account heatmap keeps provider-supplied days and streak")
    }

  }
}
