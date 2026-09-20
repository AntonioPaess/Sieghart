import Foundation
import SwiftUI

enum PomodoroPhase: Equatable {
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

    @Published private(set) var pomodoroPhase: PomodoroPhase = .idle
    @Published private(set) var remainingSeconds = AssistantViewModel.focusDuration
    @Published private(set) var lastAction = "Waiting for an action"
    @Published private(set) var impactCount = 0

    private var endDate: Date?
    private var refreshTimer: Timer?

    var pomodoroTimeLabel: String {
        let totalSeconds = max(0, Int(remainingSeconds.rounded(.up)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
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

    func resetPomodoro() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        endDate = nil
        pomodoroPhase = .idle
        remainingSeconds = Self.focusDuration
        lastAction = "Pomodoro reset"
    }

    private func startPomodoro() {
        if pomodoroPhase == .completed || remainingSeconds <= 0 {
            remainingSeconds = Self.focusDuration
        }

        endDate = Date().addingTimeInterval(remainingSeconds)
        pomodoroPhase = .focusing
        scheduleRefresh()
    }

    private func pausePomodoro() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = nil
        endDate = nil
        pomodoroPhase = .paused
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
    }
}
