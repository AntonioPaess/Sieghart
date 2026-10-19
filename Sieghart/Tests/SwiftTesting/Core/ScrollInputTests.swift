import AppKit
import Foundation
import Testing

extension LogicTests {
    @Suite(.tags(.input)) struct ScrollTransformTests {
        @Test("G19.01 reverse every axis and retain sub-line fixed precision", arguments: [Int64(-7), 0, 9])
        func inversion(_ sign: Int64) {
            let input = ScrollSample(lines: .init(x: sign, y: -sign), points: .init(x: sign * 13, y: sign * 4), fixed: .init(x: sign * 65536 + 1, y: sign * 32768), flags: CGEventFlags.maskCommand.rawValue)
            let output = ScrollTransform.apply(input, options: .init(inverted: true))
            #expect(output.lines == ScrollVector(x: -sign, y: sign))
            #expect(output.points.x == -input.points.x && output.points.y == -input.points.y)
            #expect(output.fixed.x == -input.fixed.x && output.fixed.y == -input.fixed.y)
            #expect(output.flags == input.flags)
        }
        @Test("G19.02 continuous samples require explicit inclusion")
        func continuous() {
            let input = ScrollSample(points: .init(y: 17), continuous: true)
            #expect(ScrollTransform.apply(input, options: .init(inverted: true)) == input)
            #expect(ScrollTransform.apply(input, options: .init(inverted: true, affectsContinuous: true)).points.y == -17)
        }
        @Test("G19.03 combine horizontal and inverse once, preserving unrelated flags", arguments: ScrollModifier.allCases)
        func combined(_ modifier: ScrollModifier) {
            let input = ScrollSample(lines: .init(x: 2, y: 5), points: .init(x: 20, y: 50), fixed: .init(x: 1, y: 32769), flags: modifier.flags | CGEventFlags.maskCommand.rawValue)
            let options = ScrollOptions(inverted: true, horizontal: true, modifier: modifier)
            let output = ScrollTransform.apply(input, options: options)
            #expect(output.lines == ScrollVector(x: -7, y: 0))
            #expect(output.points == ScrollVector(x: -70, y: 0))
            #expect(output.fixed == ScrollVector(x: -32770, y: 0))
            #expect(output.flags == CGEventFlags.maskCommand.rawValue)
            #expect(ScrollTransform.apply(output, options: .init(horizontal: true, modifier: modifier)) == output)
            var noModifier = input; noModifier.flags = 0
            #expect(ScrollTransform.apply(noModifier, options: .init(horizontal: true, modifier: modifier)) == noModifier)
        }
        @Test("G19.04 malformed or overflowing vectors leave entire sample unchanged")
        func overflow() {
            for vector in [ScrollVector(x: .min, y: 1), ScrollVector(x: .max, y: 1)] {
                let input = ScrollSample(lines: vector, points: .init(y: 23), flags: ScrollModifier.shift.flags)
                #expect(ScrollTransform.apply(input, options: .init(inverted: true, horizontal: true)) == input)
                #expect(ScrollTransform.apply(input, options: .init(horizontal: true)) == input)
            }
            let input = ScrollSample(points: .init(x: 3, y: 0), flags: ScrollModifier.shift.flags)
            #expect(ScrollTransform.apply(input, options: .init(horizontal: true)) == input)
            #expect(ScrollTransform.apply(input, options: .init()) == input)
        }
        @Test("G19.05 reject modifier-only overlap but allow key chords", arguments: ScrollModifier.allCases)
        func conflict(_ modifier: ScrollModifier) {
            let chord = ShortcutChord(keyCode: nil, modifiers: UInt(modifier.flags | CGEventFlags.maskCommand.rawValue), keyLabel: "")
            #expect(modifier.conflicts(with: [chord]))
            var keyed = chord; keyed.keyCode = 3
            #expect(!modifier.conflicts(with: [keyed]))
        }
    }
}

