import Foundation
import SwiftUI

enum ImpactAction: String, CaseIterable, Identifiable {
    case toggleCharacter
    case showCharacter
    case hideCharacter
    case startPomodoro
    case pausePomodoro
    case togglePomodoro
    case showCalendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleCharacter:
            return "Show or hide character"
        case .showCharacter:
            return "Show character"
        case .hideCharacter:
            return "Hide character"
        case .startPomodoro:
            return "Start Pomodoro"
        case .pausePomodoro:
            return "Pause Pomodoro"
        case .togglePomodoro:
            return "Start or pause Pomodoro"
        case .showCalendar:
            return "Show calendar"
        }
    }
}

@MainActor
final class ImpactGestureCoordinator: ObservableObject {
    @Published var singleImpactAction: ImpactAction {
        didSet { save(singleImpactAction, forKey: singleActionKey) }
    }

    @Published var doubleImpactAction: ImpactAction {
        didSet { save(doubleImpactAction, forKey: doubleActionKey) }
    }

    @Published var tripleImpactAction: ImpactAction {
        didSet { save(tripleImpactAction, forKey: tripleActionKey) }
    }

    private let assistant: AssistantViewModel
    private let notch: NotchWidgetController
    private var pendingImpactCount = 0
    private var sequenceTask: Task<Void, Never>?

    private let singleActionKey = "impact.action.single"
    private let doubleActionKey = "impact.action.double"
    private let tripleActionKey = "impact.action.triple"
    private let sequenceWindow: Duration = .milliseconds(480)

    init(assistant: AssistantViewModel, notch: NotchWidgetController) {
        self.assistant = assistant
        self.notch = notch
        singleImpactAction = Self.loadAction(forKey: singleActionKey, default: .toggleCharacter)
        doubleImpactAction = Self.loadAction(forKey: doubleActionKey, default: .togglePomodoro)
        tripleImpactAction = Self.loadAction(forKey: tripleActionKey, default: .showCalendar)
    }

    func receive(_ impact: ImpactEvent) {
        pendingImpactCount = min(3, pendingImpactCount + 1)
        sequenceTask?.cancel()

        sequenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: sequenceWindow)
            guard !Task.isCancelled else { return }

            let count = pendingImpactCount
            pendingImpactCount = 0
            apply(action: action(for: count))
        }
    }

    private func action(for count: Int) -> ImpactAction {
        switch count {
        case 1:
            return singleImpactAction
        case 2:
            return doubleImpactAction
        default:
            return tripleImpactAction
        }
    }

    private func apply(action: ImpactAction) {
        switch action {
        case .toggleCharacter:
            notch.handleImpact()
        case .showCharacter:
            notch.show()
        case .hideCharacter:
            notch.hide()
        case .startPomodoro:
            assistant.startPomodoroFromGesture()
            notch.show()
        case .pausePomodoro:
            assistant.pausePomodoroFromGesture()
            notch.show()
        case .togglePomodoro:
            assistant.togglePomodoro()
            notch.show()
        case .showCalendar:
            notch.showCalendar()
        }
    }

    private func save(_ action: ImpactAction, forKey key: String) {
        UserDefaults.standard.set(action.rawValue, forKey: key)
    }

    private static func loadAction(forKey key: String, default defaultAction: ImpactAction) -> ImpactAction {
        guard let rawValue = UserDefaults.standard.string(forKey: key),
              let action = ImpactAction(rawValue: rawValue)
        else {
            return defaultAction
        }
        return action
    }
}
