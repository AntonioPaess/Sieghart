import AppKit
import Foundation
import SwiftUI

@main
struct InteractionChecks {
    @MainActor static func drainEvents() { RunLoop.main.run(until: Date().addingTimeInterval(0.04)) }

    @MainActor static func main() async throws {
        // Actual command parsing: natural wording, repeated recognition words,
        // duration boundaries, negation, conflicting actions, and Portuguese.
        precondition(FocusVoiceParser.parse("Start focus focus") == .start(minutes: nil))
        precondition(FocusVoiceParser.parse("Please start focus for twenty five minutes") == .start(minutes: 25))
        precondition(FocusVoiceParser.parse("Quero focar por cinquenta minutos") == .start(minutes: 50))
        precondition(FocusVoiceParser.parse("Can you pause my focus timer") == .pause)
        precondition(FocusVoiceParser.parse("Take a break") == .startBreak)
        precondition(FocusVoiceParser.parse("Don't start focus") == nil)
        precondition(FocusVoiceParser.parse("Não iniciar o pomodoro") == nil)
        precondition(FocusVoiceParser.parse("Start and pause the timer") == nil)
        precondition(FocusVoiceParser.parse("Start focus for 90 minutes") == nil)
        precondition(FocusVoiceParser.parse("Start focus for one hour") == nil)
        precondition(FocusVoiceParser.parse("Start focus for seven minutes") == nil)
        precondition(FocusVoiceParser.parse("Start focus for 20 or 25 minutes") == nil)
        precondition(FocusVoiceParser.parse("Start focus for fifty nine minutes") == nil)
        precondition(FocusVoiceParser.parse("Start focus for -5 minutes") == nil)
        precondition(FocusVoiceParser.parse("Start focus for twenty-five minutes") == .start(minutes: 25))
        precondition(FocusVoiceParser.parse("Show and hide") == nil)
        precondition(FocusVoiceParser.parse("Open Warp") == .openApp(name: "warp"))
        precondition(FocusVoiceParser.parse("Open Safari and search YouTube") == nil)
        precondition(FocusVoiceParser.parse("Abra o WhatsApp") == .openApp(name: "whatsapp"))
        precondition(FocusVoiceParser.parse("Open Safari") == .openApp(name: "safari"))
        precondition(FocusVoiceParser.parse("Open Safari; rm -rf something") == nil)
        precondition(FocusVoiceParser.parse("Não abra o WhatsApp") == nil)
        precondition(FocusVoiceParser.parse("Open Sieghart") == .show)
        precondition(FocusVoiceParser.parse("What is my ai limits") == .aiLimits)
        precondition(FocusVoiceParser.parse("What are my AI limits?") == .aiLimits)
        precondition(FocusVoiceParser.parse("Mostre meus limites do Codex") == .aiLimits)
        precondition(FocusVoiceParser.parse("Show AI limits and start focus") == nil)
        precondition(FocusVoiceParser.parse("Don't show my AI limits") == nil)

        var tracker = ModifierShortcutTracker()
        tracker.keyPressed() // Normal typing must not block the next modifier shortcut.
        precondition(tracker.update(.option) == nil)
        precondition(tracker.update([.option, .command]) == nil)
        precondition(tracker.update(.command) == nil)
        precondition(tracker.update([]) == ShortcutChord.legacyVoice.modifiers)
        precondition(tracker.update([]) == nil) // One release, one activation.
        _ = tracker.update([.option, .command]); tracker.keyPressed()
        precondition(tracker.update([]) == nil) // A regular keyboard shortcut isn't a voice trigger.
        _ = tracker.update([.option, .command, .shift])
        precondition(tracker.update([]) != ShortcutChord.legacyVoice.modifiers)

        let suite = "Sieghart.InteractionChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let assistant = AssistantViewModel(defaults: defaults, now: { clock }, schedulesTimer: false)
        let preferences = CompanionPreferences(defaults: defaults)
        precondition(preferences.appearance == .system && !preferences.windowGlass && !preferences.islandGlass)
        for theme in AppAppearance.allCases {
            preferences.appearance = theme
            precondition(CompanionPreferences(defaults: defaults).appearance == theme)
        }
        preferences.windowGlass = true
        precondition(CompanionPreferences(defaults: defaults).windowGlass && !CompanionPreferences(defaults: defaults).islandGlass)
        preferences.windowGlass = false; preferences.islandGlass = true
        precondition(!CompanionPreferences(defaults: defaults).windowGlass && CompanionPreferences(defaults: defaults).islandGlass)
        preferences.islandGlass = false; preferences.appearance = .system
        let display = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        precondition(NotchOverlayPolicy.coversDisplay(display, display: display))
        precondition(!NotchOverlayPolicy.coversDisplay(CGRect(x: 0, y: 0, width: 1440, height: 900), display: display))
        precondition(!NotchOverlayPolicy.coversDisplay(CGRect(x: -1440, y: 24, width: 1440, height: 876), display: display))
        precondition(!NotchOverlayPolicy.coversDisplay(.zero, display: display))
        precondition(NotchOverlayPolicy.level(fullScreen: true) == .screenSaver)
        precondition(NotchOverlayPolicy.level(fullScreen: false).rawValue > NSWindow.Level.statusBar.rawValue)
        for avatar in CompanionAvatar.allCases {
            guard let icon = CompanionArtwork.menuBarImage(for: avatar) else { fatalError("Missing vector menu image") }
            precondition(icon.size == NSSize(width: 22, height: 22))
            precondition(icon.isTemplate == (avatar == .minimalSpirit))
            for mood: CompanionMood in [.idle, .happy, .annoyed, .asleep, .waking, .startled, .understood, .celebrating] {
                let still = CompanionMotion.sample(time: 0, size: 24, avatar: avatar, mood: mood, listening: true, strolling: true, animates: false)
                let later = CompanionMotion.sample(time: 100, size: 24, avatar: avatar, mood: mood, listening: true, strolling: true, animates: false)
                precondition(still == later) // Motion disabled never depends on the clock.
                if mood == .asleep {
                    let asleepA = CompanionMotion.sample(time: 0.2, size: 96, avatar: avatar, mood: .asleep, listening: false, strolling: false, animates: true)
                    let asleepB = CompanionMotion.sample(time: 1.5, size: 96, avatar: avatar, mood: .asleep, listening: false, strolling: false, animates: true)
                    precondition(asleepA != asleepB && asleepA.eyeOpen == 0.07 && asleepB.eyeOpen == 0.07, "All sleeping avatars must breathe while their eyes remain closed")
                }
                let moving = CompanionMotion.sample(time: 0.14, size: 24, avatar: avatar, mood: mood, listening: false, strolling: false, animates: true)
                precondition(moving.eyeOpen.isFinite && moving.scaleX > 0 && moving.scaleY > 0)
            }
        }
        let blinkClosed = CompanionMotion.sample(time: 0.14, size: 42, avatar: .crtBuddy, mood: .idle, listening: false, strolling: false, animates: true)
        let blinkOpen = CompanionMotion.sample(time: 0.28, size: 42, avatar: .crtBuddy, mood: .idle, listening: false, strolling: false, animates: true)
        precondition(blinkClosed.eyeOpen < 0.05 && blinkOpen.eyeOpen == 1)
        let compactNotch = NotchGeometry(width: 328, cutoutWidth: 180, cutoutHeight: 32, compact: true)
        precondition(compactNotch.height == 32 && compactNotch.contentTop == 0)
        precondition(compactNotch.width > compactNotch.cutoutWidth)

        let reactions = CompanionReactions(now: { clock }, recoveryDelay: .milliseconds(30), wakeDelay: .milliseconds(30))
        for _ in 0..<3 { reactions.touch(); precondition(reactions.mood == .happy) }
        reactions.touch(); precondition(reactions.mood == .annoyed)
        reactions.touch(); precondition(reactions.mood == .asleep)
        try await Task.sleep(for: .milliseconds(60))
        precondition(reactions.mood == .asleep) // Sleep lasts until the next interaction.
        reactions.touch(); precondition(reactions.mood == .waking)
        try await Task.sleep(for: .milliseconds(60))
        precondition(reactions.mood == .idle)
        reactions.touch(); clock = clock.addingTimeInterval(4)
        reactions.touch(); reactions.touch(); reactions.touch()
        precondition(reactions.mood == .happy) // An old tap doesn't join a new burst.
        reactions.reset(); precondition(reactions.mood == .idle)
        precondition(preferences.avatar == .crtBuddy)
        for avatar in CompanionAvatar.allCases {
            preferences.avatar = avatar
            precondition(CompanionPreferences(defaults: defaults).avatar == avatar)
        }
        defaults.set("soft-orbit", forKey: "appearance.avatar")
        precondition(CompanionPreferences(defaults: defaults).avatar == .coastBuddy)
        defaults.set("star-sprout", forKey: "appearance.avatar")
        precondition(CompanionPreferences(defaults: defaults).avatar == .inkBuddy)
        defaults.set("retired-avatar", forKey: "appearance.avatar")
        precondition(CompanionPreferences(defaults: defaults).avatar == .crtBuddy)
        preferences.avatar = .crtBuddy
        let notch = NotchWidgetController(assistant: assistant, preferences: preferences, managesWindows: false, announcementDelay: .milliseconds(90), pointerExitDelay: .milliseconds(250), keyboardRevealDelay: .milliseconds(1100))
        let lifecycle = NotificationCenter()
        let activation = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false, lifecycleNotifications: lifecycle, openApplication: { name in "Fixture " + name })
        notch.activation = activation
        precondition(activation.voiceShortcut == .voice && activation.voiceShortcut?.keyCode != nil)
        // A first click from another app must reach both native activation and
        // the SwiftUI controls. These views stay offscreen; no window is opened.
        let hitZone = HoverZoneView(frame: NSRect(x: 0, y: 0, width: 240, height: 36))
        let hosted = IslandHostingView(rootView: Text("Offscreen check"))
        precondition(hitZone.acceptsFirstMouse(for: nil) && hosted.acceptsFirstMouse(for: nil))
        precondition(hitZone.hitTest(NSPoint(x: 120, y: 18)) === hitZone)
        precondition(hitZone.hitTest(NSPoint(x: 1, y: 18)) === hitZone)
        precondition(hitZone.hitTest(NSPoint(x: 239, y: 18)) === hitZone)
        precondition(hitZone.hitTest(NSPoint(x: 241, y: 18)) == nil)
        hitZone.onClick = { notch.clickIsland() }
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        hitZone.mouseDown(with: click)
        precondition(notch.isVisible && notch.presentation == .home)
        hitZone.mouseDown(with: click)
        precondition(!notch.isVisible) // Second activation click closes, rather than reopening.

