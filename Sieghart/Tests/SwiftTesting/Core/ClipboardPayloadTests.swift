import AppKit
import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.clipboard, .logic))
  struct ClipboardPayloadTests {
    @Test("G12.02 remote file URLs, oversized text and malformed image are invalid")
    func invalidPayloads() throws {
      #expect(
        !ClipboardPayload(kind: .files, files: [try #require(URL(string: "https://example.com"))])
          .valid)
      #expect(!ClipboardPayload(kind: .text, text: String(repeating: "x", count: 524289)).valid)
      #expect(!ClipboardPayload(kind: .image, image: Data([0, 1, 2])).valid)
    }

  }
}
