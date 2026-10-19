import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.spending, .localIntegration)) @MainActor
  struct LocalTokenReaderTests {
    @Test("G07.01 cumulative counters and cloned sessions do not count reasoning or cache twice")
    func codexCounters() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Sieghart.TokenChecks.\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: root) }
      let codex = root.appendingPathComponent(".codex/sessions/2026/10/05")
      let claude = root.appendingPathComponent(".claude/projects/example")
      try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
      func codexLine(_ input: Int, _ cache: Int, _ output: Int) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cache),\"output_tokens\":\(output),\"reasoning_output_tokens\":15}}}}"
      }
      let id = UUID().uuidString
      let log =
        codexLine(100, 30, 10) + "\n" + codexLine(200, 80, 40) + "\n" + codexLine(200, 80, 40)
        + "\n"
      try log.write(
        to: codex.appendingPathComponent("rollout-a-\(id).jsonl"), atomically: true, encoding: .utf8
      )
      try log.write(
        to: codex.appendingPathComponent("rollout-copy-\(id).jsonl"), atomically: true,
        encoding: .utf8)
      try (codexLine(50, 5, 20) + "\n").write(
        to: codex.appendingPathComponent("another.jsonl"), atomically: true, encoding: .utf8)
      let tokens = LocalTokenReader.read(
        .codex, home: root, codexHome: root.appendingPathComponent(".codex"))
      #expect(
        tokens
          == LocalTokenUsage(input: 250, cachedInput: 85, cacheCreation: 0, output: 60, sessions: 2)
      )
      #expect(tokens?.total == 310)  // No double counting cache or reasoning.
    }

    @Test("G07.02 latest Claude messages preserve cache creation and ignore users")
    func claudeCounters() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Sieghart.TokenChecks.\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: root) }
      let codex = root.appendingPathComponent(".codex/sessions/2026/10/05")
      let claude = root.appendingPathComponent(".claude/projects/example")
      try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
      func codexLine(_ input: Int, _ cache: Int, _ output: Int) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cache),\"output_tokens\":\(output),\"reasoning_output_tokens\":15}}}}"
      }
      let id = UUID().uuidString
      let log =
        codexLine(100, 30, 10) + "\n" + codexLine(200, 80, 40) + "\n" + codexLine(200, 80, 40)
        + "\n"
      try log.write(
        to: codex.appendingPathComponent("rollout-a-\(id).jsonl"), atomically: true, encoding: .utf8
      )
      try log.write(
        to: codex.appendingPathComponent("rollout-copy-\(id).jsonl"), atomically: true,
        encoding: .utf8)
      try (codexLine(50, 5, 20) + "\n").write(
        to: codex.appendingPathComponent("another.jsonl"), atomically: true, encoding: .utf8)
      let messages = [
        #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_read_input_tokens":50,"cache_creation_input_tokens":20,"output_tokens":10}}}"#,
        #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_read_input_tokens":50,"cache_creation_input_tokens":20,"output_tokens":30}}}"#,
        #"{"type":"user","message":{"id":"u1","content":"Must not count this","usage":{"input_tokens":999999}}}"#,
        #"{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":10,"output_tokens":5}}}"#,
      ].joined(separator: "\n")
      try messages.write(
        to: claude.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
      #expect(
        LocalTokenReader.read(.claude, home: root, codexHome: root.appendingPathComponent(".codex"))
          == LocalTokenUsage(
            input: 180, cachedInput: 50, cacheCreation: 20, output: 35, sessions: 1))
      #expect(
        LocalTokenReader.read(
          .codex, home: root.appendingPathComponent("absent"),
          codexHome: root.appendingPathComponent("absent/.codex")) == nil)
    }

    @Test("G07.03 Antigravity transcript counters traverse .system_generated logs and skip transcript_full")
    func antigravityCounters() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Sieghart.AntigravityTokenChecks.\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: root) }
      let convLogs = root.appendingPathComponent(
        ".gemini/antigravity/brain/conv-1/.system_generated/logs")
      try FileManager.default.createDirectory(at: convLogs, withIntermediateDirectories: true)
      let lines = [
        #"{"step_index":1,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-10-19T12:00:00Z","content":"hello"}"#,
        #"{"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-19T12:00:05Z","input_tokens":400,"cache_read_tokens":1200,"output_tokens":80}"#,
        #"{"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-19T12:00:05Z","input_tokens":400,"cache_read_tokens":1200,"output_tokens":150}"#,
        #"{"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-19T12:01:00Z","input_tokens":100,"cache_read_tokens":1500,"output_tokens":50}"#,
      ].joined(separator: "\n")
      try lines.write(
        to: convLogs.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
      // Must be ignored so tokens are not double-counted:
      try lines.write(
        to: convLogs.appendingPathComponent("transcript_full.jsonl"), atomically: true,
        encoding: .utf8)
      let usage = LocalTokenReader.read(.antigravity, home: root)
      #expect(
        usage
          == LocalTokenUsage(
            input: 3200, cachedInput: 2700, cacheCreation: 0, output: 200, sessions: 1)
      )
      #expect(usage?.total == 3400)
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let iso = ISO8601DateFormatter()
      let shortReset = iso.string(from: now.addingTimeInterval(2 * 3600))
      let weeklyReset = iso.string(from: now.addingTimeInterval(5 * 86400))
      let statusJSON = """
        {
          "userStatus": {
            "planStatus": {
              "planInfo": { "planName": "Pro" }
            },
            "cascadeModelConfigData": {
              "clientModelConfigs": [
                {
                  "label": "Gemini 4 Argon",
                  "quotaInfo": { "remainingFraction": 0.4, "resetTime": "\(shortReset)" }
                },
                {
                  "label": "Gemini 3.8 Flash",
                  "quotaInfo": { "remainingFraction": 0.8, "resetTime": "\(weeklyReset)" }
                }
              ]
            }
          }
        }
        """
      let report = AntigravityPlanHistory.parseUserStatus(
        Data(statusJSON.utf8), now: now)
      #expect(report?.planType == "Pro")
      #expect(report?.primary?.usedPercent == 60)
      #expect(report?.primary?.windowDurationMins == 300)
      #expect(report?.secondary?.usedPercent == 20)
      #expect(report?.secondary?.windowDurationMins == 10080)
      #expect(report?.scoped?.count == 2)
    }

  }
}
