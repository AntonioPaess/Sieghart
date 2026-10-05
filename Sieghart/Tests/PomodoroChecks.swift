import Foundation

// Compile with AssistantCore.swift and SensorEngine.swift; no app UI or sensor is started.
@main
struct PomodoroChecks {
    @MainActor private final class Clock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
    }

    @MainActor static func main() {
        let suite = "Sieghart.Checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock()
        func model() -> AssistantViewModel {
            AssistantViewModel(defaults: defaults, now: { clock.date }, schedulesTimer: false)
        }
        let timer = model()
        timer.startFocusSession(minutes: 50, shortBreak: 10, longBreak: 20, rounds: 2, autoBreak: false)
        clock.advance(75)
        timer.togglePomodoro()
        precondition(timer.pomodoroPhase == .paused && timer.remainingSeconds == 2925)
        let restored = model()
        precondition(restored.pomodoroPhase == .paused && restored.remainingSeconds == 2925)
        precondition(restored.focusMinutes == 50 && restored.shortBreakMinutes == 10 && restored.longBreakMinutes == 20 && restored.sessionsPerCycle == 2 && !restored.autoStartBreaks)
        restored.togglePomodoro()
        clock.advance(2925)
        restored.refresh()
        precondition(restored.pomodoroPhase == .completed && restored.completedSessions == 1 && restored.nextBreak == .shortBreak)
        restored.refresh()
        precondition(restored.completedSessions == 1)
        restored.startBreak()
        precondition(restored.interval == .shortBreak && restored.remainingSeconds == 600)
        clock.advance(30)
        restored.togglePomodoro()
        let pausedBreak = model()
        precondition(pausedBreak.interval == .shortBreak && pausedBreak.remainingSeconds == 570 && pausedBreak.pomodoroPhase == .paused)
        pausedBreak.togglePomodoro()
        clock.advance(570)
        pausedBreak.refresh()
        precondition(pausedBreak.completedSessions == 1 && pausedBreak.pomodoroPhase == .completed)
        pausedBreak.startFocusSession()
        pausedBreak.finishPomodoroFromWidget()
        precondition(pausedBreak.completedSessions == 2 && pausedBreak.nextBreak == .longBreak)
        pausedBreak.startBreak()
        precondition(pausedBreak.interval == .longBreak && pausedBreak.remainingSeconds == 1200)
        clock.advance(1200)
        pausedBreak.refresh()
        precondition(pausedBreak.cycleSessions == 0 && pausedBreak.completedSessions == 2)

        pausedBreak.startFocusSession(minutes: 5, shortBreak: 5, longBreak: 15, rounds: 2, autoBreak: true)
        clock.advance(300)
        pausedBreak.refresh()
        precondition(pausedBreak.isRunning && pausedBreak.interval == .shortBreak && pausedBreak.completedSessions == 3)
        clock.advance(300)
        pausedBreak.refresh()
        precondition(pausedBreak.pomodoroPhase == .completed && pausedBreak.completedSessions == 3)
        pausedBreak.startFocusSession()
        clock.advance(300)
        pausedBreak.refresh()
        precondition(pausedBreak.isRunning && pausedBreak.interval == .longBreak && pausedBreak.completedSessions == 4)
        clock.advance(900)
        let expired = model()
        precondition(expired.pomodoroPhase == .completed && expired.interval == .longBreak && expired.cycleSessions == 0 && expired.completedSessions == 4)
        let reopened = model()
        precondition(reopened.completedSessions == 4)
        reopened.startFocusSession()
        clock.advance(300)
        let expiredFocus = model()
        precondition(expiredFocus.pomodoroPhase == .completed && expiredFocus.completedSessions == 5)
        precondition(model().completedSessions == 5)
        defaults.set(17, forKey: "pomodoro.focusMinutes")
        precondition(model().focusMinutes == 25)
        print("PASS: focus configuration, pause/resume, short/long breaks, rounds, automatic breaks, relaunch restoration, and single completion counting")
    }
}