        let liveTask = AIWork(id: "fixture", provider: .codex, model: "fixture-model", project: "Fixture project", startedAt: .now.addingTimeInterval(-20), lastSeen: .now, output: 100)
        let liveUsage = AIUsageModel(defaults: defaults, initialAnalytics: AIAnalytics(work: [liveTask]), read: { _ in nil })
        notch.aiUsage = liveUsage
        notch.showIsland()
        precondition(notch.isVisible && notch.presentation == .island && notch.geometry.height == 36)
        hitZone.mouseDown(with: click)
        precondition(notch.presentation == .aiLimits)
        hitZone.mouseDown(with: click)
        precondition(notch.presentation == .island)
        notch.setPointerInsidePanel(true)
        try await Task.sleep(for: .milliseconds(300))
        precondition(notch.presentation == .island && notch.isPointerHovering) // Hover highlights; it never expands.
        notch.setPointerInsidePanel(false)
        notch.showCurrentTask()
        precondition(notch.presentation == .aiLimits) // No focus timer needed for live AI.
        notch.hide()
        precondition(notch.presentation == .island)
        let disconnected = CodexUsageModel(defaults: defaults, load: { throw CodexUsageError.unavailable })
        liveUsage.disable(.codex, codex: disconnected)
        notch.showIsland()
        precondition(!notch.isVisible)
        notch.aiUsage = nil
        assistant.selectTimerMode(.timer)
        notch.showTimer()
        precondition(assistant.selectedTimerMode == .timer && !assistant.utilityClock.hasSession)
        assistant.utilityClock.start(.stopwatch)
        drainEvents(); notch.hide()
        precondition(notch.presentation == .island)
        hitZone.mouseDown(with: click)
        precondition(notch.presentation == .timer && assistant.selectedTimerMode == .stopwatch)
        notch.setPointerInsidePanel(true); notch.setPointerInsidePanel(false)
        try await Task.sleep(for: .milliseconds(320))
        precondition(notch.presentation == .island && assistant.utilityClock.isRunning)
        assistant.utilityClock.reset(); drainEvents(); notch.hide()
        assistant.utilityClock.start(.timer, minutes: 1); drainEvents()
        clock = clock.addingTimeInterval(61); assistant.utilityClock.refresh(); drainEvents()
        precondition(notch.presentation == .timer && assistant.utilityClock.phase == .completed && assistant.completedSessions == 0)
        try await Task.sleep(for: .milliseconds(170))
        precondition(!notch.isVisible) // The explicit countdown announces once, then closes.
        assistant.utilityClock.reset(); drainEvents()
        var widths: [CGFloat] = []
        for size in WidgetSize.allCases {
            preferences.widgetSize = size
            precondition(CompanionPreferences(defaults: defaults).widgetSize == size)
            notch.show(); widths.append(notch.geometry.width); notch.hide()
        }
        precondition(widths[0] < widths[1] && widths[1] < widths[2])
        preferences.widgetSize = .medium
        notch.setPointerInsideHoverZone(true)
        precondition(notch.presentation == .island && notch.isPointerHovering)
        notch.setPointerInsidePanel(true)
        notch.setPointerInsideHoverZone(false)
        try await Task.sleep(for: .milliseconds(320))
        precondition(notch.isVisible && notch.presentation == .island) // Crossing between native and SwiftUI hover regions is stable.
        notch.setPointerInsidePanel(false)
        try await Task.sleep(for: .milliseconds(320))
        precondition(!notch.isVisible)

