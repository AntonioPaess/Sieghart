import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.imports, .isolated)) @MainActor
  struct ClaudeHistoryModelTests {
    @Test("G11.02 automatic report requires opt-in and disappears when disabled")
    func historyConsent() async throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      // Only this freshness-boundary contract uses the production wall clock.
      let now = Date()
      let ms = now.timeIntervalSince1970 * 1000
      func history(_ source: String) throws -> ClaudeLimitsReport? {
        try ClaudePlanHistory.decode(Data(source.utf8), now: now)
      }
      let decodedV2 = try history(
        "{\"version\":2,\"samples\":[{\"t\":\(ms-10000),\"org\":\"old\",\"u\":{\"fh\":60,\"sd\":75}},{\"t\":\(ms),\"org\":\"new\",\"u\":{\"fh\":20,\"so\":8,\"sn\":10}}]}"
      )
      let v2 = try #require(decodedV2)
      let model = AIUsageViewModel(defaults: defaults, readClaude: { v2 }, read: { _ in nil })
      await model.refresh(codexEnabled: false)
      #expect(model.effectiveClaudeReport == nil)
      model.claudeEnabled = true
      await model.refresh(codexEnabled: false)
      #expect(
        model.effectiveClaudeReport?.primary?.usedPercent == 20
          && model.claudeSource.contains("Local history"))
      model.claudeEnabled = false
      #expect(model.automaticClaudeReport == nil)
    }

  }
}
