import AppKit
import Foundation

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
        precondition(FocusVoiceParser.parse("Open Warp") == nil)
        precondition(FocusVoiceParser.parse("Open Safari and search YouTube") == nil)
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
        precondition(tracker.update([]) == ShortcutChord.voice.modifiers)
        precondition(tracker.update([]) == nil) // One release, one activation.
        _ = tracker.update([.option, .command]); tracker.keyPressed()
        precondition(tracker.update([]) == nil) // A regular keyboard shortcut isn't a voice trigger.
        _ = tracker.update([.option, .command, .shift])
        precondition(tracker.update([]) != ShortcutChord.voice.modifiers)

        let suite = "Sieghart.InteractionChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let assistant = AssistantViewModel(defaults: defaults, now: { clock }, schedulesTimer: false)
        let preferences = CompanionPreferences(defaults: defaults)
        CompanionSprites.directory = URL(fileURLWithPath: "Sieghart/Sieghart/AvatarSprites", isDirectory: true)
        for avatar in CompanionAvatar.allCases {
            for pose in CompanionPose.allCases {
                precondition(CompanionSprites.image(for: avatar, pose: pose) != nil)
            }
            precondition(CompanionSprites.menuBarImage(for: avatar)?.isTemplate == false)
        }
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
        let notch = NotchWidgetController(assistant: assistant, preferences: preferences, managesWindows: false, announcementDelay: .milliseconds(90))
        let lifecycle = NotificationCenter()
        let activation = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false, lifecycleNotifications: lifecycle)
        notch.activation = activation

        let liveTask = AIWork(id: "fixture", provider: .codex, model: "fixture-model", project: "Fixture project", startedAt: .now.addingTimeInterval(-20), lastSeen: .now, output: 100)
        let liveUsage = AIUsageModel(defaults: defaults, initialAnalytics: AIAnalytics(work: [liveTask]), read: { _ in nil })
        notch.aiUsage = liveUsage
        notch.showIsland()
        precondition(notch.isVisible && notch.presentation == .island && notch.geometry.height == 36)
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
        activation.recoverShortcuts()
        precondition(activation.recordingShortcut == nil)
        precondition(activation.companionShortcut == .companion && activation.voiceShortcut == .voice)
        activation.performShortcut(.companion)
        precondition(notch.isVisible)
        notch.hide()

        let custom = ShortcutChord(keyCode: 18, modifiers: NSEvent.ModifierFlags([.command, .option, .shift]).rawValue, keyLabel: "1")
        activation.setShortcut(custom, for: .voice)
        let restored = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false)
        precondition(restored.voiceShortcut == custom)
        activation.setShortcut(activation.companionShortcut, for: .voice)
        precondition(activation.voiceShortcut == custom) // Duplicate bindings are rejected.

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

        notch.showTools()
        precondition(notch.presentation == .tools && notch.isVisible)
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
        precondition(ShortcutChord.companion.matches(keyCode: 1, flags: [.control, .option]))
        precondition(!ShortcutChord.companion.matches(keyCode: 1, flags: [.control, .option, .command]))
        print("PASS: repeated touch moods and wake, exact notch height, avatar resources and persistence, voice intents and acknowledgement, abandoned shortcut recording and recovery, compact island, completion announcement, and automatic collapse")
    }
}
