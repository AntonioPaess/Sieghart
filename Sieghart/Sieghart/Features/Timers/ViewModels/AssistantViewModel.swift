import Foundation
import Combine
import SwiftUI

@MainActor
final class AssistantViewModel: ObservableObject {
    static let defaultFocusMinutes = 25
    static let focusLengths = Array(stride(from: 5, through: 60, by: 5))
    static let shortBreakLengths = [5, 10, 15]
    static let longBreakLengths = [15, 20, 30]
    static let roundCounts = [2, 4, 6, 8]

    @Published private(set) var pomodoroPhase: PomodoroPhase = .idle
    @Published private(set) var interval: PomodoroInterval = .focus
    @Published private(set) var remainingSeconds: TimeInterval = 25 * 60
    @Published private(set) var focusMinutes = defaultFocusMinutes
    @Published private(set) var shortBreakMinutes = 5
    @Published private(set) var longBreakMinutes = 15
    @Published private(set) var sessionsPerCycle = 4
    @Published private(set) var autoStartBreaks = true
    @Published private(set) var completedSessions = 0
    @Published private(set) var cycleSessions = 0
    @Published private(set) var lastAction = "Ready when you are"
    @Published private(set) var impactCount = 0
    @Published private(set) var completionNotice: SessionCompletion?
    @Published private(set) var selectedTimerMode: TimerToolMode
    let utilityClock: UtilityClock
    private var clockObservation: AnyCancellable?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let schedulesTimer: Bool
    private var endDate: Date?
    private var refreshTimer: Timer?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, schedulesTimer: Bool = true) {
        self.defaults = defaults
        self.now = now
        self.schedulesTimer = schedulesTimer
        selectedTimerMode = TimerToolMode(rawValue: defaults.string(forKey: "timerTools.selection") ?? "") ?? .timer
        utilityClock = UtilityClock(defaults: defaults, now: now, schedulesTimer: schedulesTimer)
        focusMinutes = Self.savedChoice("focusMinutes", choices: Self.focusLengths, fallback: 25, defaults: defaults)
        shortBreakMinutes = Self.savedChoice("shortBreakMinutes", choices: Self.shortBreakLengths, fallback: 5, defaults: defaults)
        longBreakMinutes = Self.savedChoice("longBreakMinutes", choices: Self.longBreakLengths, fallback: 15, defaults: defaults)
        sessionsPerCycle = Self.savedChoice("sessionsPerCycle", choices: Self.roundCounts, fallback: 4, defaults: defaults)
        autoStartBreaks = defaults.object(forKey: "pomodoro.autoStartBreaks") as? Bool ?? true
        completedSessions = max(0, defaults.integer(forKey: "pomodoro.completedSessions"))
        cycleSessions = min(max(0, defaults.integer(forKey: "pomodoro.cycleSessions")), sessionsPerCycle)
        interval = PomodoroInterval(rawValue: defaults.string(forKey: "pomodoro.interval") ?? "") ?? .focus
        remainingSeconds = intervalDuration
        restorePomodoro()
        clockObservation = utilityClock.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var isRunning: Bool { pomodoroPhase == .focusing }
    var hasActiveSession: Bool { isRunning || pomodoroPhase == .paused }
    var hasTimerActivity: Bool { hasActiveSession || utilityClock.hasSession }
    var activeTimerMode: TimerToolMode {
        if utilityClock.hasSession && selectedTimerMode == utilityClock.mode { return utilityClock.mode }
        return hasActiveSession ? .pomodoro : utilityClock.mode
    }
    var compactTimeLabel: String { activeTimerMode == .pomodoro ? pomodoroTimeLabel : utilityClock.timeLabel }

    func selectTimerMode(_ mode: TimerToolMode) {
        selectedTimerMode = mode
        defaults.set(mode.rawValue, forKey: "timerTools.selection")
    }
    var sessionNumber: Int { min(cycleSessions + 1, sessionsPerCycle) }
    var nextBreak: PomodoroInterval { cycleSessions >= sessionsPerCycle ? .longBreak : .shortBreak }
    var nextBreakMinutes: Int { nextBreak == .longBreak ? longBreakMinutes : shortBreakMinutes }
    var intervalDuration: TimeInterval {
        TimeInterval((interval == .focus ? focusMinutes : interval == .shortBreak ? shortBreakMinutes : longBreakMinutes) * 60)
    }
    var activityTitle: String {
        pomodoroPhase == .paused ? "Paused" : pomodoroPhase == .completed ? "\(interval.title) complete" : interval.title
    }
    var sessionCaption: String {
        interval == .focus ? "Session \(sessionNumber) of \(sessionsPerCycle)" : "You earned this."
    }
    var pomodoroTimeLabel: String {
        let seconds = max(0, Int(remainingSeconds.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var pomodoroProgress: Double { min(max(remainingSeconds / intervalDuration, 0), 1) }
    var pomodoroButtonLabel: String {
        isRunning ? "Pause timer" : pomodoroPhase == .paused ? "Resume timer" : "Start focus"
    }

    func registerImpact(_ impact: ImpactEvent) {
        impactCount += 1
        lastAction = "Impact received"
    }

    func handle(impact: ImpactEvent) { registerImpact(impact); togglePomodoro() }

    func togglePomodoro() {
        if isRunning { pausePomodoro() }
        else if pomodoroPhase == .paused { runTimer() }
        else { startFocusSession() }
    }

    func startPomodoroFromGesture() {
        if pomodoroPhase == .paused { runTimer() }
        else if !isRunning { startFocusSession() }
    }

    func pausePomodoroFromGesture() { if isRunning { pausePomodoro() } }

    func setFocusMinutes(_ minutes: Int) {
        guard Self.focusLengths.contains(minutes), minutes != focusMinutes else { return }
        focusMinutes = minutes
        resetPomodoro()
    }

    func startFocusSession(minutes: Int? = nil, shortBreak: Int? = nil, longBreak: Int? = nil, rounds: Int? = nil, autoBreak: Bool? = nil) {
        selectTimerMode(.pomodoro)
        if let minutes, Self.focusLengths.contains(minutes) { focusMinutes = minutes }
        if let shortBreak, Self.shortBreakLengths.contains(shortBreak) { shortBreakMinutes = shortBreak }
        if let longBreak, Self.longBreakLengths.contains(longBreak) { longBreakMinutes = longBreak }
        if let rounds, Self.roundCounts.contains(rounds) { sessionsPerCycle = rounds }
        if let autoBreak { autoStartBreaks = autoBreak }
        if cycleSessions >= sessionsPerCycle { cycleSessions = 0 }
        interval = .focus
        remainingSeconds = intervalDuration
        runTimer()
    }

    func startBreak() {
        guard pomodoroPhase == .completed, interval == .focus else { return }
        interval = nextBreak
        remainingSeconds = intervalDuration
        runTimer()
    }

    func resetPomodoro() {
        stopTimer()
        interval = .focus
        remainingSeconds = intervalDuration
        pomodoroPhase = .idle
        lastAction = "Ready for a new focus session"
        persistPomodoro()
    }

    func finishPomodoroFromWidget() {
        guard hasActiveSession else { return }
        completeInterval(allowAutomaticBreak: false)
    }

    private func runTimer() {
        endDate = now().addingTimeInterval(remainingSeconds)
        pomodoroPhase = .focusing
        lastAction = "\(interval.title) started"
        persistPomodoro()
        scheduleRefresh()
    }

    private func pausePomodoro() {
        refresh()
        // An elapsed focus interval may have just started an automatic break.
        guard isRunning else { return }
        stopTimer()
        pomodoroPhase = .paused
        lastAction = "\(interval.title) paused"
        persistPomodoro()
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        endDate = nil
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        guard schedulesTimer else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    // Internal so the deadline and restoration transitions can be verified without launching UI.
    func refresh() {
        guard let endDate, isRunning else { return }
        remainingSeconds = max(0, endDate.timeIntervalSince(now()))
        if remainingSeconds <= 0 { completeInterval(allowAutomaticBreak: true) }
    }

    private func completeInterval(allowAutomaticBreak: Bool) {
        stopTimer()
        remainingSeconds = 0
        if interval == .focus {
            completedSessions += 1
            cycleSessions = min(cycleSessions + 1, sessionsPerCycle)
        } else if interval == .longBreak {
            cycleSessions = 0
        }
        pomodoroPhase = .completed
        lastAction = "\(interval.title) completed"
        persistPomodoro()
        completionNotice = SessionCompletion(interval: interval, completedSessions: completedSessions, automaticBreakMinutes: interval == .focus && allowAutomaticBreak && autoStartBreaks ? nextBreakMinutes : nil)
        if interval == .focus, allowAutomaticBreak, autoStartBreaks { startBreak() }
    }

    private func restorePomodoro() {
        guard let raw = defaults.string(forKey: "pomodoro.phase"), let phase = PomodoroPhase(rawValue: raw) else { return }
        switch phase {
        case .focusing:
            guard let savedEnd = defaults.object(forKey: "pomodoro.endDate") as? Date else { return }
            endDate = savedEnd
            pomodoroPhase = .focusing
            remainingSeconds = max(0, savedEnd.timeIntervalSince(now()))
            if remainingSeconds > 0 { scheduleRefresh() }
            else {
                // A timer that expired while the app was closed finishes once.
                // Wait for the user before starting a new interval after relaunch.
                completeInterval(allowAutomaticBreak: false)
            }
        case .paused:
            remainingSeconds = min(max(defaults.double(forKey: "pomodoro.remainingSeconds"), 0), intervalDuration)
            pomodoroPhase = .paused
        case .completed:
            remainingSeconds = 0
            pomodoroPhase = .completed
        case .idle:
            interval = .focus
            remainingSeconds = intervalDuration
        }
    }

    private func persistPomodoro() {
        defaults.set(pomodoroPhase.rawValue, forKey: "pomodoro.phase")
        defaults.set(interval.rawValue, forKey: "pomodoro.interval")
        defaults.set(focusMinutes, forKey: "pomodoro.focusMinutes")
        defaults.set(shortBreakMinutes, forKey: "pomodoro.shortBreakMinutes")
        defaults.set(longBreakMinutes, forKey: "pomodoro.longBreakMinutes")
        defaults.set(sessionsPerCycle, forKey: "pomodoro.sessionsPerCycle")
        defaults.set(autoStartBreaks, forKey: "pomodoro.autoStartBreaks")
        defaults.set(completedSessions, forKey: "pomodoro.completedSessions")
        defaults.set(cycleSessions, forKey: "pomodoro.cycleSessions")
        defaults.set(remainingSeconds, forKey: "pomodoro.remainingSeconds")
        if let endDate { defaults.set(endDate, forKey: "pomodoro.endDate") }
        else { defaults.removeObject(forKey: "pomodoro.endDate") }
    }

    private static func savedChoice(_ name: String, choices: [Int], fallback: Int, defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: "pomodoro.\(name)")
        return choices.contains(value) ? value : fallback
    }
}
