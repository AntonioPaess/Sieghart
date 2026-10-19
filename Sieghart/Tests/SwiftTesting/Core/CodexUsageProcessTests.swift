import Darwin
import Foundation
import Testing

private let coreQuotaProcessJSON = """
  {"rateLimits":{"limitId":"codex","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":36,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":33,"windowDurationMins":10080,"resetsAt":1800600000}}}}
  """

extension MacContractsTests {
  @Suite(.tags(.usage, .localIntegration)) @MainActor
  struct CodexUsageProcessTests {
    @Test("G06.02 owned stdio process implements the initialize and quota handshake")
    func handshake() throws {
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "sieghart-usage-checks-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let cli = directory.appendingPathComponent("codex")
      let script = """
        #!/bin/sh
        IFS= read -r initial
        case "$initial" in *'"initialize"'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        case "$initialized" in *'"initialized"'*) ;; *) exit 1 ;; esac
        IFS= read -r query
        case "$query" in *'rateLimits'*'read'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"id":2,"result":\(coreQuotaProcessJSON)}'
        """
      try script.write(to: cli, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
      let fetched = try LocalCodexUsage.fetch(executable: cli)
      #expect(fetched.codex?.primary?.remainingPercent(at: now) == 64)
    }

    @Test("G06.03 an owned unresponsive process is terminated within the deadline")
    func timeout() throws {
      let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(
        "sieghart-usage-timeout-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let cli = directory.appendingPathComponent("codex")
      let pidFile = directory.appendingPathComponent("pid")
      try "#!/bin/sh\necho $$ > '\(pidFile.path)'\nexec /bin/sleep 20\n".write(
        to: cli, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
      let started = Date()
      #expect(throws: CodexUsageError.timedOut) {
        _ = try LocalCodexUsage.fetch(executable: cli, timeout: 2)
      }
      #expect(Date().timeIntervalSince(started) < 4)
      let rawPID = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(
        in: .whitespacesAndNewlines)
      let pid = try #require(Int32(rawPID))
      #expect(kill(pid, 0) == -1, "The timed-out fixture process must be reaped")
    }

  }
}
