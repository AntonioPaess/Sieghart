import Foundation

@main struct TokenSpendingChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Sieghart.TokenChecks.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent(".codex/sessions/2026/10/05"), claude = root.appendingPathComponent(".claude/projects/example")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        func codexLine(_ input: Int, _ cache: Int, _ output: Int) -> String {
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cache),\"output_tokens\":\(output),\"reasoning_output_tokens\":15}}}}"
        }
        let id = UUID().uuidString
        let log = codexLine(100, 30, 10) + "\n" + codexLine(200, 80, 40) + "\n" + codexLine(200, 80, 40) + "\n"
        try log.write(to: codex.appendingPathComponent("rollout-a-\(id).jsonl"), atomically: true, encoding: .utf8)
        try log.write(to: codex.appendingPathComponent("rollout-copy-\(id).jsonl"), atomically: true, encoding: .utf8)
        try (codexLine(50, 5, 20) + "\n").write(to: codex.appendingPathComponent("another.jsonl"), atomically: true, encoding: .utf8)
        let tokens = LocalTokenReader.read(.codex, home: root)
        precondition(tokens == LocalTokenUsage(input: 250, cachedInput: 85, cacheCreation: 0, output: 60, sessions: 2))
        precondition(tokens?.total == 310) // No double counting cache or reasoning.
        let messages = [
            #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_read_input_tokens":50,"cache_creation_input_tokens":20,"output_tokens":10}}}"#,
            #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_read_input_tokens":50,"cache_creation_input_tokens":20,"output_tokens":30}}}"#,
            #"{"type":"user","message":{"id":"u1","content":"Must not count this","usage":{"input_tokens":999999}}}"#,
            #"{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":10,"output_tokens":5}}}"#
        ].joined(separator: "\n")
        try messages.write(to: claude.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        precondition(LocalTokenReader.read(.claude, home: root) == LocalTokenUsage(input: 180, cachedInput: 50, cacheCreation: 20, output: 35, sessions: 1))
        precondition(LocalTokenReader.read(.codex, home: root.appendingPathComponent("absent")) == nil)

        let sample = LocalTokenUsage(input: 1_000_000, cachedInput: 250_000, cacheCreation: 50_000, output: 500_000, sessions: 1)
        let prices = TokenPrices(inputUSD: 2, outputUSD: 8, cachedInputUSD: Decimal(string: "0.5"), cacheCreationUSD: 3)
        precondition(prices.estimate(sample) == Decimal(string: "5.675"))
        precondition(prices.estimate(nil) == nil)
        precondition(TokenPrices(inputUSD: nil, outputUSD: 8).estimate(sample) == nil)
        let suite = "Sieghart.SpendingChecks.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let readerRoot = root
        let model = AIUsageViewModel(defaults: defaults, read: { LocalTokenReader.read($0, home: readerRoot) })
        await model.refresh(codexEnabled: false)
        precondition(model.tokens.isEmpty && !model.claudeEnabled)
        model.claudeEnabled = true
        await model.refresh(codexEnabled: true)
        precondition(model.tokens[.codex] == tokens && model.tokens[.claude]?.output == 35)
        model.claudeEnabled = false
        precondition(model.tokens[.claude] == nil)
        model.savePrices(prices, provider: .codex, exchangeRate: 5)
        let now = Date.now
        model.record(RecordedCharge(provider: .codex, date: now, amount: 20, currency: .USD, kind: .subscription))
        model.record(RecordedCharge(provider: .codex, date: now, amount: 5, currency: .USD, kind: .api))
        model.record(RecordedCharge(provider: .codex, date: now, amount: 100, currency: .BRL, kind: .api))
        model.record(RecordedCharge(provider: .claude, date: now, amount: 500, currency: .USD, kind: .api))
        model.record(RecordedCharge(provider: .codex, date: now, amount: -99, currency: .USD, kind: .api))
        precondition(model.ledger.recorded(.codex, currency: .USD, month: now) == 25)
        precondition(model.ledger.recorded(.codex, currency: .BRL, month: now) == 100)
        precondition(model.ledger.recorded(.codex, currency: .USD, month: now.addingTimeInterval(-90 * 86400)) == nil)
        let restored = AIUsageViewModel(defaults: defaults)
        precondition(restored.ledger.prices[.codex] == prices && restored.ledger.usdToBRL == 5)
        precondition(restored.ledger.charges.count == 4)
        let first = model.ledger.charges[0].id
        model.removeCharge(id: first)
        precondition(model.ledger.recorded(.codex, currency: .USD, month: now) == 5)

        let report = Data("{\"capturedAt\":\"2026-10-05T21:00:00Z\",\"primary\":{\"usedPercent\":40,\"windowDurationMins\":300,\"resetsAt\":2000000000},\"secondary\":{\"usedPercent\":60,\"windowDurationMins\":10080,\"resetsAt\":2000200000}}".utf8)
        try model.importClaudeReport(report)
        precondition(model.claudeEnabled && model.claudeReport?.primary?.window.remainingPercent(at: now) == 60)
        precondition(AIUsageViewModel(defaults: defaults).claudeReport?.secondary?.usedPercent == 60)
        let invalid = Data(String(decoding: report, as: UTF8.self).replacingOccurrences(of: "\"usedPercent\":40", with: "\"usedPercent\":101").utf8)
        do { try model.importClaudeReport(invalid); preconditionFailure("Invalid quotas accepted") } catch { }
        model.clearClaudeReport(); precondition(AIUsageViewModel(defaults: defaults).claudeReport == nil)
        print("PASS: local counters, duplicate and cumulative events, cache/reasoning accounting, opt-in, decimal estimates, separate USD/BRL charges, monthly totals, persistence, and dated Claude reports")
    }
}
