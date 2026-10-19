import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.imports, .logic))
  struct ClaudeHistoryDecodeTests {
    @Test("G11.01 latest isolated organization, scoped quotas, stale and invalid samples")
    func historyVersions() throws {
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let ms = now.timeIntervalSince1970 * 1000
      func history(_ source: String) throws -> ClaudeLimitsReport? {
        try ClaudePlanHistory.decode(Data(source.utf8), now: now)
      }
      let decodedV1 = try history(
        "{\"version\":1,\"samples\":[{\"t\":\(ms),\"fh\":42.5,\"sd\":17}]}")
      let v1 = try #require(decodedV1)
      #expect(
        v1.primary?.usedPercent == 42.5 && v1.secondary?.windowDurationMins == 10080
          && v1.primary?.resetsAt == nil)
      let decodedV2 = try history(
        "{\"version\":2,\"samples\":[{\"t\":\(ms-10000),\"org\":\"old\",\"u\":{\"fh\":60,\"sd\":75}},{\"t\":\(ms),\"org\":\"new\",\"u\":{\"fh\":20,\"so\":8,\"sn\":10}}]}"
      )
      let v2 = try #require(decodedV2)
      #expect(
        v2.primary?.usedPercent == 20 && v2.secondary == nil && v2.scoped?.count == 2,
        "Organizations and readings must not combine")
      let stale = try history("{\"version\":1,\"samples\":[{\"t\":\(ms-1_800_001),\"fh\":20}]}")
      #expect(stale == nil)
      #expect(
        try history("{\"version\":2,\"samples\":[{\"t\":\(ms),\"u\":{\"fh\":true,\"sd\":101}}]}")
          == nil)
      #expect(try history("{\"version\":1,\"samples\":[{\"t\":\(ms+900000),\"fh\":20}]}") == nil)
      #expect(throws: (any Error).self) { _ = try history("{\"version\":true,\"samples\":[]}") }
      #expect(throws: (any Error).self) { _ = try history("{\"version\":3,\"samples\":[]}") }
    }

  }
}
