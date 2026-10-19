import AppKit
import Foundation
import Testing

extension LogicTests {
    @Suite(.tags(.input)) struct InputGuardsRuleTests {
        @Test("G24.01 click debounce suppresses rapid same-spot switch bounce and pairs its release without swallowing valid clicks")
        func clickDebounce() {
            var state = ClickDebounceState()
            let origin = CGPoint(x: 100, y: 100)
            let c1 = state.shouldSuppress(.init(button: 0, phase: .down, location: origin, timestampNs: 1_000_000_000), enabled: true, windowMs: 35)
            let c2 = state.shouldSuppress(.init(button: 0, phase: .up, location: origin, timestampNs: 1_020_000_000), enabled: true, windowMs: 35)
            #expect(!c1 && !c2)
            // Switch bounce 15 ms after release at same point -> suppressed along with drag and release
            let b1 = state.shouldSuppress(.init(button: 0, phase: .down, location: CGPoint(x: 101, y: 100), timestampNs: 1_035_000_000), enabled: true, windowMs: 35)
            let b2 = state.shouldSuppress(.init(button: 0, phase: .dragged, location: CGPoint(x: 101, y: 100), timestampNs: 1_040_000_000), enabled: true, windowMs: 35)
            let b3 = state.shouldSuppress(.init(button: 0, phase: .up, location: CGPoint(x: 101, y: 100), timestampNs: 1_045_000_000), enabled: true, windowMs: 35)
            #expect(b1 && b2 && b3)
            // Click after window (60 ms later) passes through
            let c3 = state.shouldSuppress(.init(button: 0, phase: .down, location: origin, timestampNs: 1_100_000_000), enabled: true, windowMs: 35)
            let c4 = state.shouldSuppress(.init(button: 0, phase: .up, location: origin, timestampNs: 1_110_000_000), enabled: true, windowMs: 35)
            #expect(!c3 && !c4)
            // Fast click far away (> 2 pt) is not treated as stationary switch chatter
            let f1 = state.shouldSuppress(.init(button: 0, phase: .down, location: CGPoint(x: 120, y: 100), timestampNs: 1_120_000_000), enabled: true, windowMs: 35)
            let f2 = state.shouldSuppress(.init(button: 0, phase: .up, location: CGPoint(x: 120, y: 100), timestampNs: 1_130_000_000), enabled: true, windowMs: 35)
            #expect(!f1 && !f2)
        }

        @Test("G24.02 keyboard debounce suppresses mechanical chatter and paired keyUp while preserving OS autorepeat and modifiers")
        func keyDebounce() {
            var state = KeyDebounceState()
            let k1 = state.shouldSuppress(.init(keyCode: 0, phase: .down, timestampNs: 1_000_000_000), enabled: true, windowMs: 30)
            let k2 = state.shouldSuppress(.init(keyCode: 0, phase: .up, timestampNs: 1_010_000_000), enabled: true, windowMs: 30)
            #expect(!k1 && !k2)
            // Chatter 12 ms later
            let ch1 = state.shouldSuppress(.init(keyCode: 0, phase: .down, timestampNs: 1_022_000_000), enabled: true, windowMs: 30)
            let ch2 = state.shouldSuppress(.init(keyCode: 0, phase: .up, timestampNs: 1_028_000_000), enabled: true, windowMs: 30)
            #expect(ch1 && ch2)
            // OS autorepeat is never suppressed even within threshold
            let rep = state.shouldSuppress(.init(keyCode: 0, phase: .down, isRepeat: true, timestampNs: 1_020_000_000), enabled: true, windowMs: 30)
            #expect(!rep)
            // Modifier keys are never debounced
            let m1 = state.shouldSuppress(.init(keyCode: 55, phase: .down, timestampNs: 1_020_000_000), enabled: true, windowMs: 30)
            let m2 = state.shouldSuppress(.init(keyCode: 55, phase: .down, timestampNs: 1_021_000_000), enabled: true, windowMs: 30)
            #expect(!m1 && !m2)
        }

        @Test("G24.03 superKey consumes trigger press and injects Hyper flags on modified keys", arguments: SuperKeyTrigger.allCases)
        func superKey(_ trigger: SuperKeyTrigger) {
            var state = SuperKeyState()
            let down = state.process(.init(keyCode: trigger.keyCode, phase: .down), enabled: true, trigger: trigger)
            #expect(down.consume && state.isHeld)
            let letter = state.process(.init(keyCode: 4, phase: .down, flags: 0), enabled: true, trigger: trigger)
            #expect(!letter.consume && letter.flags == SuperKeyState.hyperFlags)
            let up = state.process(.init(keyCode: trigger.keyCode, phase: .up), enabled: true, trigger: trigger)
            #expect(up.consume && !state.isHeld)
            let afterRelease = state.process(.init(keyCode: 4, phase: .down, flags: 0), enabled: true, trigger: trigger)
            #expect(afterRelease.flags == 0)
            let conflictChord = ShortcutChord(keyCode: UInt32(trigger.keyCode), modifiers: 0, keyLabel: trigger.title)
            #expect(trigger.conflicts(with: [conflictChord]))
        }

        @Test("G24.04 quit and close protection intercepts first press and allows second press within confirmation window for same app")
        func quitProtection() {
            var state = QuitProtectionState()
            let cmd = CGEventFlags.maskCommand.rawValue
            let first = state.evaluate(.init(keyCode: 12, phase: .down, flags: cmd, timestampNs: 1_000_000_000, frontmostPID: 42, frontmostAppName: "Safari"), enabled: true, protectClose: true)
            #expect(first.intercepted && first.hint?.contains("Safari") == true)
            // Autorepeat while still holding first press is intercepted without confirming
            let repeatHold = state.evaluate(.init(keyCode: 12, phase: .down, isRepeat: true, flags: cmd, timestampNs: 1_300_000_000, frontmostPID: 42, frontmostAppName: "Safari"), enabled: true, protectClose: true)
            #expect(repeatHold.intercepted)
            // Different app PID resets and requires its own confirmation
            let otherApp = state.evaluate(.init(keyCode: 12, phase: .down, flags: cmd, timestampNs: 1_400_000_000, frontmostPID: 99, frontmostAppName: "Notes"), enabled: true, protectClose: true)
            #expect(otherApp.intercepted && otherApp.hint?.contains("Notes") == true)
            // Second press in Notes within 1.5s confirms and passes through
            let confirmNotes = state.evaluate(.init(keyCode: 12, phase: .down, flags: cmd, timestampNs: 1_800_000_000, frontmostPID: 99, frontmostAppName: "Notes"), enabled: true, protectClose: true)
            #expect(!confirmNotes.intercepted && confirmNotes.hint?.contains("Confirmed") == true)
            // Close window (Cmd+W, keyCode 13) respects protectClose flag
            let unguardedW = state.evaluate(.init(keyCode: 13, phase: .down, flags: cmd, timestampNs: 2_000_000_000, frontmostPID: 99, frontmostAppName: "Notes"), enabled: true, protectClose: false)
            #expect(!unguardedW.intercepted)
            let guardedW = state.evaluate(.init(keyCode: 13, phase: .down, flags: cmd, timestampNs: 2_100_000_000, frontmostPID: 99, frontmostAppName: "Notes"), enabled: true, protectClose: true)
            #expect(guardedW.intercepted)
        }

        @Test("G24.05 snippet validation rejects recursive or duplicate triggers and matcher handles backspace and reset keys")
        func snippetMatching() {
            let existing = [TextSnippet(trigger: ";mail", replacement: "antonio@example.com")]
            #expect(TextSnippet.validate(trigger: ";m", replacement: "contains ;m inside", existing: existing) != nil)
            #expect(TextSnippet.validate(trigger: ";MAIL", replacement: "other@example.com", existing: existing) != nil)
            #expect(TextSnippet.validate(trigger: "; a", replacement: "valid", existing: existing) != nil)
            #expect(TextSnippet.validate(trigger: ";ok", replacement: "Great!", existing: existing) == nil)

            var matcher = SnippetMatcher()
            let snippets = [TextSnippet(trigger: ";sig", replacement: "Sieghart Companion")]
            let s1 = matcher.feed(.init(keyCode: 41, phase: .down, characters: ";", frontmostPID: 77), enabled: true, snippets: snippets)
            let s2 = matcher.feed(.init(keyCode: 1, phase: .down, characters: "s", frontmostPID: 77), enabled: true, snippets: snippets)
            let s3 = matcher.feed(.init(keyCode: 3, phase: .down, characters: "x", frontmostPID: 77), enabled: true, snippets: snippets)
            // Backspace removes 'x'
            let s4 = matcher.feed(.init(keyCode: 51, phase: .down, characters: "", frontmostPID: 77), enabled: true, snippets: snippets)
            let s5 = matcher.feed(.init(keyCode: 34, phase: .down, characters: "i", frontmostPID: 77), enabled: true, snippets: snippets)
            #expect(s1 == nil && s2 == nil && s3 == nil && s4 == nil && s5 == nil)
            let match = matcher.feed(.init(keyCode: 5, phase: .down, characters: "g", frontmostPID: 77), enabled: true, snippets: snippets)
            #expect(match == SnippetExpansionRequest(trigger: ";sig", replacement: "Sieghart Companion", pid: 77))
            #expect(matcher.buffer.isEmpty)
        }
    }
}

