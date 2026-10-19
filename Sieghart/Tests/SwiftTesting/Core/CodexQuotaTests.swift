import Foundation
import Testing

private let coreQuotaJSON = """
  {"rateLimits":{"limitId":"codex","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":36,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":33,"windowDurationMins":10080,"resetsAt":1800600000}}}}
  """

extension LogicTests {
  @Suite(.tags(.usage, .logic))
  struct CodexQuotaTests {
    @Test("G06.01 bucket precedence, fallback, labels, clamps and resets")
    func quotas() throws {
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let response = try JSONDecoder().decode(
        CodexUsageResponse.self, from: Data(coreQuotaJSON.utf8))
      #expect(response.codex?.primary?.remainingPercent(at: now) == 64)
      #expect(response.codex?.secondary?.remainingPercent(at: now) == 67)
      #expect(response.codex?.primary?.title == "5-hour window")
      #expect(response.codex?.secondary?.title == "Weekly")
      #expect(response.codex?.primary?.resetDate == now.addingTimeInterval(3600))
      #expect(response.codex?.primary?.remainingPercent(at: now.addingTimeInterval(3600)) == nil)
      #expect(
        CodexQuotaWindow(usedPercent: nil, windowDurationMins: nil, resetsAt: nil).remainingPercent(
          at: now) == nil)
      #expect(
        CodexQuotaWindow(usedPercent: 110, windowDurationMins: 1440, resetsAt: nil)
          .remainingPercent(at: now) == 0)
      let differentBucket = try JSONDecoder().decode(
        CodexUsageResponse.self,
        from: Data(
          "{\"rateLimitsByLimitId\":{\"other\":{\"limitId\":\"other\",\"primary\":{\"usedPercent\":0}}}}"
            .utf8))
      #expect(differentBucket.codex == nil)
      let legacy = try JSONDecoder().decode(
        CodexUsageResponse.self,
        from: Data("{\"rateLimits\":{\"primary\":{\"usedPercent\":50}}}".utf8))
      #expect(legacy.codex?.primary?.remainingPercent(at: now) == 50)
    }

  }
}
