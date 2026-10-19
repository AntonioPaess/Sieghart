import AppKit
import Foundation
import Testing

extension MacContractsTests {
    @MainActor @Suite(.tags(.isolated, .interactions)) struct ActivationDispatchTests {
        @Test("G04.12 · Injected browser acknowledges and collapsed result updates never reopen") func searchResult() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("search for café & Swift")
            try await PresentationWait.until { activation.commandAcknowledged }
            #expect(activation.voiceStatus == "Search opened · Fixture café & Swift" && f.notch.presentation == .home)
            #expect(f.queries == ["café & Swift"])
            f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.until { f.notch.presentation == .island }
            #expect(activation.voicePresented && activation.commandAcknowledged)
            f.notch.showVoice(); #expect(f.notch.presentation == .island)
            f.notch.clickIsland()
            #expect(f.notch.presentation == .home && activation.voicePresented)
        }
        @Test("G04.12 · App dispatcher uses injected launcher and preserves transcript") func appLaunch() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("Open Safari")
            #expect(f.notch.presentation == .home && activation.voicePresented && activation.transcript == "Open Safari")
            try await PresentationWait.until { activation.commandAcknowledged }
            #expect(activation.voiceStatus == "Opened Fixture safari" && f.apps == ["safari"])
        }
        @Test("G04.12 · Focus, pause and resume dispatch; unsupported speech cannot change duration") func focusCommands() throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("Start focus for 50 minutes")
            #expect(f.assistant.isRunning && f.assistant.focusMinutes == 50 && activation.commandAcknowledged)
            activation.executeVoiceCommand("Pause the timer"); #expect(f.assistant.pomodoroPhase == .paused)
            activation.executeVoiceCommand("Resume"); #expect(f.assistant.isRunning)
            activation.executeVoiceCommand("Don't start focus for 10 minutes")
            #expect(f.assistant.focusMinutes == 50 && !activation.commandAcknowledged)
            #expect(f.notch.presentation == .home && activation.voicePresented)
            activation.cancelVoiceCommand(keepCompanionVisible: true)
            #expect(f.notch.presentation == .home && f.notch.isVisible && !activation.voicePresented)
            activation.executeVoiceCommand("Unsupported fixture command"); f.notch.hide()
            #expect(!activation.voicePresented && activation.transcript.isEmpty)
        }
        @Test("G04.12 · Tools/audio/clipboard/avatar/AI routing and clipboard collisions") func toolRouting() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            f.notch.showTools(); #expect(f.notch.presentation == .tools && f.notch.isVisible)
            f.notch.showAudio(); #expect(f.notch.presentation == .audio)
            activation.receiveHotkey(.clipboard, eventTime: 10)
            #expect(f.notch.presentation == .clipboard && f.notch.isVisible)
            activation.receiveHotkey(.clipboard, eventTime: 11)
            #expect(!f.notch.isVisible || f.notch.presentation == .island)
            let companionChord = try #require(activation.companionShortcut)
            activation.setShortcut(companionChord, for: .clipboard)
            #expect(activation.clipboardShortcut == .clipboard)
            activation.setShortcut(nil, for: .clipboard); #expect(activation.clipboardShortcut == nil)
            activation.setShortcut(.clipboard, for: .clipboard)
            f.notch.showClipboard(); f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.until { !f.notch.isVisible || f.notch.presentation == .island }
            f.notch.showAvatars(); #expect(f.notch.presentation == .avatars)
            f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.until { !f.notch.isVisible || f.notch.presentation == .island }
            activation.executeVoiceCommand("Start focus for 50 minutes")
            f.notch.showTools(); activation.executeVoiceCommand("What is my ai limits")
            #expect(f.notch.presentation == .aiLimits && activation.commandAcknowledged)
            #expect(f.assistant.focusMinutes == 50 && f.assistant.isRunning)
        }
    }

    @MainActor @Suite(.tags(.isolated, .interactions)) struct IslandSessionTests {
        @Test("G04.13 · Active focus supports compact task, gesture reveal and setup") func focusPresentation() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            f.assistant.startFocusSession(minutes: 5, autoBreak: true); f.notch.showIsland()
            try await PresentationWait.until { f.notch.presentation == .island }
            #expect(f.notch.geometry.height <= 50)
            f.notch.showCurrentTask(); #expect(f.notch.presentation == .timer)
            f.notch.hide(); #expect(f.notch.presentation == .island && f.assistant.isRunning)
            f.notch.handleImpact(); #expect(f.notch.presentation == .home)
            f.notch.hide(); #expect(f.notch.presentation == .island)
            f.notch.showFocusSetup(); #expect(f.notch.presentation == .focusSetup)
        }
        @Test("G04.13 · Focus completion celebrates before automatic break and gesture pause stays compact") func automaticBreak() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            f.assistant.startFocusSession(minutes: 5, autoBreak: true)
            f.clock.advance(301); f.assistant.refresh()
            try await PresentationWait.until { f.notch.presentation == .celebration }
            #expect(f.assistant.completedSessions == 1 && f.assistant.interval == .shortBreak)
            #expect(f.notch.latestCompletion?.interval == .focus && f.notch.latestCompletion?.automaticBreakMinutes == 5)
            try await PresentationWait.until { f.notch.presentation == .island && f.assistant.isRunning }
            f.assistant.pausePomodoroFromGesture()
            try await PresentationWait.until { f.notch.presentation == .island && f.assistant.pomodoroPhase == .paused }
            f.notch.showCurrentTask(); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.until { f.notch.presentation == .island }
        }
        @Test("G04.13 · Every expanded page tucks away while session remains active", arguments: Array(0..<6))
        func expandedPages(_ page: Int) async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            f.assistant.startFocusSession(minutes: 5, autoBreak: false)
            let open: [() -> Void] = [f.notch.show, f.notch.showTools, f.notch.showAILimits, f.notch.showFocusSetup, { f.notch.showVoice() }, f.notch.showClipboard]
            open[page](); f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.until { f.notch.presentation == .island }
            #expect(f.assistant.hasActiveSession)
        }
        @Test("G04.13 · Finished focus does not hijack reveal or replay completion on relaunch") func noCompletionReplay() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            f.assistant.startFocusSession(minutes: 5, autoBreak: false)
            f.assistant.finishPomodoroFromWidget()
            try await PresentationWait.until { f.notch.presentation == .celebration }
            try await PresentationWait.until { !f.notch.isVisible }
            f.notch.showCurrentTask(); #expect(f.notch.presentation == .home)
            let relaunched = NotchWidgetViewModel(assistant: f.assistant, preferences: f.preferences,
                audio: f.notch.audio, monitor: f.notch.monitor, keepAwake: f.notch.keepAwake, displayPower: f.notch.displayPower,
                clipboard: f.notch.clipboard, calendar: IsolatedCalendarFixture.make(defaults: f.defaults), managesWindows: false)
            defer { relaunched.hide(); relaunched.stopUtilities() }
            try await PresentationWait.stays({ !relaunched.isVisible }, for: .milliseconds(100))
        }
    }

    @MainActor @Suite(.tags(.isolated, .interactions)) struct IslandRevealTests {
        @Test("G04.14 · Modifier-only shortcuts suppress ordinary keys and backend duplicates") func shortcutDelivery() throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            activation.setShortcut(ShortcutChord(keyCode: nil, modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue, keyLabel: ""), for: .companion)
            activation.receiveShortcutEvent(keyCode: nil, flags: [.control, .shift])
            activation.receiveShortcutEvent(keyCode: nil, flags: [])
            #expect(f.notch.isVisible)
            f.notch.hide()
            activation.receiveShortcutEvent(keyCode: nil, flags: [.control, .shift])
            activation.receiveShortcutEvent(keyCode: 1, flags: [.control, .shift])
            activation.receiveShortcutEvent(keyCode: nil, flags: [])
            #expect(!f.notch.isVisible)
            activation.setShortcut(.companion, for: .companion)
            activation.receiveHotkey(.companion, eventTime: 100)
            activation.receiveShortcutEvent(keyCode: 1, flags: [.control, .option], eventTime: 100.01)
            #expect(f.notch.isVisible)
            activation.receiveShortcutEvent(keyCode: 1, flags: [.control, .option], eventTime: 101)
            #expect(!f.notch.isVisible)
            activation.receiveHotkey(.companion, eventTime: 101.01)
            #expect(!f.notch.isVisible)
        }
        @Test("G04.14 · Keyboard reveal grace survives layout exit and header crossing cancels collapse") func revealGrace() async throws {
            let f = try PresentationFixture(pointerExitDelay: .milliseconds(90), keyboardRevealDelay: .milliseconds(280))
            defer { f.cleanup() }
            f.notch.show(); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.stays({ f.notch.isVisible }, for: .milliseconds(150))
            f.notch.setPointerInsidePanel(true)
            try await PresentationWait.stays({ f.notch.isVisible }, for: .milliseconds(170))
            f.notch.setPointerInsidePanel(false)
            try await PresentationWait.stays({ f.notch.isVisible }, for: .milliseconds(50))
            f.notch.setPointerInsideHoverZone(true)
            try await PresentationWait.stays({ f.notch.isVisible }, for: .milliseconds(80))
            f.notch.setPointerInsideHoverZone(false)
            try await PresentationWait.until { !f.notch.isVisible }
        }
    }
}