@MainActor private final class InputGuardsBackendFixture: InputGuardsBackend {
    var starts = 0
    var stops = 0
    var fail = false
    var onMouse: (@MainActor (ClickDebounceSample) -> Bool)?
    var onKey: (@MainActor (KeyGuardSample) -> KeyGuardDecision)?
    var interrupted: (@MainActor () -> Void)?
    func start(onMouse: @escaping @MainActor (ClickDebounceSample) -> Bool,
               onKey: @escaping @MainActor (KeyGuardSample) -> KeyGuardDecision,
               interrupted: @escaping @MainActor () -> Void) throws {
        starts += 1; self.onMouse = onMouse; self.onKey = onKey; self.interrupted = interrupted
        if fail { throw CocoaError(.featureUnsupported) }
    }
    func stop() { stops += 1; onMouse = nil; onKey = nil; interrupted = nil }
}

@MainActor private final class SnippetExpanderFixture: SnippetExpanding {
    var expanded: [SnippetExpansionRequest] = []
    func expand(_ request: SnippetExpansionRequest) -> Bool {
        expanded.append(request); return true
    }
}

extension MacContractsTests {
    @Suite(.tags(.input, .isolated)) @MainActor struct InputGuardsContracts {
        @Test("G24.06 controller lifecycle, persistence, secure input pause, conflict gate and snippet expansion")
        func lifecycleAndExpansion() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let backend = InputGuardsBackendFixture()
            let expander = SnippetExpanderFixture()
            var trust = true
            var secure = false
            var chords: [ShortcutChord] = []
            let model = InputGuardsController(defaults: store.value, backend: backend, expander: expander,
                                              trusted: { trust }, secureInput: { secure })
            model.shortcutChords = { chords }
            model.start(observeSystem: false)
            #expect(backend.starts == 0 && !model.options.enabled)

            let added = model.addSnippet(trigger: ";hi", replacement: "Hello there")
            #expect(added)
            model.options.snippetsEnabled = true
            model.options.quitProtectionEnabled = true
            model.options.superKeyEnabled = true
            #expect(backend.starts == 1)

            // Super key conflict stops backend
            chords = [ShortcutChord(keyCode: UInt32(SuperKeyTrigger.f18.keyCode), modifiers: 0, keyLabel: "F18")]
            model.configure()
            #expect(model.hasSuperKeyConflict && backend.onKey == nil)
            chords = []
            model.configure()
            let keyHandler = try #require(backend.onKey)

            // Snippet expansion end-to-end
            _ = keyHandler(.init(keyCode: 41, phase: .down, characters: ";", frontmostPID: 55))
            _ = keyHandler(.init(keyCode: 4, phase: .down, characters: "h", frontmostPID: 55))
            _ = keyHandler(.init(keyCode: 34, phase: .down, characters: "i", frontmostPID: 55))
            #expect(expander.expanded == [SnippetExpansionRequest(trigger: ";hi", replacement: "Hello there", pid: 55)])

            // Secure input pauses keyboard processing and clears transient state
            secure = true
            let held = keyHandler(.init(keyCode: SuperKeyTrigger.f18.keyCode, phase: .down))
            #expect(!held.consume && model.status.contains("Secure Input"))
            secure = false

            // Persistence round-trip
            let restored = InputGuardsController(defaults: store.value, backend: InputGuardsBackendFixture(), expander: SnippetExpanderFixture(), trusted: { false })
            #expect(restored.options.snippets.count == 1 && restored.options.snippetsEnabled && restored.options.quitProtectionEnabled)

            model.setSleeping(true)
            #expect(backend.onKey == nil)
            model.setSleeping(false)
            #expect(backend.onKey != nil)
            model.stop()
            #expect(backend.onKey == nil)
        }
    }
}
