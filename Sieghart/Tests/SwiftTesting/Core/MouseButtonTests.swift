import AppKit
import Testing

extension LogicTests {
    @Suite(.tags(.mouseButtons)) struct MouseButtonRules {
        @Test("G22.01 opt-in, navigation defaults and explicit assignments have predictable precedence")
        func options() {
            var value = MouseButtonOptions()
            #expect(!value.enabled && value.action(for: 3) == .native)
            value.navigation = true
            #expect(value.enabled && value.action(for: 3) == .back && value.action(for: 4) == .forward)
            for button in [0, 1, 2, 8, 31, -1] { #expect(value.action(for: button) == .native) }
            value.bindings[3] = .copy; #expect(value.action(for: 3) == .back)
            value.custom = true; #expect(value.action(for: 3) == .copy)
            value.bindings[3] = .native; #expect(value.action(for: 3) == .native)
            value.bindings[3] = .inherit; #expect(value.action(for: 3) == .back)
            value.navigation = false; #expect(!value.enabled)
            value.bindings[7] = .redo; #expect(value.enabled && value.action(for: 7) == .redo)
        }
        @Test("G22.02 menu matching requires the exact command, modifiers and enabled state", arguments: MouseButtonAction.allCases)
        func menuMatch(_ action: MouseButtonAction) {
            let expected = action.menuKey != nil, modifiers: UInt32 = action == .redo ? 1 : 0
            #expect(action.matchesMenu(key: action.menuKey?.uppercased(), modifiers: modifiers, enabled: true) == expected)
            #expect(!action.matchesMenu(key: action.menuKey, modifiers: modifiers ^ 1, enabled: true))
            #expect(!action.matchesMenu(key: action.menuKey, modifiers: modifiers, enabled: false))
            #expect(!action.matchesMenu(key: nil, modifiers: modifiers, enabled: true))
            #expect(!action.matchesMenu(key: action.menuKey, modifiers: nil, enabled: true))
        }
        @Test("G22.03 navigation cannot invoke indentation commands in an unrelated editor")
        func navigationScope() {
            for bundle in ["com.apple.finder", "com.apple.Safari", "com.google.Chrome"] {
                #expect(MouseButtonAction.back.supports(bundleID: bundle) && MouseButtonAction.forward.supports(bundleID: bundle))
            }
            #expect(!MouseButtonAction.back.supports(bundleID: "com.apple.TextEdit"))
            #expect(MouseButtonAction.copy.supports(bundleID: "com.apple.TextEdit"))
            #expect(!MouseButtonAction.native.supports(bundleID: "com.apple.Safari"))
            #expect(MouseButtonSample(button: 3, phase: .down, modifiers: CGEventFlags.maskCommand.rawValue).hasModifiers)
            #expect(MouseButtonSample(button: 3, phase: .down, modifiers: CGEventFlags.maskSecondaryFn.rawValue).hasModifiers)
            #expect(!MouseButtonSample(button: 3, phase: .down, modifiers: CGEventFlags.maskAlphaShift.rawValue).hasModifiers)
        }
    }
}

@MainActor private final class MouseMonitorFixture: MouseButtonMonitoring {
    var handle: (@MainActor (MouseButtonSample) -> Bool)?
    var interrupted: (@MainActor () -> Void)?
    var attempts: [@MainActor (MouseButtonSample) -> Bool] = []
    var recoveries: [@MainActor () -> Void] = []
    var pressed: Set<Int> = []
    var starts = 0
    var fail = false
    func start(handle: @escaping @MainActor (MouseButtonSample) -> Bool, interrupted: @escaping @MainActor () -> Void) throws {
        starts += 1; attempts.append(handle); recoveries.append(interrupted)
        self.handle = handle; self.interrupted = interrupted
        if fail { throw CocoaError(.featureUnsupported) }
    }
    func stop() { handle = nil; interrupted = nil }
    func isPressed(_ button: Int) -> Bool { pressed.contains(button) }
    func send(_ button: Int, _ phase: MouseButtonPhase, flags: UInt64 = 0) -> Bool {
        if phase == .down { pressed.insert(button) }
        if phase == .up { pressed.remove(button) }
        return handle?(MouseButtonSample(button: button, phase: phase, modifiers: flags)) ?? false
    }
}
@MainActor private final class MouseDispatcherFixture: MouseActionDispatching {
    var prepared: [MouseActionRequest] = []
    var started: [MouseActionRequest] = []
    var delivered: [MouseActionRequest] = []
    var completions = 0
    var blocked = false
    var current = true
    var suspend = false
    var continuation: CheckedContinuation<Void, Never>?
    var outcome: MouseActionResult = .requested
    func prepare(_ action: MouseButtonAction) -> MouseActionPreparation {
        if blocked { return .unavailable("Fixture Secure Input or unsupported app") }
        let request = MouseActionRequest(action: action, pid: 99999, launchedAt: Date(timeIntervalSince1970: 1800000000),
                                         bundleID: "com.apple.Safari", appName: "Fixture", windowID: 456)
        prepared.append(request); return .ready(request)
    }
    func isCurrent(_ request: MouseActionRequest) -> Bool { current }
    func perform(_ request: MouseActionRequest, valid: @escaping @MainActor @Sendable () -> Bool) async -> MouseActionResult {
        started.append(request); defer { completions += 1 }
        if suspend { await withCheckedContinuation { continuation = $0 } }
        guard !Task.isCancelled, valid() else { return .cancelled }
        if outcome == .requested { delivered.append(request) }
        return outcome
    }
    func release() { let continuation = continuation; self.continuation = nil; continuation?.resume() }
}
@MainActor private func mouseEventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

extension MacContractsTests {
    @Suite(.tags(.mouseButtons, .isolated)) @MainActor struct MouseButtonContracts {
        @Test("G22.04 native bridge reads only extra mouse samples without modifying or posting events")
        func eventBridge() throws {
            let event = try #require(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: CGPoint(x: 20, y: 30), mouseButton: .center))
            #expect(NativeMouseButtonMonitor.sample(event, type: .otherMouseDown) == nil)
            event.setIntegerValueField(.mouseEventButtonNumber, value: 3); event.flags = .maskShift
            let sample = try #require(NativeMouseButtonMonitor.sample(event, type: .otherMouseDown))
            #expect(sample.button == 3 && sample.phase == .down && sample.hasModifiers)
            #expect(NativeMouseButtonMonitor.sample(event, type: .leftMouseDown) == nil)
            #expect(event.location == CGPoint(x: 20, y: 30) && event.flags == .maskShift)
            #expect(NativeMouseButtonMonitor.sample(event, type: .otherMouseUp)?.phase == .up)
            #expect(NativeMouseButtonMonitor.sample(event, type: .otherMouseDragged)?.phase == .dragged)
            event.setIntegerValueField(.mouseEventButtonNumber, value: 32)
            #expect(NativeMouseButtonMonitor.sample(event, type: .otherMouseDown) == nil)
        }
        @Test("G22.05 initialization is inert, permission is explicit and settings persist")
        func consent() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture(); var trust = false, requests = 0
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { trust }, requestAccess: { requests += 1 })
            model.start(observeSystem: false); #expect(monitor.starts == 0)
            model.options.custom = true; #expect(monitor.starts == 0)
            model.options.navigation = true; #expect(monitor.starts == 0 && requests == 0)
            model.allowAccess(); #expect(requests == 1 && monitor.starts == 0)
            trust = true; model.configure(); #expect(monitor.starts == 1)
            model.options.bindings[3] = .copy; #expect(monitor.starts == 1)
            let restored = MouseButtonController(defaults: store.value, backend: MouseMonitorFixture(), dispatcher: dispatcher, trusted: { false })
            #expect(restored.options.navigation && restored.options.custom && restored.options.action(for: 3) == .copy)
            model.stop(); #expect(monitor.handle == nil && dispatcher.prepared.isEmpty)
        }
        @Test("G22.06 a captured click consumes its pair and drag, delivers once and preserves basic or modified clicks")
        func clickPair() async throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture()
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { true })
            model.options.navigation = true; model.start(observeSystem: false)
            #expect(monitor.send(3, .down) && monitor.send(3, .down) && monitor.send(3, .dragged) && monitor.send(3, .up))
            #expect(!monitor.send(3, .up))
            #expect(await mouseEventually { dispatcher.completions == 1 })
            #expect(dispatcher.delivered.map(\.action) == [.back])
            for button in [0, 1, 2, 8] { #expect(!monitor.send(button, .down) && !monitor.send(button, .up)) }
            #expect(!monitor.send(4, .down, flags: CGEventFlags.maskCommand.rawValue) && !monitor.send(4, .up))
            #expect(dispatcher.prepared.count == 1)
            model.stop()
        }
        @Test("G22.07 disabling while held drains the existing release and cancels pending actions")
        func disableWhileHeld() async throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture(); dispatcher.suspend = true
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { true })
            model.options.navigation = true; model.start(observeSystem: false)
            #expect(monitor.send(3, .down))
            #expect(await mouseEventually { dispatcher.continuation != nil })
            model.options.navigation = false
            #expect(monitor.handle != nil && !monitor.send(4, .down))
            #expect(monitor.send(3, .up))
            dispatcher.release()
            #expect(await mouseEventually { monitor.handle == nil && dispatcher.completions == 1 })
            #expect(dispatcher.delivered.isEmpty)
            model.stop()
        }
        @Test("G22.08 failed starts, interruption and callbacks from an older tap cannot restart or consume")
        func recovery() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture(); monitor.fail = true
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { true })
            model.options.navigation = true; model.start(observeSystem: false)
            let old = try #require(monitor.attempts.first), recovery = try #require(monitor.recoveries.first)
            #expect(monitor.handle == nil && !old(.init(button: 3, phase: .down)))
            monitor.fail = false; model.configure(); recovery(); #expect(monitor.starts == 2)
            let newer = try #require(monitor.interrupted); newer(); newer(); #expect(monitor.starts == 3)
            model.stop(); #expect(!old(.init(button: 3, phase: .down)) && dispatcher.prepared.isEmpty)
        }
        @Test("G22.09 screen lock, sleep and session are independent; disabled wake remains off")
        func lifecycle() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture()
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { true })
            model.options.navigation = true; model.start(observeSystem: false)
            model.setLocked(true); model.setSessionActive(false); model.setSessionActive(true); #expect(monitor.handle == nil)
            model.setSleeping(true); model.setLocked(false); #expect(monitor.handle == nil)
            model.setSleeping(false); #expect(monitor.handle != nil)
            model.options.navigation = false; let count = monitor.starts
            model.setSleeping(true); model.setSleeping(false); #expect(monitor.starts == count && monitor.handle == nil)
            model.stop()
        }
        @Test("G22.10 app or window changes cancel an action before the dispatcher applies it")
        func targetChange() async throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture(); dispatcher.suspend = true
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { true })
            model.options.navigation = true; model.start(observeSystem: false)
            #expect(monitor.send(3, .down) && monitor.send(3, .up))
            #expect(await mouseEventually { dispatcher.continuation != nil })
            dispatcher.current = false; dispatcher.release()
            #expect(await mouseEventually { dispatcher.completions == 1 })
            #expect(dispatcher.delivered.isEmpty && model.status.contains("cancelled"))
            model.stop()
        }
        @Test("G22.11 queued clicks run in order; overflow is bounded and cancellation drops the queue")
        func queue() async throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture(); dispatcher.suspend = true
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { true })
            model.options.navigation = true; model.start(observeSystem: false)
            #expect(monitor.send(3, .down) && monitor.send(3, .up))
            #expect(await mouseEventually { dispatcher.continuation != nil })
            #expect(monitor.send(4, .down) && monitor.send(4, .up))
            #expect(monitor.send(3, .down) && monitor.send(3, .up))
            dispatcher.release(); #expect(await mouseEventually { dispatcher.started.count == 2 && dispatcher.continuation != nil })
            dispatcher.release(); #expect(await mouseEventually { dispatcher.started.count == 3 && dispatcher.continuation != nil })
            #expect(dispatcher.started.map(\.action) == [.back, .forward, .back])
            for _ in 0..<12 { #expect(monitor.send(3, .down) && monitor.send(3, .up)) }
            #expect(dispatcher.started.count == 3 && model.status.contains("busy"))
            dispatcher.suspend = false; dispatcher.release()
            #expect(await mouseEventually { dispatcher.completions >= 11 })
            #expect(dispatcher.started.count == 11 && dispatcher.delivered.count == 11, "Only eight waiting requests may follow the current request")
            dispatcher.suspend = true
            #expect(monitor.send(4, .down) && monitor.send(4, .up))
            #expect(await mouseEventually { dispatcher.continuation != nil })
            #expect(monitor.send(3, .down) && monitor.send(3, .up))
            model.cancelPendingActions(); dispatcher.release()
            #expect(await mouseEventually { dispatcher.completions == 12 })
            #expect(dispatcher.started.count == 12 && dispatcher.delivered.count == 11)
            model.stop()
        }
        @Test("G22.12 unsupported targets preserve the native click; disabled commands report failure")
        func unsupported() async throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture(); dispatcher.blocked = true
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { true })
            model.options.navigation = true; model.start(observeSystem: false)
            #expect(!monitor.send(3, .down) && !monitor.send(3, .up) && model.status.contains("unsupported"))
            dispatcher.blocked = false; dispatcher.outcome = .unavailable
            #expect(monitor.send(3, .down) && monitor.send(3, .up))
            #expect(await mouseEventually { dispatcher.completions == 1 })
            #expect(dispatcher.delivered.isEmpty && model.status.contains("unavailable"))
            model.stop()
        }
        @Test("G22.13 revocation tears down the tap and prevents already prepared work")
        func revoked() async throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture(); dispatcher.suspend = true; var trust = true
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { trust })
            model.options.navigation = true; model.start(observeSystem: false)
            #expect(monitor.send(3, .down)); #expect(await mouseEventually { dispatcher.continuation != nil })
            let old = try #require(monitor.handle)
            trust = false; model.checkHealth(); dispatcher.release()
            #expect(await mouseEventually { dispatcher.completions == 1 })
            #expect(monitor.handle == nil && dispatcher.delivered.isEmpty && !old(.init(button: 3, phase: .up)))
            model.stop()
        }
        @Test("G22.14 a missed release cannot retain a drain-only tap after the button is physically released")
        func missedRelease() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let monitor = MouseMonitorFixture(), dispatcher = MouseDispatcherFixture()
            let model = MouseButtonController(defaults: store.value, backend: monitor, dispatcher: dispatcher, trusted: { true })
            model.options.navigation = true; model.start(observeSystem: false)
            #expect(monitor.send(3, .down)); model.options.navigation = false
            #expect(monitor.handle != nil)
            monitor.pressed = []; model.checkHealth(); #expect(monitor.handle == nil)
            model.stop()
        }
    }
}
