import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.spending, .isolated)) @MainActor
  struct ClaudeReportTests {
    @Test("G07.06 dated Claude report persists, rejects invalid percentage and clears")
    func datedReports() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let model = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
      let report = Data(
        "{\"capturedAt\":\"2026-10-05T21:00:00Z\",\"primary\":{\"usedPercent\":40,\"windowDurationMins\":300,\"resetsAt\":2000000000},\"secondary\":{\"usedPercent\":60,\"windowDurationMins\":10080,\"resetsAt\":2000200000}}"
          .utf8)
      try model.importClaudeReport(report)
      #expect(
        model.claudeEnabled && model.claudeReport?.primary?.window.remainingPercent(at: now) == 60)
      #expect(
        AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil }).claudeReport?
          .secondary?.usedPercent == 60)
      let invalid = Data(
        String(decoding: report, as: UTF8.self).replacingOccurrences(
          of: "\"usedPercent\":40", with: "\"usedPercent\":101"
        ).utf8)
      #expect(throws: (any Error).self) { try model.importClaudeReport(invalid) }
      model.clearClaudeReport()
      #expect(
        AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil }).claudeReport
          == nil)
    }

  }
}
