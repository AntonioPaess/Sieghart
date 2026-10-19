import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.clipboard, .isolated)) @MainActor
  struct ClipboardRetentionTests {
    @Test("G12.04 persistence, pins, bounds, lid cleanup and simulated reboot")
    func retention() async throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let now = Date(timeIntervalSince1970: 1_790_000_000)
      let access = CoreClipboard()
      let store = CoreClipboardStorage()
      let model = ClipboardViewModel(
        defaults: defaults, access: access, storage: store, monitorsSystem: false, now: { now },
        bootTime: { 1_780_000_000 })
      await model.restore()
      await model.poll(sourceName: "Example", sourceBundle: "example")

      model.isEnabled = true
      access.content = ClipboardPayload(kind: .text, text: "Copied while disabled")
      await model.poll(sourceName: "Example", sourceBundle: "example")
      // enabling only establishes a baseline
      access.count += 1
      access.content = ClipboardPayload(kind: .text, text: "A useful first copy")
      await model.poll(sourceName: "Editor", sourceBundle: "example.editor")

      let original = try #require(model.entries.first)
      model.togglePin(original.id)
      access.count += 1
      await model.poll(sourceName: "Browser", sourceBundle: "example.browser")

      let image = try #require(
        Data(
          base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII="
        ))
      model.record(
        ClipboardPayload(kind: .image, image: image), sourceName: "Preview",
        sourceBundle: "example.preview")
      model.record(
        ClipboardPayload(kind: .files, files: [URL(fileURLWithPath: "/tmp/example.pdf")]),
        sourceName: "Finder", sourceBundle: "com.apple.finder")

      model.record(
        ClipboardPayload(kind: .text, text: "Marked source test"), sourceName: "Passwords",
        sourceBundle: "com.apple.Passwords")

      model.includeMedia = false
      model.record(
        ClipboardPayload(kind: .image, image: image), sourceName: "Preview",
        sourceBundle: "example.preview")

      await model.flush()
      let restored = ClipboardViewModel(
        defaults: defaults, access: CoreClipboard(), storage: store, monitorsSystem: false,
        now: { now }, bootTime: { 1_780_000_000 })
      await restored.restore()
      #expect(restored.entries.count == 3 && restored.entries.contains { $0.pinned })
      model.remove(original.id)
      await model.flush()
      #expect(!model.entries.contains { $0.id == original.id })
      model.clear()
      await model.flush()
      let cleared = await store.load()
      #expect(cleared.isEmpty)
      var many = (0..<210).map {
        ClipboardEntry(
          payload: ClipboardPayload(kind: .text, text: "item \($0)"),
          copiedAt: now.addingTimeInterval(-Double($0)), sourceName: "Fixture",
          sourceBundle: "fixture")
      }
      many[209].pinned = true
      let bounded = ClipboardViewModel.bounded(many, now: now)
      #expect(bounded.count == 200 && bounded.contains { $0.pinned })
      let expired = ClipboardEntry(
        payload: ClipboardPayload(kind: .text, text: "Old"),
        copiedAt: now.addingTimeInterval(-31 * 86400), sourceName: "Fixture",
        sourceBundle: "fixture")
      #expect(ClipboardViewModel.bounded([expired], now: now).isEmpty)
      var pinned = expired
      pinned.pinned = true
      #expect(ClipboardViewModel.bounded([pinned, pinned], now: now).count == 1)
      model.historyLimit = 5
      for index in 0..<9 {
        model.record(
          ClipboardPayload(kind: .text, text: "Limit \(index)"), sourceName: "Fixture",
          sourceBundle: "fixture")
      }
      #expect(model.entries.count == 5)
      model.cleanup = .lidClose
      model.handleCleanupEvent(.shutdown)
      #expect(model.entries.count == 5)
      model.handleCleanupEvent(.lidClose)
      await model.flush()
      #expect(model.entries.isEmpty)
      model.historyLimit = 10
      model.cleanup = .shutdown
      model.record(
        ClipboardPayload(kind: .text, text: "Before restart"), sourceName: "Fixture",
        sourceBundle: "fixture")
      model.togglePin(try #require(model.entries.first).id)
      await model.flush()
      let afterBoot = ClipboardViewModel(
        defaults: defaults, access: CoreClipboard(), storage: store, monitorsSystem: false,
        now: { now }, bootTime: { 1_780_000_100 })
      await afterBoot.restore()
      await afterBoot.flush()
      #expect(afterBoot.entries.isEmpty && afterBoot.historyLimit == 10)
      #expect(
        ClipboardViewModel.bounded([expired], now: now, limit: 5, retentionDays: nil).count == 1)
    }

  }
}
