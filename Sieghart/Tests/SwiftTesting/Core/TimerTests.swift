import Foundation
import Testing

@MainActor private final class CoreTimerFixture {
  let storage: TestDefaults
  init() throws { storage = try TestDefaults() }
  var date = Date(timeIntervalSince1970: 1_800_000_000)
  func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
  func model() -> AssistantViewModel {
    AssistantViewModel(defaults: storage.value, now: { self.date }, schedulesTimer: false)
  }
  func cleanup() { storage.cleanup() }
}

extension MacContractsTests {
  @Suite(.tags(.timer, .isolated)) @MainActor
  struct TimerTests {
    @Test("G01.01 focus pauses, restores its configuration and completes once")
    func focusRestore() throws {
      let f = try CoreTimerFixture()
      defer { f.cleanup() }
      let timer = f.model()
      timer.startFocusSession(
        minutes: 50, shortBreak: 10, longBreak: 20, rounds: 2, autoBreak: false)
      f.advance(75)
      timer.togglePomodoro()
      #expect(timer.pomodoroPhase == .paused && timer.remainingSeconds == 2925)
      let restored = f.model()
      #expect(restored.pomodoroPhase == .paused && restored.remainingSeconds == 2925)
      #expect(
        restored.focusMinutes == 50 && restored.shortBreakMinutes == 10
          && restored.longBreakMinutes == 20)
      #expect(restored.sessionsPerCycle == 2 && !restored.autoStartBreaks)
      restored.togglePomodoro()
      f.advance(2925)
      restored.refresh()
      #expect(
        restored.pomodoroPhase == .completed && restored.completedSessions == 1
          && restored.nextBreak == .shortBreak)
      restored.refresh()
      #expect(restored.completedSessions == 1)
    }

    @Test("G01.02 short break restores without counting another focus session")
    func shortBreakRestore() throws {
      let f = try CoreTimerFixture()
      defer { f.cleanup() }
      let timer = f.model()
      timer.startFocusSession(
        minutes: 50, shortBreak: 10, longBreak: 20, rounds: 2, autoBreak: false)
      timer.finishPomodoroFromWidget()
      timer.startBreak()
      #expect(timer.interval == .shortBreak && timer.remainingSeconds == 600)
      f.advance(30)
      timer.togglePomodoro()
      let restored = f.model()
      #expect(
        restored.interval == .shortBreak && restored.remainingSeconds == 570
          && restored.pomodoroPhase == .paused)
      restored.togglePomodoro()
      f.advance(570)
      restored.refresh()
      #expect(restored.completedSessions == 1 && restored.pomodoroPhase == .completed)
    }

    @Test("G01.03 widget completion selects long break and resets the cycle")
    func widgetAndLongBreak() throws {
      let f = try CoreTimerFixture()
      defer { f.cleanup() }
      let timer = f.model()
      timer.startFocusSession(
        minutes: 50, shortBreak: 10, longBreak: 20, rounds: 2, autoBreak: false)
      timer.finishPomodoroFromWidget()
      timer.startBreak()
      f.advance(600)
      timer.refresh()
      timer.startFocusSession()
      timer.finishPomodoroFromWidget()
      #expect(timer.completedSessions == 2 && timer.nextBreak == .longBreak)
      timer.startBreak()
      #expect(timer.interval == .longBreak && timer.remainingSeconds == 1200)
      f.advance(1200)
      timer.refresh()
      #expect(timer.cycleSessions == 0 && timer.completedSessions == 2)
    }

    @Test("G01.04 automatic breaks and expiry during relaunch do not duplicate completions")
    func automaticBreaksAndRelaunch() throws {
      let f = try CoreTimerFixture()
      defer { f.cleanup() }
      let timer = f.model()
      timer.startFocusSession(minutes: 5, shortBreak: 5, longBreak: 15, rounds: 2, autoBreak: true)
      f.advance(300)
      timer.refresh()
      #expect(timer.isRunning && timer.interval == .shortBreak && timer.completedSessions == 1)
      f.advance(300)
      timer.refresh()
      #expect(timer.pomodoroPhase == .completed && timer.completedSessions == 1)
      timer.startFocusSession()
      f.advance(300)
      timer.refresh()
      #expect(timer.isRunning && timer.interval == .longBreak && timer.completedSessions == 2)
      f.advance(900)
      let expired = f.model()
      #expect(
        expired.pomodoroPhase == .completed && expired.interval == .longBreak
          && expired.cycleSessions == 0)
      #expect(expired.completedSessions == 2 && f.model().completedSessions == 2)
      expired.startFocusSession()
      f.advance(300)
      let expiredFocus = f.model()
      #expect(expiredFocus.pomodoroPhase == .completed && expiredFocus.completedSessions == 3)
      #expect(f.model().completedSessions == 3)
    }

    @Test("G01.05 invalid focus setting falls back and selecting a tool has no side effect")
    func invalidSettingsAndToolSelection() throws {
      let f = try CoreTimerFixture()
      defer { f.cleanup() }
      f.storage.value.set(17, forKey: "pomodoro.focusMinutes")
      let model = f.model()
      #expect(model.focusMinutes == 25)
      model.selectTimerMode(.stopwatch)
      #expect(!model.utilityClock.hasSession)
    }

    @Test("G01.06 countdown preserves fractional seconds while paused and restores completion")
    func countdown() throws {
      let f = try CoreTimerFixture()
      defer { f.cleanup() }
      let clock = f.model().utilityClock
      clock.start(.timer, minutes: 2)
      f.advance(30.5)
      clock.refresh()
      #expect(clock.seconds == 89.5 && clock.timeLabel == "01:30")
      clock.togglePause()
      f.advance(600)
      let restored = f.model().utilityClock
      #expect(restored.phase == .paused && restored.seconds == 89.5)
      restored.togglePause()
      f.advance(90)
      restored.refresh()
      #expect(restored.phase == .completed && restored.timeLabel == "00:00")
      #expect(f.model().utilityClock.phase == .completed)
      restored.reset()
      #expect(restored.phase == .idle && restored.seconds == 120)
    }

    @Test("G01.07 stopwatch precision, hours, reset and expired countdown preserve focus rounds")
    func stopwatch() throws {
      let f = try CoreTimerFixture()
      defer { f.cleanup() }
      let model = f.model()
      let clock = model.utilityClock
      let savedCount = model.completedSessions
      clock.start(.stopwatch)
      f.advance(12.3)
      clock.refresh()
      #expect(abs(clock.seconds - 12.3) < 0.001)
      clock.togglePause()
      f.advance(600)
      let paused = f.model().utilityClock
      #expect(paused.phase == .paused && abs(paused.seconds - 12.3) < 0.001)
      paused.togglePause()
      f.advance(3.7)
      let restored = f.model().utilityClock
      #expect(restored.isRunning && abs(restored.seconds - 16) < 0.001)
      f.advance(3600)
      restored.refresh()
      #expect(restored.timeLabel == "01:00:16.0")
      restored.reset()
      #expect(restored.timeLabel == "00:00.0")
      #expect(f.model().completedSessions == savedCount)
      restored.start(.timer, minutes: 1)
      f.advance(65)
      #expect(f.model().utilityClock.phase == .completed && f.model().utilityClock.seconds == 0)
    }
  }
}
