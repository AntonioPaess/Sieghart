import Foundation

@MainActor final class FakeMiddleClickBackend: MiddleClickBackend {
    var starts = 0, stops = 0
    var callback: (@Sendable () -> Void)?
    var failure = false
    func start(onTap: @escaping @Sendable () -> Void) throws { starts += 1; if failure { throw CocoaError(.featureUnsupported) }; callback = onTap }
    func stop() { stops += 1 }
}
@main struct MiddleClickChecks {
    @MainActor static func main() async throws {
        let contacts = (0..<3).map { TrackpadContact(id: Int32($0), x: 0.2 + Double($0) * 0.15, y: 0.5) }
        var tap = ThreeFingerTap()
        precondition(!tap.consume(contacts, at: 0)); precondition(tap.consume([], at: 0.12))
        precondition(!tap.consume(contacts, at: 0.2)); precondition(!tap.consume([], at: 0.25)) // debounce
        precondition(!tap.consume(Array(contacts.prefix(2)), at: 1)); precondition(!tap.consume([], at: 1.1))
        precondition(!tap.consume(contacts, at: 2)); precondition(!tap.consume([], at: 2.4))
        precondition(!tap.consume(contacts, at: 3)); precondition(!tap.consume(contacts.map { TrackpadContact(id: $0.id, x: $0.x + 0.1, y: $0.y) }, at: 3.1)); precondition(!tap.consume([], at: 3.2))
        precondition(!tap.consume(contacts + [TrackpadContact(id: 9, x: 0.8, y: 0.5)], at: 4)); precondition(!tap.consume([], at: 4.1))
        precondition(!tap.consume(Array(contacts.prefix(1)), at: 5)); precondition(!tap.consume(contacts, at: 5.06)); precondition(!tap.consume(Array(contacts.prefix(2)), at: 5.08)); precondition(tap.consume([], at: 5.15))
        let suite = "Sieghart.MiddleClickChecks.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeMiddleClickBackend(); var trusted = false, emitted = 0, asked = 0
        let model = MiddleClickController(defaults: defaults, backend: backend, trusted: { trusted }, requestAccess: { asked += 1 }, emit: { emitted += 1 })
        model.start(observeSystem: false); precondition(!model.isEnabled && backend.starts == 0)
        model.isEnabled = true; precondition(backend.starts == 0 && model.status.contains("Accessibility"))
        model.allowAccess(); precondition(asked == 1 && emitted == 0)
        trusted = true; model.configure(); precondition(backend.starts == 1)
        backend.callback?(); try await Task.sleep(for: .milliseconds(10)); precondition(emitted == 1)
        let old = backend.callback; model.isEnabled = false; old?(); try await Task.sleep(for: .milliseconds(10)); precondition(emitted == 1)
        backend.failure = true; model.isEnabled = true; precondition(!model.status.contains("ready"))
        print("Middle-click checks passed: exact three-finger taps, drag/long/four-finger rejection, debounce, explicit opt-in/access, callback teardown and unavailable support. No device or input events used.")
    }
}
