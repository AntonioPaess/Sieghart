import AppKit
import Foundation

@MainActor final class CoreClipboard: ClipboardAccess {
  var count = 10
  var content: ClipboardPayload?
  var reads = 0
  var writes = 0
  var delay = false
  var failWrite = false
  var readStarted: (() -> Void)?
  var pendingRead: CheckedContinuation<Void, Never>?
  func read(after previous: Int?, includeMedia: Bool) async -> ClipboardRead? {
    reads += 1
    let snapshot = ClipboardRead(changeCount: count, payload: previous == count ? nil : content)
    if delay {
      await withCheckedContinuation {
        pendingRead = $0
        readStarted?()
      }
    }
    return snapshot
  }
  func write(_ payload: ClipboardPayload) async -> Int? {
    guard !failWrite else { return nil }
    count += 1
    writes += 1
    content = payload
    return count
  }
}
actor CoreClipboardStorage: ClipboardStorage {
  var entries: [ClipboardEntry] = []
  func load() -> [ClipboardEntry] { entries }
  func save(_ entries: [ClipboardEntry], revision: UInt64) { self.entries = entries }
}
