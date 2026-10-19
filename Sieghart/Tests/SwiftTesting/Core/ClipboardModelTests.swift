import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.clipboard, .isolated)) @MainActor
  struct ClipboardModelTests {
    @Test("G12.01 disabled baseline, capture, stable pin identity and case-insensitive search")
    func baselineAndDedup() async throws {
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
      #expect(access.reads == 0 && model.entries.isEmpty)
      model.isEnabled = true
      access.content = ClipboardPayload(kind: .text, text: "Copied while disabled")
      await model.poll(sourceName: "Example", sourceBundle: "example")
      #expect(model.entries.isEmpty)  // enabling only establishes a baseline
      access.count += 1
      access.content = ClipboardPayload(kind: .text, text: "A useful first copy")
      await model.poll(sourceName: "Editor", sourceBundle: "example.editor")
      #expect(model.entries.count == 1)
      let original = try #require(model.entries.first)
      model.togglePin(original.id)
      access.count += 1
      await model.poll(sourceName: "Browser", sourceBundle: "example.browser")
      #expect(
        model.entries.count == 1 && model.entries[0].id == original.id && model.entries[0].pinned)
      #expect(model.filtered(query: "USEFUL", pinnedOnly: true).count == 1)
      await model.flush()
    }

    @Test("G12.02 text, image and files retain source exclusions and media opt-out")
    func payloadCapture() async throws {
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
      #expect(
        model.entries.count == 3 && model.filtered(query: "example.pdf", kind: .files).count == 1)
      #expect(model.filtered(query: "", kind: .image).count == 1)
      model.record(
        ClipboardPayload(kind: .text, text: "Marked source test"), sourceName: "Passwords",
        sourceBundle: "com.apple.Passwords")
      #expect(model.entries.count == 3)
      model.includeMedia = false
      model.record(
        ClipboardPayload(kind: .image, image: image), sourceName: "Preview",
        sourceBundle: "example.preview")
      #expect(model.entries.count == 3)
      await model.flush()
    }

  }
}
