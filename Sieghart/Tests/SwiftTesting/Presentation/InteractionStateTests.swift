import AppKit
import Foundation
import SwiftUI
import Testing

extension MacContractsTests {
    @MainActor @Suite(.tags(.isolated, .interactions)) struct PreferenceTests {
        @Test("G04.04 · Appearance and window/island glass persist independently") func appearance() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let prefs = CompanionPreferences(defaults: store.value)
            #expect(prefs.appearance == .system && !prefs.windowGlass && !prefs.islandGlass)
            for theme in AppAppearance.allCases {
                prefs.appearance = theme
                #expect(CompanionPreferences(defaults: store.value).appearance == theme)
            }
            prefs.windowGlass = true
            #expect(CompanionPreferences(defaults: store.value).windowGlass && !CompanionPreferences(defaults: store.value).islandGlass)
            prefs.windowGlass = false; prefs.islandGlass = true
            #expect(!CompanionPreferences(defaults: store.value).windowGlass && CompanionPreferences(defaults: store.value).islandGlass)
        }
        @Test("G04.04 · Retired avatars migrate to Sig", arguments: ["crt-buddy", "arcade-1984", "minimal-spirit", "coast-buddy", "paper-pal", "ink-buddy", "soft-orbit", "star-sprout", "retired-avatar"])
        func oldAvatar(_ saved: String) throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            #expect(CompanionPreferences(defaults: store.value).avatar == .sig)
            store.value.set(saved, forKey: "appearance.avatar")
            #expect(CompanionPreferences(defaults: store.value).avatar == .sig)
            #expect(store.value.string(forKey: "appearance.avatar") == "sig")
        }
        @Test("G04.04 · Widget sizes persist and produce ascending widths") func widgetWidths() throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            var widths: [CGFloat] = []
            for size in WidgetSize.allCases {
                f.preferences.widgetSize = size
                #expect(CompanionPreferences(defaults: f.defaults).widgetSize == size)
                f.notch.show(); widths.append(f.notch.geometry.width); f.notch.hide()
            }
            try #require(widths.count == 3)
            #expect(widths[0] < widths[1] && widths[1] < widths[2])
        }
    }

    @MainActor @Suite(.tags(.isolated, .interactions)) struct CompanionReactionTests {
        @Test("G04.08 · Touch burst reaches sleep, remains asleep, wakes and recovers") func touchSequence() async throws {
            let clock = PresentationClock()
            let reactions = CompanionReactions(now: { clock.date }, recoveryDelay: .milliseconds(30), wakeDelay: .milliseconds(30))
            defer { reactions.reset() }
            for _ in 0..<3 { reactions.touch(); #expect(reactions.mood == .happy) }
            reactions.touch(); #expect(reactions.mood == .annoyed)
            reactions.touch(); #expect(reactions.mood == .asleep)
            try await PresentationWait.stays({ reactions.mood == .asleep }, for: .milliseconds(60))
            reactions.touch(); #expect(reactions.mood == .waking)
            try await PresentationWait.until { reactions.mood == .idle }
            reactions.touch(); clock.advance(4)
            reactions.touch(); reactions.touch(); reactions.touch()
            #expect(reactions.mood == .happy)
            reactions.reset(); #expect(reactions.mood == .idle)
        }
        @Test("G04.08 · Utility failure/success overrides mood and reset cancels recovery") func utilityResult() {
            let reactions = CompanionReactions(recoveryDelay: .milliseconds(30))
            defer { reactions.reset() }
            reactions.utility(false); #expect(reactions.mood == .startled)
            reactions.utility(true); #expect(reactions.mood == .understood)
            reactions.reset(); #expect(reactions.mood == .idle)
        }
    }

    @MainActor @Suite(.tags(.interactions, .nativeView)) struct IslandHitTargetTests {
        @Test("G04.09 · Offscreen first-click views preserve complete hit regions and toggle once") func firstClick() throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let hitZone = HoverZoneView(frame: NSRect(x: 0, y: 0, width: 240, height: 36))
            let hosted = IslandHostingView(rootView: Text("Offscreen check"))
            #expect(hitZone.acceptsFirstMouse(for: nil) && hosted.acceptsFirstMouse(for: nil))
            for x in [CGFloat(1), 120, 239] { #expect(hitZone.hitTest(NSPoint(x: x, y: 18)) === hitZone) }
            #expect(hitZone.hitTest(NSPoint(x: 241, y: 18)) == nil)
            hitZone.onClick = { f.notch.clickIsland() }; defer { hitZone.onClick = nil }
            let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            hitZone.mouseDown(with: click)
            #expect(f.notch.isVisible && f.notch.presentation == .home)
            hitZone.mouseDown(with: click)
            #expect(!f.notch.isVisible)
        }
    }

    @MainActor @Suite(.tags(.isolated, .interactions)) struct IslandPresentationTests {
        @Test("G04.10 · Current AI work drives compact/expanded content and hover never expands") func currentAIWork() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let task = AIWork(id: "fixture", provider: .codex, model: "fixture-model", project: "Fixture project",
                startedAt: f.clock.date.addingTimeInterval(-20), lastSeen: f.clock.date, output: 100)
            let prices = PriceCatalog(entries: try JSONDecoder().decode([ModelPrice].self, from: Data(contentsOf: TestResources.priceCatalogURL)))
            let usage = AIUsageViewModel(defaults: f.defaults, readClaude: { nil }, initialAnalytics: AIAnalytics(work: [task]), initialPrices: prices, read: { _ in nil })
            f.notch.aiUsage = usage
            f.notch.showIsland()
            #expect(f.notch.isVisible && f.notch.presentation == .island && f.notch.geometry.height == 36)
            f.notch.clickIsland(); #expect(f.notch.presentation == .aiLimits)
            f.notch.clickIsland(); #expect(f.notch.presentation == .island)
            f.notch.setPointerInsidePanel(true)
            try await PresentationWait.stays({ f.notch.presentation == .island && f.notch.isPointerHovering }, for: .milliseconds(100))
            f.notch.setPointerInsidePanel(false); f.notch.showCurrentTask()
            #expect(f.notch.presentation == .aiLimits)
            f.notch.hide(); #expect(f.notch.presentation == .island)
            let disconnected = CodexUsageViewModel(defaults: f.defaults, load: { throw CodexUsageError.unavailable })
            usage.disable(.codex, codex: disconnected)
            f.notch.showIsland(); #expect(!f.notch.isVisible)
            f.notch.aiUsage = nil
        }
        @Test("G04.10 · Stopwatch drives island and explicit countdown announces once") func utilityTimer() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            f.assistant.selectTimerMode(.timer); f.notch.showTimer()
            #expect(f.assistant.selectedTimerMode == .timer && !f.assistant.utilityClock.hasSession)
            f.assistant.utilityClock.start(.stopwatch)
            f.notch.hide(); #expect(f.notch.presentation == .island)
            f.notch.clickIsland()
            #expect(f.notch.presentation == .timer && f.assistant.selectedTimerMode == .stopwatch)
            f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.until { f.notch.presentation == .island }
            #expect(f.assistant.utilityClock.isRunning)
            f.assistant.utilityClock.reset(); f.notch.hide()
            f.assistant.utilityClock.start(.timer, minutes: 1)
            try await PresentationWait.until { f.notch.presentation == .island }
            f.clock.advance(61); f.assistant.utilityClock.refresh()
            try await PresentationWait.until { f.notch.presentation == .timer }
            #expect(f.assistant.utilityClock.phase == .completed && f.assistant.completedSessions == 0)
            try await PresentationWait.until { !f.notch.isVisible }
            // Delivering the same completed clock reading cannot replay its announcement.
            f.assistant.utilityClock.refresh()
            #expect(!f.notch.isVisible)
        }
        @Test("G04.10 · Crossing native and hosted hover regions keeps island stable") func hoverCrossing() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            f.notch.setPointerInsideHoverZone(true)
            #expect(f.notch.presentation == .island && f.notch.isPointerHovering)
            f.notch.setPointerInsidePanel(true); f.notch.setPointerInsideHoverZone(false)
            try await PresentationWait.stays({ f.notch.isVisible && f.notch.presentation == .island }, for: .milliseconds(100))
            f.notch.setPointerInsidePanel(false)
            try await PresentationWait.until { !f.notch.isVisible }
        }
    }

    @MainActor @Suite(.tags(.isolated, .interactions)) struct ShortcutLifecycleTests {
        @Test("G04.11 · Abandoned recording only cancels matching recorder and restores activation") func abandonedRecorder() throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            #expect(activation.voiceShortcut == .voice && activation.voiceShortcut?.keyCode != nil)
            activation.recordingShortcut = .voice; activation.performShortcut(.companion)
            #expect(!f.notch.isVisible)
            activation.cancelShortcutRecording(for: .companion); #expect(activation.recordingShortcut == .voice)
            activation.cancelShortcutRecording(for: .voice); activation.performShortcut(.companion)
            #expect(f.notch.isVisible)
            f.notch.hide(); activation.recordingShortcut = .companion; activation.recoverShortcuts()
            #expect(activation.recordingShortcut == nil)
            #expect(activation.companionShortcut == .companion && activation.voiceShortcut == .voice)
            activation.performShortcut(.companion); #expect(f.notch.isVisible)
        }
        @Test("G04.11 · Space changes and offscreen settings closure restore both event backends") func lifecycleRecovery() throws {
            let f = try PresentationFixture(observesShortcutLifecycle: true); defer { f.cleanup() }
            let activation = try f.activation()
            activation.recordingShortcut = .voice
            f.lifecycle.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            #expect(activation.recordingShortcut == nil)
            activation.performShortcut(.companion)
            #expect(f.notch.isVisible && activation.lastShortcutActivation != nil)
            f.notch.hide(); activation.recordingShortcut = .companion
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: nil)
            #expect(activation.recordingShortcut == nil)
            activation.receiveHotkey(.companion, eventTime: 210)
            #expect(f.notch.isVisible)
            f.notch.hide()
            activation.receiveShortcutEvent(keyCode: ShortcutChord.companion.keyCode, flags: ShortcutChord.companion.flags, eventTime: 211)
            #expect(f.notch.isVisible)
        }
        @Test("G04.11 · Shortcut persistence and shared voice/audio collision checks") func persistenceAndCollisions() throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            let custom = ShortcutChord(keyCode: 18, modifiers: NSEvent.ModifierFlags([.command, .option, .shift]).rawValue, keyLabel: "1")
            activation.setShortcut(.legacyVoice, for: .voice)
            let legacy = ActivationController(assistant: f.assistant, notch: f.notch, defaults: f.defaults, registersShortcuts: false, voiceCapture: f.capture)
            defer { legacy.shutdown() }
            #expect(legacy.voiceShortcut == .legacyVoice)
            activation.setShortcut(custom, for: .voice)
            let restored = ActivationController(assistant: f.assistant, notch: f.notch, defaults: f.defaults, registersShortcuts: false, voiceCapture: f.capture)
            defer { restored.shutdown() }
            #expect(restored.voiceShortcut == custom)
            activation.setShortcut(activation.companionShortcut, for: .voice); #expect(activation.voiceShortcut == custom)
            #expect(activation.shortcut(for: .nextOutput) == nil && activation.shortcut(for: .muteMicrophone) == nil)
            activation.setShortcut(custom, for: .nextOutput); #expect(activation.shortcut(for: .nextOutput) == nil)
            let output = ShortcutChord(keyCode: 20, modifiers: NSEvent.ModifierFlags([.command, .option, .shift]).rawValue, keyLabel: "3")
            activation.setShortcut(output, for: .nextOutput)
            let audio = ActivationController(assistant: f.assistant, notch: f.notch, defaults: f.defaults, registersShortcuts: false, voiceCapture: f.capture)
            defer { audio.shutdown() }
            #expect(audio.shortcut(for: .nextOutput) == output)
            activation.setShortcut(output, for: .muteMicrophone); #expect(activation.shortcut(for: .muteMicrophone) == nil)
            activation.setShortcut(nil, for: .nextOutput); #expect(activation.shortcut(for: .nextOutput) == nil)
        }
        @Test("G04.11 · Shutdown detaches exact observer centers, is repeatable and preserves another owner") func shutdownOwnership() throws {
            let f = try PresentationFixture(observesShortcutLifecycle: true), other = try PresentationFixture()
            defer { f.cleanup(); other.cleanup() }
            let activation = try f.activation(), otherController = try other.activation()
            let previousOwner = ActivationController.activeHotkeyOwner
            ActivationController.activeHotkeyOwner = otherController
            defer { ActivationController.activeHotkeyOwner = previousOwner }
            activation.shutdown(); activation.shutdown()
            #expect(ActivationController.activeHotkeyOwner === otherController)
            activation.recordingShortcut = .voice
            f.lifecycle.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: nil)
            #expect(activation.recordingShortcut == .voice)
        }
    }
}
