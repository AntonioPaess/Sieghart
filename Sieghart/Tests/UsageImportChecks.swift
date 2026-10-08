import Foundation

@main struct UsageImportChecks {
    static func check(_ value: Bool) { precondition(value) }
    @MainActor static func main() async throws {
        let now = Date(), ms = now.timeIntervalSince1970 * 1000
        func history(_ source: String) throws -> ClaudeLimitsReport? { try ClaudePlanHistory.decode(Data(source.utf8), now: now) }
        let v1 = try history("{\"version\":1,\"samples\":[{\"t\":\(ms),\"fh\":42.5,\"sd\":17}]}")!
        precondition(v1.primary?.usedPercent == 42.5 && v1.secondary?.windowDurationMins == 10080 && v1.primary?.resetsAt == nil)
        let v2 = try history("{\"version\":2,\"samples\":[{\"t\":\(ms-10000),\"org\":\"old\",\"u\":{\"fh\":60,\"sd\":75}},{\"t\":\(ms),\"org\":\"new\",\"u\":{\"fh\":20,\"so\":8,\"sn\":10}}]}")!
        precondition(v2.primary?.usedPercent == 20 && v2.secondary == nil && v2.scoped?.count == 2, "Organizations and readings must not combine")
        let stale = try history("{\"version\":1,\"samples\":[{\"t\":\(ms-1800001),\"fh\":20}]}"); precondition(stale == nil)
        check(try history("{\"version\":2,\"samples\":[{\"t\":\(ms),\"u\":{\"fh\":true,\"sd\":101}}]}") == nil)
        check(try history("{\"version\":1,\"samples\":[{\"t\":\(ms+900000),\"fh\":20}]}") == nil)
        do { _ = try history("{\"version\":true,\"samples\":[]}"); preconditionFailure("Boolean version accepted") } catch {}
        do { _ = try history("{\"version\":3,\"samples\":[]}"); preconditionFailure("Unknown version accepted") } catch {}

        let suite = "Sieghart.UsageImportChecks.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AIUsageViewModel(defaults: defaults, readClaude: { v2 }, read: { _ in nil })
        await model.refresh(codexEnabled: false)
        precondition(model.effectiveClaudeReport == nil)
        model.claudeEnabled = true; await model.refresh(codexEnabled: false)
        precondition(model.effectiveClaudeReport?.primary?.usedPercent == 20 && model.claudeSource.contains("Local history"))
        model.claudeEnabled = false; precondition(model.automaticClaudeReport == nil)

        let csv = "\u{feff}reference,provider,date,amount,currency,kind\r\n\"invoice,001\",codex,2026-10-01,20.05,USD,Subscription\r\ninvoice-2,claude,2026-10-02,12.123456,BRL,API\r\n"
        let charges = try ChargeFile.decode(Data(csv.utf8), csv: true, source: "fixture.csv", now: now)
        precondition(charges.count == 2 && charges[0].externalID == "invoice,001" && charges[0].amount == Decimal(string: "20.05"))
        precondition(Calendar.current.component(.day, from: charges[0].date) == 1 && Calendar.current.component(.month, from: charges[0].date) == 10, "Date-only invoices must keep their local billing month")
        check(try model.importCharges(charges) == 2)
        check(try model.importCharges(charges) == 0)
        let roundtrip = try ChargeFile.decode(ChargeFile.export(charges), csv: false, source: "export.json", now: now)
        check(try ChargeFile.additions(roundtrip, existing: charges).isEmpty)
        var changed = csv.replacingOccurrences(of: "20.05", with: "20.06")
        let conflicts = try ChargeFile.decode(Data(changed.utf8), csv: true, source: "changed.csv", now: now)
        do { _ = try model.importCharges(conflicts); preconditionFailure("Conflicting reference accepted") } catch {}
        precondition(model.ledger.charges.count == 2 && model.ledger.charges[0].amount == Decimal(string: "20.05"))
        changed = csv.replacingOccurrences(of: "12.123456", with: "-2")
        do { _ = try ChargeFile.decode(Data(changed.utf8), csv: true, source: "bad.csv", now: now); preconditionFailure("Invalid batch accepted") } catch {}
        do { _ = try ChargeFile.decode(Data("reference,provider,date,amount,currency,kind\n\"unclosed".utf8), csv: true, source: "bad.csv", now: now); preconditionFailure("Malformed CSV accepted") } catch {}
        let restored = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
        precondition(restored.ledger.charges.count == 2 && restored.ledger.charges.first?.source == "fixture.csv")
        let manual = RecordedCharge(provider: .codex, date: now, amount: 9, currency: .USD, kind: .api)
        let manualRoundtrip = try ChargeFile.decode(ChargeFile.export([manual]), csv: false, source: "export.json", now: now)
        check(try ChargeFile.additions(manualRoundtrip, existing: [manual]).isEmpty)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Sieghart-History-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent(".codex/sessions"), archived = root.appendingPathComponent(".codex/archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter()
        func event(_ date: Date, input: Int, output: Int) -> String { "{\"timestamp\":\"\(stamp.string(from: date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output)}}}}\n" }
        let name = "session-\(UUID()).jsonl"
        let old = event(now.addingTimeInterval(-120 * 86400), input: 100, output: 10)
        let body = old + String(repeating: "{\"type\":\"irrelevant\"}\n", count: 120000) + event(now.addingTimeInterval(-1), input: 150, output: 15)
        try body.write(to: sessions.appendingPathComponent(name), atomically: true, encoding: .utf8)
        try body.write(to: archived.appendingPathComponent(name), atomically: true, encoding: .utf8)
        for index in 0..<82 { try event(now.addingTimeInterval(-2), input: 1, output: 0).write(to: sessions.appendingPathComponent("\(index)-\(UUID()).jsonl"), atomically: true, encoding: .utf8) }
        let reader = AIAnalyticsReader(home: root, codexHome: root.appendingPathComponent(".codex"))
        let recent = await reader.read(providers: [.codex], now: now)
        precondition(recent.scannedFiles == 80)
        let expanded = await reader.readFullHistory(providers: [.codex], now: now)
        precondition(expanded.scannedFiles == 84 && expanded.points.reduce(0) { $0 + $1.total } == 247, "Read the full older counter sequence, include archives, deduplicate the same session")
        let polled = await reader.read(providers: [.codex], now: now)
        precondition(polled.points.reduce(0) { $0 + $1.total } == 247, "Polling must retain broader history without adding totals twice")
        check(await reader.read(providers: [], now: now).points.isEmpty)
        print("PASS: automatic Claude v1/v2 quotas, staleness/account isolation, atomic CSV/JSON charges and export deduplication, broader archived history and polling")
    }
}
