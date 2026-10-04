import Foundation
import SwiftUI

enum PomodoroPhase: String, Equatable {
    case idle
    case focusing
    case paused
    case completed

    var title: String {
        switch self {
        case .idle:
            return "Ready to focus"
        case .focusing:
            return "Focusing"
        case .paused:
            return "Paused"
        case .completed:
            return "Completed"
        }
    }
}

@MainActor
final class AssistantViewModel: ObservableObject {
    static let focusDuration: TimeInterval = 25 * 60

    private enum StorageKey {
        static let phase = "pomodoro.phase"
        static let remaining = "pomodoro.remainingSeconds"
        static let endDate = "pomodoro.endDate"
    }

    @Published private(set) var pomodoroPhase: PomodoroPhase = .idle
    @Published private(set) var remainingSeconds = AssistantViewModel.focusDuration
    @Published private(set) var lastAction = "Waiting for an action"
    @Published private(set) var impactCount = 0

    private var endDate: Date?
    private var refreshTimer: Timer?

    init() {
        restorePomodoro()
    }

    var pomodoroTimeLabel: String {
        let totalSeconds = max(0, Int(remainingSeconds.rounded(.up)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var pomodoroProgress: Double {
        min(max(remainingSeconds / Self.focusDuration, 0), 1)
    }

    var pomodoroButtonLabel: String {
        switch pomodoroPhase {
        case .focusing:
            return "Pause Pomodoro"
        case .paused:
            return "Resume Pomodoro"
        case .idle, .completed:
            return "Start Pomodoro"
        }
    }

    func registerImpact(_ impact: ImpactEvent) {
        impactCount += 1
        lastAction = "Impact detected — intensity \(impact.intensity.formatted(.number.precision(.fractionLength(2))))g"
    }

    func handle(impact: ImpactEvent) {
        impactCount += 1

        if pomodoroPhase == .focusing {
            pausePomodoro()
            lastAction = "Impact received — Pomodoro paused"
        } else {
            startPomodoro()
            lastAction = "Impact received — Pomodoro started"
        }
    }

    func togglePomodoro() {
        switch pomodoroPhase {
        case .focusing:
            pausePomodoro()
            lastAction = "Pomodoro paused"
        case .idle, .paused, .completed:
            startPomodoro()
            lastAction = "Pomodoro started"
        }
    }

    func startPomodoroFromGesture() {
        startPomodoro()
        lastAction = "Pomodoro started by gesture"
    }

    func pausePomodoroFromGesture() {
        guard pomodoroPhase == .focusing else {
            lastAction = "Pomodoro is not running"
            return
        }

        pausePomodoro()
        lastAction = "Pomodoro paused by gesture"
    }

    func resetPomodoro() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        endDate = nil
        pomodoroPhase = .idle
        remainingSeconds = Self.focusDuration
        lastAction = "Pomodoro reset"
        persistPomodoro()
    }

    func finishPomodoroFromWidget() {
        guard pomodoroPhase == .focusing || pomodoroPhase == .paused else { return }

        refreshTimer?.invalidate()
        refreshTimer = nil
        endDate = nil
        remainingSeconds = 0
        pomodoroPhase = .completed
        lastAction = "Pomodoro finished from widget"
        persistPomodoro()
    }

    private func startPomodoro() {
        if pomodoroPhase == .completed || remainingSeconds <= 0 {
            remainingSeconds = Self.focusDuration
        }

        endDate = Date().addingTimeInterval(remainingSeconds)
        pomodoroPhase = .focusing
        persistPomodoro()
        scheduleRefresh()
    }

    private func pausePomodoro() {
        refresh()
        guard pomodoroPhase == .focusing else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        endDate = nil
        pomodoroPhase = .paused
        persistPomodoro()
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let endDate else { return }

        remainingSeconds = max(0, endDate.timeIntervalSinceNow)
        guard remainingSeconds <= 0 else { return }

        refreshTimer?.invalidate()
        refreshTimer = nil
        self.endDate = nil
        pomodoroPhase = .completed
        lastAction = "Pomodoro completed"
        persistPomodoro()
    }

    private func restorePomodoro() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: StorageKey.phase),
              let storedPhase = PomodoroPhase(rawValue: raw) else { return }

        switch storedPhase {
        case .focusing:
            guard let storedEnd = defaults.object(forKey: StorageKey.endDate) as? Date else { return }
            remainingSeconds = max(0, storedEnd.timeIntervalSinceNow)
            if remainingSeconds > 0 {
                endDate = storedEnd
                pomodoroPhase = .focusing
                lastAction = "Pomodoro restored"
                scheduleRefresh()
            } else {
                pomodoroPhase = .completed
                lastAction = "Pomodoro completed while Sieghart was closed"
                persistPomodoro()
            }
        case .paused:
            remainingSeconds = min(max(defaults.double(forKey: StorageKey.remaining), 0), Self.focusDuration)
            pomodoroPhase = .paused
            lastAction = "Paused Pomodoro restored"
        case .completed:
            remainingSeconds = 0
            pomodoroPhase = .completed
        case .idle:
            break
        }
    }

    private func persistPomodoro() {
        let defaults = UserDefaults.standard
        defaults.set(pomodoroPhase.rawValue, forKey: StorageKey.phase)
        defaults.set(remainingSeconds, forKey: StorageKey.remaining)
        if let endDate {
            defaults.set(endDate, forKey: StorageKey.endDate)
        } else {
            defaults.removeObject(forKey: StorageKey.endDate)
        }
    }
}