        // Abandoning a recorder or changing apps cannot leave activation locked.
        activation.recordingShortcut = .voice
        activation.performShortcut(.companion)
        precondition(!notch.isVisible)
        activation.cancelShortcutRecording(for: .companion)
        precondition(activation.recordingShortcut == .voice)
        activation.cancelShortcutRecording(for: .voice)
        activation.performShortcut(.companion)
        precondition(notch.isVisible)
        notch.hide()

        activation.recordingShortcut = .voice
        lifecycle.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(220))
        precondition(activation.recordingShortcut == nil)
        activation.performShortcut(.companion)
        precondition(notch.isVisible && activation.lastShortcutActivation != nil)
        notch.hide()
        activation.recordingShortcut = .companion
        // Closing the settings surface during recording must restore both
        // event backends. Feed its notification without opening a real window.
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: nil)
        try await Task.sleep(for: .milliseconds(220))
        precondition(activation.recordingShortcut == nil)
        activation.receiveHotkey(.companion, eventTime: 210)
        precondition(notch.isVisible, "Companion activation must survive closing the settings window")
        notch.hide()
        activation.receiveShortcutEvent(keyCode: ShortcutChord.companion.keyCode, flags: ShortcutChord.companion.flags, eventTime: 211)
        precondition(notch.isVisible, "The monitor fallback must survive window closure too")
        notch.hide()
        activation.recordingShortcut = .companion
        activation.recoverShortcuts()
        precondition(activation.recordingShortcut == nil)
        precondition(activation.companionShortcut == .companion && activation.voiceShortcut == .voice)
        activation.performShortcut(.companion)
        precondition(notch.isVisible)
        notch.hide()

        let custom = ShortcutChord(keyCode: 18, modifiers: NSEvent.ModifierFlags([.command, .option, .shift]).rawValue, keyLabel: "1")
        activation.setShortcut(.legacyVoice, for: .voice)
        precondition(ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false).voiceShortcut == .legacyVoice)
        activation.setShortcut(custom, for: .voice)
        let restored = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false)
        precondition(restored.voiceShortcut == custom)
        activation.setShortcut(activation.companionShortcut, for: .voice)
        precondition(activation.voiceShortcut == custom) // Duplicate bindings are rejected.

        activation.executeVoiceCommand("Open Safari")
        precondition(notch.presentation == .home && activation.voicePresented && activation.transcript == "Open Safari")
        try await Task.sleep(for: .milliseconds(20))
        precondition(activation.commandAcknowledged && activation.voiceStatus == "Opened Fixture safari", "App launch commands use the injected local launcher, never a real app in tests")
        activation.executeVoiceCommand("Start focus for 50 minutes")
        precondition(assistant.isRunning && assistant.focusMinutes == 50)
        precondition(activation.commandAcknowledged)
        activation.executeVoiceCommand("Pause the timer")
        precondition(assistant.pomodoroPhase == .paused)
        activation.executeVoiceCommand("Resume")
        precondition(assistant.isRunning)
        activation.executeVoiceCommand("Don't start focus for 10 minutes")
        precondition(assistant.focusMinutes == 50) // Unsupported speech never changes the session.
        precondition(!activation.commandAcknowledged)
        precondition(notch.presentation == .home && activation.voicePresented)
        activation.cancelVoiceCommand(keepCompanionVisible: true)
        precondition(notch.presentation == .home && notch.isVisible && !activation.voicePresented)
        activation.executeVoiceCommand("Unsupported fixture command")
        notch.hide()
        precondition(!activation.voicePresented && activation.transcript.isEmpty)

        notch.showTools()
        precondition(notch.presentation == .tools && notch.isVisible)
        notch.showAudio(); precondition(notch.presentation == .audio)
        notch.setPointerInsidePanel(true); notch.setPointerInsidePanel(false)
        try await Task.sleep(for: .milliseconds(320))
        precondition(!notch.isVisible || notch.presentation == .island)
        notch.showAvatars(); precondition(notch.presentation == .avatars)
        notch.setPointerInsidePanel(true); notch.setPointerInsidePanel(false)
        try await Task.sleep(for: .milliseconds(320))
        precondition(!notch.isVisible || notch.presentation == .island)
        notch.showTools()
        activation.executeVoiceCommand("What is my ai limits")
        precondition(notch.presentation == .aiLimits && activation.commandAcknowledged)
        precondition(assistant.focusMinutes == 50 && assistant.isRunning)

        assistant.startFocusSession(minutes: 5, autoBreak: true)
        notch.showIsland()
        drainEvents()
        precondition(notch.presentation == .island && notch.geometry.height <= 50)
        notch.showCurrentTask()
        precondition(notch.presentation == .timer)
        notch.hide()
        precondition(notch.presentation == .island && assistant.isRunning)
        notch.handleImpact()
        precondition(notch.presentation == .home)
        notch.hide()
        precondition(notch.presentation == .island)
        notch.showFocusSetup()
        precondition(notch.presentation == .focusSetup)

        clock = clock.addingTimeInterval(301)
        assistant.refresh()
        drainEvents()
        precondition(assistant.completedSessions == 1 && assistant.interval == .shortBreak)
        precondition(notch.presentation == .celebration) // Automatic break must not skip the announcement.
        precondition(notch.latestCompletion?.interval == .focus)
        precondition(notch.latestCompletion?.automaticBreakMinutes == 5)
        try await Task.sleep(for: .milliseconds(170))
        precondition(notch.presentation == .island && assistant.isRunning)

        assistant.pausePomodoroFromGesture(); drainEvents()
        precondition(notch.presentation == .island && assistant.pomodoroPhase == .paused)
        notch.showCurrentTask(); notch.setPointerInsidePanel(false)
        try await Task.sleep(for: .milliseconds(1200))
        precondition(notch.presentation == .island) // Leaving expanded controls tucks them away.
        // Every expanded page obeys pointer exit, including former sticky pages.
        for open in [notch.show, notch.showTools, notch.showAILimits, notch.showFocusSetup, notch.showVoice] {
            open(); notch.setPointerInsidePanel(true); notch.setPointerInsidePanel(false)
            try await Task.sleep(for: .milliseconds(320))
            precondition(notch.presentation == .island && assistant.hasActiveSession)
        }
        assistant.resetPomodoro(); drainEvents(); notch.hide()
        precondition(!notch.isVisible)
        assistant.startFocusSession(minutes: 5, autoBreak: false)
        assistant.finishPomodoroFromWidget(); drainEvents()
        try await Task.sleep(for: .milliseconds(170))
        precondition(!notch.isVisible)
        notch.showCurrentTask()
        precondition(notch.presentation == .home) // Completed focus cannot hijack a reveal.
        let relaunched = NotchWidgetController(assistant: assistant, preferences: preferences, managesWindows: false)
        drainEvents()
        precondition(!relaunched.isVisible) // Published saved completion is not replayed.
        notch.hide()
        activation.setShortcut(ShortcutChord(keyCode: nil, modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue, keyLabel: ""), for: .companion)
        activation.receiveShortcutEvent(keyCode: nil, flags: [.control, .shift])
        activation.receiveShortcutEvent(keyCode: nil, flags: [])
        precondition(notch.isVisible)
        notch.hide()
        activation.receiveShortcutEvent(keyCode: nil, flags: [.control, .shift])
        activation.receiveShortcutEvent(keyCode: 1, flags: [.control, .shift])
        activation.receiveShortcutEvent(keyCode: nil, flags: [])
        precondition(!notch.isVisible) // A regular key suppresses modifier-only capture.
        activation.setShortcut(.companion, for: .companion)
        activation.receiveHotkey(.companion, eventTime: 100)
        activation.receiveShortcutEvent(keyCode: 1, flags: [.control, .option], eventTime: 100.01)
        precondition(notch.isVisible) // Two backends must not toggle the island twice.
        activation.receiveShortcutEvent(keyCode: 1, flags: [.control, .option], eventTime: 101)
        precondition(!notch.isVisible) // Session input works even with successful Carbon setup.
        activation.receiveHotkey(.companion, eventTime: 101.01)
        precondition(!notch.isVisible)
        var gate = ShortcutDeliveryGate()
        precondition(gate.accept(.companion, source: .monitor, at: 90.01))
        precondition(!gate.accept(.companion, source: .carbon, at: 90), "Reverse timestamp delivery must not immediately close a just-opened island")
        precondition(gate.accept(.voice, source: .monitor, at: 1))
        precondition(!gate.accept(.voice, source: .carbon, at: 1.01))
        precondition(gate.accept(.voice, source: .monitor, at: 1.1))
        precondition(gate.accept(.companion, source: .carbon, at: 1.1))

        let grace = NotchWidgetController(assistant: assistant, preferences: preferences, managesWindows: false, pointerExitDelay: .milliseconds(90), keyboardRevealDelay: .milliseconds(280))
        grace.show()
        grace.setPointerInsidePanel(false) // A layout/Space exit cannot cut short a keyboard reveal.
        try await Task.sleep(for: .milliseconds(150))
        precondition(grace.isVisible)
        grace.setPointerInsidePanel(true) // Reaching a control cancels the reveal timeout.
        try await Task.sleep(for: .milliseconds(170))
        precondition(grace.isVisible)
        grace.setPointerInsidePanel(false)
        try await Task.sleep(for: .milliseconds(50))
        grace.setPointerInsideHoverZone(true) // Crossing back into the header cancels collapse.
        try await Task.sleep(for: .milliseconds(80))
        precondition(grace.isVisible)
        grace.setPointerInsideHoverZone(false)
        try await Task.sleep(for: .milliseconds(140))
        precondition(!grace.isVisible)
        precondition(ShortcutChord.companion.matches(keyCode: 1, flags: [.control, .option]))
        precondition(!ShortcutChord.companion.matches(keyCode: 1, flags: [.control, .option, .command]))
        print("PASS: repeated touch moods and wake, exact notch height, simple vector icons, reduced-motion determinism and avatar persistence, voice intents and acknowledgement, abandoned shortcut recording and recovery, compact island, completion announcement, and automatic collapse")
    }
}
