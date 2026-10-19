import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.clipboard, .localIntegration)) @MainActor
  struct ClipboardStorageTests {
    @Test("G12.06 old writes are ignored and an existing directory remains private")
    func diskRevisions() async throws {
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      var pinned = ClipboardEntry(
        payload: ClipboardPayload(kind: .text, text: "Pinned fixture"), copiedAt: now,
        sourceName: "Fixture", sourceBundle: "fixture")
      pinned.pinned = true
      let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Sieghart-Clipboard-\(UUID())")
      defer { try? FileManager.default.removeItem(at: temporary) }
      try FileManager.default.createDirectory(
        at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
      let file = temporary.appendingPathComponent("history.json")
      let disk = LocalClipboardStorage(url: file)
      try await disk.save([pinned], revision: 2)
      try await disk.save([], revision: 1)
      let diskItems = try await disk.load()
      #expect(diskItems == [pinned])
      let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
      let permission = try #require(fileAttributes[.posixPermissions] as? NSNumber).intValue
      #expect(permission == 0o600)
      let parentAttributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
      let parentPermission = try #require(parentAttributes[.posixPermissions] as? NSNumber).intValue
      #expect(parentPermission == 0o700, "An existing history directory is private too")
    }

  }
}