@MainActor private final class ScrollBackendFixture: ScrollInputBackend {
    var attempts: [@MainActor (ScrollSample) -> ScrollSample] = []
    var starts = 0
    var stops = 0
    var fail = false
    var transform: (@MainActor (ScrollSample) -> ScrollSample)?
    var interrupted: (@MainActor () -> Void)?
    func start(transform: @escaping @MainActor (ScrollSample) -> ScrollSample, interrupted: @escaping @MainActor () -> Void) throws {
        starts += 1; attempts.append(transform); self.transform = transform; self.interrupted = interrupted
        if fail { throw CocoaError(.featureUnsupported) }
    }
    func stop() { stops += 1; transform = nil; interrupted = nil }
}
extension MacContractsTests {
    @Suite(.tags(.input, .isolated)) @MainActor struct ScrollLifecycleTests {
        @Test("G19.12 ignored continuous input explains trackpad inclusion and enabling it applies the transform")
        func trackpadHint() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = ScrollBackendFixture()
            let model = ScrollInputController(defaults: store.value, backend: backend, trusted: { true })
            model.options.inverted = true; model.start(observeSystem: false)
            let continuous = ScrollSample(points: .init(y: 20), continuous: true)
            #expect(backend.transform?(continuous) == continuous)
            #expect(model.inputHint?.contains("trackpad") == true)
            model.options.affectsContinuous = true
            let transformed = backend.transform?(continuous)
            #expect(model.inputHint == nil && transformed?.points.y == -20)
            model.options.affectsContinuous = false
            _ = backend.transform?(continuous)
            let wheel = ScrollSample(lines: .init(y: 2))
            let wheelOutput = backend.transform?(wheel)
            #expect(wheelOutput?.lines.y == -2 && model.inputHint == nil)
            model.stop(); #expect(model.inputHint == nil)
        }
        @Test("G19.13 explicit permission action opens settings even without a new system prompt")
        func permissionRecovery() {
            var prompts = 0, urls: [URL] = []
            #expect(AccessibilityAccess.request(trusted: { false }, prompt: { prompts += 1 }, open: { urls.append($0); return true }))
            #expect(prompts == 1 && urls == [AccessibilityAccess.settingsURL])
            #expect(AccessibilityAccess.request(trusted: { true }, prompt: { prompts += 1 }, open: { urls.append($0); return true }))
            #expect(prompts == 1 && urls.count == 2)
            #expect(!AccessibilityAccess.request(trusted: { false }, prompt: { prompts += 1 }, open: { _ in false }))
            #expect(prompts == 2)
        }
        @Test("G19.11 native event bridge preserves phase, momentum and fixed-point precision without installing a tap")
        func nativeFields() throws {
            let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 8, wheel2: 3, wheel3: 0))
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
            event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 32769)
            event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 1)
            event.flags = [.maskShift, .maskCommand]
            event.timestamp = 12345678
            event.location = CGPoint(x: 42, y: 51)
            NativeScrollInputBackend.apply(to: event) {
                ScrollTransform.apply($0, options: .init(inverted: true, horizontal: true, affectsContinuous: true))
            }
            #expect(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2) == -32770)
            #expect(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1) == 0)
            #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == -32770.0 / 65536.0)
            #expect(event.getIntegerValueField(.scrollWheelEventScrollPhase) == 2)
            #expect(event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 1)
            #expect(event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
            #expect(event.timestamp == 12345678 && event.location == CGPoint(x: 42, y: 51))
            #expect(event.flags == .maskCommand)
        }
        @Test("G19.06 opt-in, persistence, explicit permission request and stop")
        func consent() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = ScrollBackendFixture(); var trust = false; var requests = 0
            let model = ScrollInputController(defaults: store.value, backend: backend, trusted: { trust }, requestAccess: { requests += 1 })
            model.start(observeSystem: false)
            #expect(backend.starts == 0 && !model.options.enabled)
            model.options.inverted = true
            #expect(backend.starts == 0 && requests == 0)
            model.allowAccess(); #expect(requests == 1 && backend.starts == 0)
            trust = true; model.configure(); #expect(backend.starts == 1)
            let restored = ScrollInputController(defaults: store.value, backend: ScrollBackendFixture(), trusted: { false })
            #expect(restored.options.inverted && !restored.options.horizontal)
            model.stop(); model.configure(); #expect(backend.starts == 1 && backend.transform == nil)
        }
        @Test("G19.07 sleep, lock and session independently gate wake; disabled wake stays off")
        func suspension() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = ScrollBackendFixture()
            let model = ScrollInputController(defaults: store.value, backend: backend, trusted: { true })
            model.options.horizontal = true; model.start(observeSystem: false)
            model.setSleeping(true); model.setLocked(true); model.setSleeping(false)
            #expect(backend.starts == 1 && backend.transform == nil)
            model.setLocked(false); #expect(backend.starts == 2)
            model.setLocked(true); model.setSessionActive(false); model.setSessionActive(true)
            #expect(backend.transform == nil, "Session activation cannot undo a screen lock")
            model.setSessionActive(false); model.setLocked(false)
            #expect(backend.transform == nil, "Unlock cannot undo an inactive session")
            model.setSessionActive(true)
            #expect(backend.transform != nil)
            let startsBeforeDisable = backend.starts
            model.options.horizontal = false; model.setSleeping(true); model.setSleeping(false)
            #expect(backend.starts == startsBeforeDisable && backend.transform == nil); model.stop()
        }
        @Test("G19.08 revoked permission and obsolete callbacks cannot alter input or restart")
        func stale() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = ScrollBackendFixture(); var trust = true
            let model = ScrollInputController(defaults: store.value, backend: backend, trusted: { trust })
            model.options.inverted = true; model.start(observeSystem: false)
            let transform = try #require(backend.transform); let recover = try #require(backend.interrupted)
            let input = ScrollSample(points: .init(y: 16))
            trust = false; #expect(transform(input) == input && backend.transform == nil)
            trust = true; recover(); #expect(backend.starts == 1)
            model.configure(); let newer = try #require(backend.interrupted)
            recover(); #expect(backend.starts == 2)
            newer(); #expect(backend.starts == 3)
            model.stop(); newer(); #expect(backend.starts == 3 && transform(input) == input)
        }
        @Test("G19.09 failed start cleans up and retry uses one backend")
        func failedStart() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = ScrollBackendFixture(); backend.fail = true
            let model = ScrollInputController(defaults: store.value, backend: backend, trusted: { true })
            model.options.inverted = true; model.start(observeSystem: false)
            #expect(backend.transform == nil && model.status.contains("unavailable"))
            let input = ScrollSample(points: .init(y: 9))
            let failedCallback = try #require(backend.attempts.first)
            #expect(failedCallback(input) == input)
            backend.fail = false; model.configure(); #expect(backend.starts == 2 && backend.transform != nil)
            model.start(observeSystem: false); #expect(backend.starts == 2); model.stop()
        }
        @Test("G19.10 runtime shortcut changes fail closed before consuming scroll")
        func lateConflict() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = ScrollBackendFixture(); var chords: [ShortcutChord] = []
            let model = ScrollInputController(defaults: store.value, backend: backend, trusted: { true })
            model.shortcutChords = { chords }; model.options.horizontal = true; model.start(observeSystem: false)
            let transform = try #require(backend.transform)
            chords = [ShortcutChord(keyCode: nil, modifiers: UInt(ScrollModifier.shift.flags), keyLabel: "")]
            let input = ScrollSample(lines: .init(y: 1), flags: ScrollModifier.shift.flags)
            #expect(transform(input) == input && model.hasConflict && backend.transform == nil)
            #expect(model.status.contains("conflicts"))
            chords = []; model.configure(); #expect(backend.starts == 2); model.stop()
        }
    }
}
