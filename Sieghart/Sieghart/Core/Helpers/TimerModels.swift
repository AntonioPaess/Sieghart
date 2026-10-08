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
