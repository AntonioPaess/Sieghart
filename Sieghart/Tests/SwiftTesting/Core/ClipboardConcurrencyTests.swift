import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.clipboard, .isolated)) @MainActor
  struct ClipboardConcurrencyTests {
    @Test("G12.03 pause, late disabled read, own copy and safe paste fallback")
    func staleReadAndCopy() async throws {
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

      model.isPaused = true
      let reads = access.reads
      await model.poll(sourceName: "Example", sourceBundle: "example")
      #expect(access.reads == reads)
      model.isPaused = false
      await model.poll(sourceName: "Example", sourceBundle: "example")
      access.count += 1
      access.content = ClipboardPayload(kind: .text, text: "Delayed copy")
      access.delay = true
      let signal = AsyncStream<Void>.makeStream()
      access.readStarted = { signal.continuation.yield(()) }
      let delayed = Task { await model.poll(sourceName: "Editor", sourceBundle: "example.editor") }
      var iterator = signal.stream.makeAsyncIterator()
      _ = await iterator.next()
      model.isEnabled = false
      access.pendingRead?.resume()
      await delayed.value
      signal.continuation.finish()
      #expect(!model.entries.contains { $0.payload.text == "Delayed copy" })
      access.delay = false
      let copied = await model.copy(original)
      #expect(copied && access.writes == 1)
      model.isEnabled = true
      await model.poll(sourceName: "Example", sourceBundle: "example")
      #expect(model.entries.count == 3)
      await model.paste(
        original, dismiss: { Issue.record("Mock paste must never activate an app") })
      #expect(model.status.contains("Copied") && !model.canPaste)
      access.failWrite = true
      let failed = await model.copy(original)
      #expect(!failed && model.status.contains("Could not copy"))
      await model.flush()
    }

  }
}
