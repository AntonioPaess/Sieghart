import Foundation

@main struct AIActivityChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sieghart-analytics-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let uuid = UUID().uuidString, file = sessions.appendingPathComponent("rollout-\(uuid).jsonl")
        let now = Date(), formatter = ISO8601DateFormatter()
        func stamp(_ seconds: Double) -> String { formatter.string(from: now.addingTimeInterval(seconds)) }
        func line(_ type: String, _ seconds: Double, _ payload: [String: Any]) throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: ["type": type, "timestamp": stamp(seconds), "payload": payload]), encoding: .utf8)! + "\n"
        }
        var records = try line("session_meta", -30, ["cwd": "/fixture/projects/FocusApp"])
        records += try line("event_msg", -20, ["type": "task_started", "turn_id": "one"])
        records += try line("turn_context", -19, ["model": "fixture-model", "cwd": "/fixture/projects/FocusApp"])
        let fields: [String: Any] = ["input_tokens": 1000, "cached_input_tokens": 750, "output_tokens": 100, "reasoning_output_tokens": 60]
        records += try line("event_msg", -10, ["type": "token_count", "info": ["total_token_usage": fields, "last_token_usage": fields]])
        records += try line("event_msg", -9, ["type": "token_count", "info": ["total_token_usage": fields, "last_token_usage": fields]])
        try records.write(to: file, atomically: true, encoding: .utf8)
        let copy = sessions.appendingPathComponent("copy-\(uuid).jsonl")
        try records.write(to: copy, atomically: true, encoding: .utf8)
        let reader = AIAnalyticsReader(home: root)
        let active = await reader.read(providers: [.codex], now: now)
        expect(active.points.count == 1 && active.points[0].total == 1100, "Repeated counters, cloned sessions and reasoning are not added twice")
        expect(active.points[0].cached == 750 && active.points[0].project == "FocusApp" && active.points[0].model == "fixture-model", "Only metadata needed by graphs is retained")
        expect(active.work.count == 1 && active.work[0].output == 100, "Task start creates one deduplicated live activity")
        let ended = records + (try line("event_msg", -1, ["type": "task_complete", "turn_id": "one"]))
        try ended.write(to: file, atomically: true, encoding: .utf8)
        try ended.write(to: copy, atomically: true, encoding: .utf8)
        let finished = await reader.read(providers: [.codex], now: now)
        expect(finished.work.isEmpty && finished.points.count == 1, "Completion removes work while keeping graph counters")
        let disabled = await reader.read(providers: [], now: now)
        expect(disabled.points.isEmpty && disabled.work.isEmpty, "No monitoring consent yields no activity")
        let stale = AIActivityParser.parse(file, provider: .codex, now: now.addingTimeInterval(3600))
        expect(stale.work.isEmpty, "An old record cannot become active work")
        // A start marker more than 2 MiB behind the counters still has a
        // bounded metadata path; a terminal marker must win over that start.
        let padding = String(repeating: "{\"type\":\"ignored\",\"pad\":\"" + String(repeating: "x", count: 1000) + "\"}\n", count: 2300)
        let longFile = sessions.appendingPathComponent("long-\(UUID()).jsonl")
        let header = try line("event_msg", -20, ["type": "task_started", "turn_id": "long"])
            + line("turn_context", -19, ["model": "fixture-model", "service_tier": "priority"])
        let final = try line("event_msg", -1, ["type": "token_count", "info": ["total_token_usage": fields, "last_token_usage": fields]])
        try (header + padding + final).write(to: longFile, atomically: true, encoding: .utf8)
        expect(AIActivityParser.parse(longFile, provider: .codex, now: now).work.count == 1, "Long tasks recover their start outside the counter tail")
        let terminal = try line("event_msg", -10, ["type": "task_complete", "turn_id": "long"])
        try (header + terminal + padding + final).write(to: longFile, atomically: true, encoding: .utf8)
        let recovered = AIActivityParser.parse(longFile, provider: .codex, now: now)
        expect(recovered.work.isEmpty, "A terminal event outside the tail prevents phantom work")
        expect(recovered.points.first?.model == "fixture-model" && recovered.points.first?.serviceTier == "priority", "Completed long histories recover model and pricing tier before the tail")
        let noLifecycle = try line("turn_context", -19, ["model": "legacy-model"])
        try (noLifecycle + padding + final).write(to: longFile, atomically: true, encoding: .utf8)
        let metadataOnly = AIActivityParser.parse(longFile, provider: .codex, now: now)
        expect(metadataOnly.points.first?.model == "legacy-model" && metadataOnly.work.isEmpty, "Historical model recovery does not require or invent lifecycle events")
        let changed = try line("turn_context", -2, ["model": "next-model"])
            + line("event_msg", -1, ["type": "token_count", "info": ["total_token_usage": ["input_tokens": 2000, "output_tokens": 200], "last_token_usage": fields]])
        try (header + terminal + padding + final + changed).write(to: longFile, atomically: true, encoding: .utf8)
        let mixed = AIActivityParser.parse(longFile, provider: .codex, now: now).points
        expect(Set(mixed.map(\.model)) == Set(["fixture-model", "next-model"]), "Future turn context cannot relabel earlier counters")
        let direct = root.appendingPathComponent("direct.jsonl")
        let responseUsage: [String: Any] = ["input_tokens": 1000, "cached_input_tokens": 800, "cache_write_input_tokens": 50, "output_tokens": 100, "reasoning_output_tokens": 80]
        var canonical = try line("session_meta", -30, ["id": "canonical-session", "cwd": "/fixture/projects/Work"])
        canonical += try line("turn_context", -20, ["model": "gpt-6.1-sol", "service_tier": "default"])
        canonical += try line("event_msg", -15, ["type": "thread_settings_applied", "thread_settings": ["service_tier": "fast"]])
        let response = try line("token_usage_record", -10, ["response_id": "response-a", "usage": responseUsage])
        canonical += response + response
        canonical += try line("event_msg", -9, ["type": "token_count", "info": ["total_token_usage": responseUsage, "last_token_usage": responseUsage]])
        try canonical.write(to: direct, atomically: true, encoding: .utf8)
        let requests = AIActivityParser.parse(direct, provider: .codex, now: now)
        expect(requests.points.count == 1 && requests.points[0].total == 1100 && requests.points[0].cached == 800 && requests.points[0].cacheCreation == 50, "Response records take precedence over repeated quota counters, without double-counting reasoning")
        expect(requests.points[0].id == "codex:response:response-a" && requests.points[0].serviceTier == "fast" && requests.points[0].perRequest, "Response identity deduplicates clones and retains changes to Fast pricing")
        let historic = sessions.appendingPathComponent("historic-\(UUID()).jsonl")
        var initial = try line("session_meta", -30, ["id": "history-session", "cwd": "/fixture/History"])
        initial += try line("turn_context", -29, ["model": "gpt-6.1-sol"])
        initial += try line("token_usage_record", -28, ["response_id": "history-old", "usage": responseUsage])
        initial += padding
        initial += try line("token_usage_record", -5, ["response_id": "history-new", "usage": responseUsage])
        try initial.write(to: historic, atomically: true, encoding: .utf8)
        let historyReader = AIAnalyticsReader(home: root)
        let initialHistory = await historyReader.read(providers: [.codex], now: now)
        expect(initialHistory.points.contains { $0.id == "codex:response:history-old" }, "Initial automatic scan keeps counters before a long conversation tail")
        initial += try line("token_usage_record", -1, ["response_id": "history-latest", "usage": responseUsage])
        try initial.write(to: historic, atomically: true, encoding: .utf8)
        let nextHistory = await historyReader.read(providers: [.codex], now: now)
        expect(["history-old", "history-new", "history-latest"].allSatisfy { id in nextHistory.points.contains { $0.id == "codex:response:" + id } }, "Polling adds new response counters without discarding the earlier day's usage")
        let account = try JSONDecoder().decode(CodexAccountActivity.self, from: Data("{\"summary\":{\"lifetimeTokens\":1200,\"peakDailyTokens\":1000,\"currentStreakDays\":2},\"dailyUsageBuckets\":[{\"startDate\":\"2026-10-05\",\"tokens\":1000}]}".utf8))
        expect(account.dailyUsageBuckets?.first?.tokens == 1000 && account.summary?.currentStreakDays == 2, "Account heatmap keeps provider-supplied days and streak")
        let claude = sessions.appendingPathComponent("claude-fixture.jsonl")
        let message: [String: Any] = ["type": "assistant", "timestamp": stamp(-2), "cwd": "/fixture/ClaudeProject", "message": ["id": "stream-one", "model": "claude-fixture", "stop_reason": "end_turn", "usage": ["input_tokens": 100, "cache_read_input_tokens": 20, "cache_creation_input_tokens": 10, "output_tokens": 40]]]
        let encoded = try JSONSerialization.data(withJSONObject: message)
        try encoded.write(to: claude)
        let claudeReading = AIActivityParser.parse(claude, provider: .claude, now: now)
        expect(claudeReading.points.first?.input == 130 && claudeReading.points.first?.cacheCreation == 10 && claudeReading.work.isEmpty, "Claude graph counters preserve cache creation and terminal state")
        let suite = "Sieghart.OnboardingChecks.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = CompanionPreferences(defaults: defaults)
        expect(!prefs.onboardingComplete && CompanionAvatar.allCases.count == 6, "First run presents exactly six choices")
        prefs.avatar = .coastBuddy; prefs.onboardingComplete = true
        let restored = CompanionPreferences(defaults: defaults)
        expect(restored.onboardingComplete && restored.avatar == .coastBuddy, "Finishing onboarding preserves choice across relaunch")
        print("PASS: AI lifecycle, graph counter deduplication, account activity and six-avatar onboarding persistence")
    }
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError("FAIL: \(message)") }
    }
}
