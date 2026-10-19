import Foundation

@MainActor final class CoreMiddleClickBackend: MiddleClickBackend {
  var starts = 0, stops = 0
  var callback: (@Sendable () -> Void)?
  var failure = false
  func start(onTap: @escaping @Sendable () -> Void) throws {
    starts += 1
    if failure { throw CocoaError(.featureUnsupported) }
    callback = onTap
  }
  func stop() { stops += 1 }

}

// The real callback may arrive off-main. This queue records its delivery and
// lets each contract explicitly run the main-actor work without wall-clock waits.
final class CoreMiddleDelivery: @unchecked Sendable {
  private let lock = NSLock()
  private var actions: [@MainActor @Sendable () -> Void] = []
  func enqueue(_ action: @escaping @MainActor @Sendable () -> Void) {
    lock.withLock { actions.append(action) }
  }
  var pendingCount: Int { lock.withLock { actions.count } }
  @MainActor func drain() {
    let pending = lock.withLock {
      let pending = actions
      actions = []
      return pending
    }
    for action in pending { action() }
  }
}
