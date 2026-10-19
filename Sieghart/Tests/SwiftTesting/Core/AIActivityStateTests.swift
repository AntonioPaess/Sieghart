import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.activity, .isolated)) @MainActor
  struct AIActivityStateTests {
    @Test("G08.02 only current real work drives processing")
    func processingState() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let now = Date(timeIntervalSince1970: 1_800_000_000)

      let work = AIWork(
        id: "one", provider: .codex, model: "fixture-model", project: "FocusApp",
        startedAt: now.addingTimeInterval(-20), lastSeen: now.addingTimeInterval(-10), output: 100)
      let activeModel = AIUsageViewModel(
        defaults: defaults, readClaude: { nil }, initialAnalytics: AIAnalytics(work: [work]),
        read: { _ in nil })
      let completedModel = AIUsageViewModel(
        defaults: defaults, readClaude: { nil }, initialAnalytics: AIAnalytics(), read: { _ in nil }
      )
      #expect(activeModel.hasCurrentWork(at: now))
      #expect(!activeModel.hasCurrentWork(at: now.addingTimeInterval(301)))
      #expect(!completedModel.hasCurrentWork(at: now) && !completedModel.hasPendingRead)
    }

  }
}
