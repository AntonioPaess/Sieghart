import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.spending, .isolated)) @MainActor
  struct SpendingModelTests {
    @Test("G07.04 per-provider opt-in and disconnect control fixture-only counters")
    func providerConsent() async throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }

      let codex = LocalTokenUsage(
        input: 250, cachedInput: 85, cacheCreation: 0, output: 60, sessions: 2)
      let claude = LocalTokenUsage(
        input: 180, cachedInput: 50, cacheCreation: 20, output: 35, sessions: 1)
      let model = AIUsageViewModel(
        defaults: defaults, readClaude: { nil }, read: { $0 == .codex ? codex : claude })
      await model.refresh(codexEnabled: false)
      #expect(model.tokens.isEmpty && !model.claudeEnabled)
      model.claudeEnabled = true
      await model.refresh(codexEnabled: true)
      #expect(model.tokens[.codex] == codex && model.tokens[.claude] == claude)
      model.claudeEnabled = false
      #expect(model.tokens[.claude] == nil)
    }

  }
}
