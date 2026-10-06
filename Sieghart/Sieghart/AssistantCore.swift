import Foundation
import Combine
import SwiftUI

enum PomodoroPhase: String, Equatable {
    case idle, focusing, paused, completed

    var title: String {
        switch self {
        case .idle: "Ready to focus"
        case .focusing: "Focusing"
        case .paused: "Paused"
        case .completed: "Completed"
        }
    }
}

enum TimerToolMode: String, CaseIterable {
    case timer, pomodoro, stopwatch
    var title: String { switch self { case .timer: "Timer"; case .pomodoro: "Pomodoro"; case .stopwatch: "Stopwatch" } }
    var symbol: String { switch self { case .timer: "timer"; case .pomodoro: "leaf"; case .stopwatch: "stopwatch" } }
}

enum UtilityClockPhase: String { case idle, running, paused, completed }

// A countdown and an elapsed clock have different time semantics. Both use
// saved dates, so sleep and relaunch do not depend on how many ticks arrived.
@MainActor final class UtilityClock: ObservableObject {
    @Published private(set) var mode: TimerToolMode = .timer
    @Published private(set) var phase: UtilityClockPhase = .idle
    @Published private(set) var seconds: TimeInterval = 15 * 60
    @Published private(set) var timerMinutes = 15
    private let defaults: UserDefaults
    private let now: () -> Date
    private let schedulesTimer: Bool
    private var deadline: Date?
    private var startedAt: Date?
    private var elapsedBeforeStart: TimeInterval = 0
    private var ticker: Timer?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, schedulesTimer: Bool = true) {
        self.defaults = defaults; self.now = now; self.schedulesTimer = schedulesTimer
        let minutes = defaults.integer(forKey: "utilityClock.minutes")
        timerMinutes = (1...180).contains(minutes) ? minutes : 15
        mode = TimerToolMode(rawValue: defaults.string(forKey: "utilityClock.mode") ?? "") == .stopwatch ? .stopwatch : .timer
        phase = UtilityClockPhase(rawValue: defaults.string(forKey: "utilityClock.phase") ?? "") ?? .idle
        seconds = mode == .timer ? Double(timerMinutes * 60) : 0
        if phase == .running {
            deadline = defaults.object(forKey: "utilityClock.deadline") as? Date
            startedAt = defaults.object(forKey: "utilityClock.startedAt") as? Date
            elapsedBeforeStart = max(0, defaults.double(forKey: "utilityClock.elapsed"))
            if (mode == .timer && deadline == nil) || (mode == .stopwatch && startedAt == nil) { reset() }
            else { refresh(); if phase == .running { schedule() } }
        } else if phase == .paused || phase == .completed {
            let saved = defaults.double(forKey: "utilityClock.seconds")
            seconds = saved.isFinite ? max(0, saved) : 0
            if mode == .timer { seconds = min(seconds, Double(timerMinutes * 60)) }
        }
    }

    var hasSession: Bool { phase == .running || phase == .paused }
    var isRunning: Bool { phase == .running }
    var timeLabel: String {
        let value = mode == .timer ? seconds.rounded(.up) : seconds.rounded(.down)
        let total = Int(max(0, min(value, Double(Int.max / 100))))
        let time = total >= 3600 ? String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60)
        return mode == .stopwatch ? time + String(format: ".%01d", Int((seconds * 10).rounded(.down)) % 10) : time
    }
    var progress: Double { min(1, max(0, seconds / Double(timerMinutes * 60))) }

    func setMinutes(_ minutes: Int) {
        guard (1...180).contains(minutes) else { return }
        timerMinutes = minutes
        if mode == .timer && phase == .idle { seconds = Double(minutes * 60) }
        persist()
    }

    func start(_ mode: TimerToolMode, minutes: Int? = nil) {
        guard mode != .pomodoro else { return }
        stopTicker(); self.mode = mode
        if let minutes, (1...180).contains(minutes) { timerMinutes = minutes }
        seconds = mode == .timer ? Double(timerMinutes * 60) : 0
        elapsedBeforeStart = 0
        resume()
    }

    func togglePause() {
        if phase == .running {
            refresh()
            guard phase == .running else { return }
            stopTicker(); deadline = nil; startedAt = nil; phase = .paused; persist()
        } else if phase == .paused { resume() }
    }

    func reset() {
        stopTicker(); deadline = nil; startedAt = nil; elapsedBeforeStart = 0
        seconds = mode == .timer ? Double(timerMinutes * 60) : 0
        phase = .idle; persist()
    }

    func refresh() {
        guard phase == .running else { return }
        if mode == .timer, let deadline {
            seconds = max(0, deadline.timeIntervalSince(now()))
            if seconds == 0 { stopTicker(); self.deadline = nil; phase = .completed; persist() }
        } else if mode == .stopwatch, let startedAt {
            seconds = elapsedBeforeStart + max(0, now().timeIntervalSince(startedAt))
        }
    }

    private func resume() {
        if mode == .timer { deadline = now().addingTimeInterval(seconds) }
        else { elapsedBeforeStart = seconds; startedAt = now() }
        phase = .running; persist(); schedule()
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }
    private func schedule() {
        stopTicker(); guard schedulesTimer else { return }
        let timer = Timer(timeInterval: mode == .stopwatch ? 0.1 : 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common); ticker = timer
    }
    private func persist() {
        defaults.set(mode.rawValue, forKey: "utilityClock.mode")
        defaults.set(phase.rawValue, forKey: "utilityClock.phase")
        defaults.set(timerMinutes, forKey: "utilityClock.minutes")
        defaults.set(seconds, forKey: "utilityClock.seconds")
        defaults.set(elapsedBeforeStart, forKey: "utilityClock.elapsed")
        if let deadline { defaults.set(deadline, forKey: "utilityClock.deadline") } else { defaults.removeObject(forKey: "utilityClock.deadline") }
        if let startedAt { defaults.set(startedAt, forKey: "utilityClock.startedAt") } else { defaults.removeObject(forKey: "utilityClock.startedAt") }
    }
}

enum PomodoroInterval: String, Equatable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }
}

struct SessionCompletion: Equatable {
    let id = UUID()
    let interval: PomodoroInterval
    let completedSessions: Int
    let automaticBreakMinutes: Int?
}

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
