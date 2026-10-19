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

  }
}
