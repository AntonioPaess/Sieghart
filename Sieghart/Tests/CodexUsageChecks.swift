import Foundation

@main
struct CodexUsageChecks {
    @MainActor static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let json = """
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":36,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":33,"windowDurationMins":10080,"resetsAt":1800600000}}}}
        """
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
        precondition(response.codex?.primary?.remainingPercent(at: now) == 64)
        precondition(response.codex?.secondary?.remainingPercent(at: now) == 67)
        precondition(response.codex?.primary?.title == "5-hour window")
        precondition(response.codex?.secondary?.title == "Weekly")
        precondition(response.codex?.primary?.resetDate == now.addingTimeInterval(3600))
        precondition(response.codex?.primary?.remainingPercent(at: now.addingTimeInterval(3600)) == nil)
        precondition(CodexQuotaWindow(usedPercent: nil, windowDurationMins: nil, resetsAt: nil).remainingPercent(at: now) == nil)
        precondition(CodexQuotaWindow(usedPercent: 110, windowDurationMins: 1440, resetsAt: nil).remainingPercent(at: now) == 0)
        let differentBucket = try JSONDecoder().decode(CodexUsageResponse.self, from: Data("{\"rateLimitsByLimitId\":{\"other\":{\"limitId\":\"other\",\"primary\":{\"usedPercent\":0}}}}".utf8))
        precondition(differentBucket.codex == nil)
        let legacy = try JSONDecoder().decode(CodexUsageResponse.self, from: Data("{\"rateLimits\":{\"primary\":{\"usedPercent\":50}}}".utf8))
        precondition(legacy.codex?.primary?.remainingPercent(at: now) == 50)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sieghart-usage-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cli = directory.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        IFS= read -r initial
        case "$initial" in *'"initialize"'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r query
        case "$query" in *'rateLimits'*'read'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"id":2,"result":\(json)}'
        """
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let fetched = try LocalCodexUsage.fetch(executable: cli)
        precondition(fetched.codex?.primary?.remainingPercent(at: now) == 64)

        try "#!/bin/sh\nexec /bin/sleep 20\n".write(to: cli, atomically: true, encoding: .utf8)
        let started = Date()
        do { _ = try LocalCodexUsage.fetch(executable: cli, timeout: 0.2); preconditionFailure("Expected timeout") }
        catch { precondition(Date().timeIntervalSince(started) < 2) }

        let suite = "Sieghart.UsageChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CodexUsageViewModel(defaults: defaults, load: { response })
        precondition(!model.enabled && model.bucket == nil)
        model.enabled = true
        await model.refresh(force: true)
        precondition(model.bucket?.primary?.usedPercent == 36 && model.updatedAt != nil)
        model.enabled = false
        precondition(model.bucket == nil && model.updatedAt == nil)
        let failing = CodexUsageViewModel(defaults: defaults, load: { throw NSError(domain: "SECRET_TOKEN", code: 1) })
        failing.enabled = true
        await failing.refresh(force: true)
        precondition(failing.bucket == nil && !(failing.errorMessage ?? "").contains("SECRET_TOKEN"))
        let delayed = CodexUsageViewModel(defaults: defaults, load: { Thread.sleep(forTimeInterval: 0.05); return response })
        delayed.enabled = true
        let request = Task { await delayed.refresh(force: true) }
        try await Task.sleep(for: .milliseconds(10))
        delayed.enabled = false
        await request.value
        precondition(delayed.bucket == nil)
        print("PASS: real-window labels, remaining percentages, Unix resets, missing and expired data, bucket selection, stdio handshake, timeout, opt-in persistence, redacted errors, and disconnect during refresh")

        if CommandLine.arguments.contains("--live") {
            let actual = try LocalCodexUsage.fetch()
            print("LIVE: primary \(actual.codex?.primary?.remainingPercent(at: Date()).map(String.init) ?? "unavailable")% left, secondary \(actual.codex?.secondary?.remainingPercent(at: Date()).map(String.init) ?? "unavailable")% left; reset timestamps received: \(actual.codex?.primary?.resetDate != nil && actual.codex?.secondary?.resetDate != nil)")
        }
    }
}
