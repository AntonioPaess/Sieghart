import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.imports, .localIntegration)) @MainActor
  struct ExpandedHistoryTests {
    @Test("G11.05 80 recent files expand to archived history without duplicate totals")
    func expandedHistory() async throws {
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Sieghart-History-\(UUID())")
      defer { try? FileManager.default.removeItem(at: root) }
      let sessions = root.appendingPathComponent(".codex/sessions")
      let archived = root.appendingPathComponent(".codex/archived_sessions")
      try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
      let stamp = ISO8601DateFormatter()
      func event(_ date: Date, input: Int, output: Int) -> String {
        "{\"timestamp\":\"\(stamp.string(from: date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output)}}}}\n"
      }
      let name = "session-\(UUID()).jsonl"
      let old = event(now.addingTimeInterval(-120 * 86400), input: 100, output: 10)
      let body =
        old + String(repeating: "{\"type\":\"irrelevant\"}\n", count: 120000)
        + event(now.addingTimeInterval(-1), input: 150, output: 15)
      try body.write(to: sessions.appendingPathComponent(name), atomically: true, encoding: .utf8)
      try body.write(to: archived.appendingPathComponent(name), atomically: true, encoding: .utf8)
      for index in 0..<82 {
        try event(now.addingTimeInterval(-2), input: 1, output: 0).write(
          to: sessions.appendingPathComponent("\(index)-\(UUID()).jsonl"), atomically: true,
          encoding: .utf8)
      }
      let reader = AIAnalyticsReader(home: root, codexHome: root.appendingPathComponent(".codex"))
      let recent = await reader.read(providers: [.codex], now: now)
      #expect(recent.scannedFiles == 80)
      let expanded = await reader.readFullHistory(providers: [.codex], now: now)
      #expect(
        expanded.scannedFiles == 84 && expanded.points.reduce(0) { $0 + $1.total } == 247,
        "Read the full older counter sequence, include archives, deduplicate the same session")
      let polled = await reader.read(providers: [.codex], now: now)
      #expect(
        polled.points.reduce(0) { $0 + $1.total } == 247,
        "Polling must retain broader history without adding totals twice")
      #expect(await reader.read(providers: [], now: now).points.isEmpty)
    }

  }
}
