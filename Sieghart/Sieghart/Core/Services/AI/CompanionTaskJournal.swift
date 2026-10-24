import Foundation
import Combine

struct WalkthroughCheckpoint: Codable, Equatable, Sendable {
    let plan: ScreenGuidancePlan
    let index: Int
    var valid: Bool { (try? plan.validated()) != nil && plan.steps.indices.contains(index) }
}

struct CompanionTaskRecord: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case research, canvas, guidance, specialist, workflow }
    enum State: String, Codable, Sendable { case running, paused, completed, failed }
    let id: UUID
    let kind: Kind
    let request: String
    let language: String
    let createdAt: Date
    var updatedAt: Date
    var state: State
    var progress: String
    var result: String
    var guidance: WalkthroughCheckpoint? = nil
    var workflow: [CompanionWorkflowStep]? = nil

    var fullResult: String {
        guard let workflow, state == .completed else { return result }
        return workflow.enumerated().map { "## \($0.offset+1). \($0.element.kind == .research ? (language.hasPrefix("en") ? "Research" : "Pesquisa") : $0.element.persona.title)\n\n\($0.element.result ?? "")" }.joined(separator: "\n\n")
    }
    var canResume: Bool { state == .paused || state == .failed }
    func stateTitle(english: Bool) -> String {
        switch state {
        case .running: return english ? "Working" : "Em andamento"
        case .paused: return english ? "Paused" : "Pausada"
        case .completed: return english ? "Completed" : "Concluída"
        case .failed: return english ? "Needs attention" : "Precisa de atenção"
        }
    }
}

/// Persists requests and receipts, never live captures or executable commands.
/// A restart pauses unfinished work; only a fresh user action resumes it.
@MainActor final class CompanionTaskJournal: ObservableObject {
    @Published private(set) var tasks: [CompanionTaskRecord] = []
    @Published private(set) var storageIssue: String?
    private let defaults: UserDefaults?
    private let key = "sieg.tasks.v1"
    static let maximumBytes = 1_500_000

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        guard let data = defaults?.data(forKey: key) else { return }
        guard data.count <= Self.maximumBytes, let saved = try? JSONDecoder().decode([CompanionTaskRecord].self, from: data),
              saved.count <= 30, Set(saved.map(\.id)).count == saved.count,
              saved.allSatisfy({ !$0.request.isEmpty && $0.request.utf8.count <= 8000 && $0.result.utf8.count <= 30_000 && ($0.guidance?.valid ?? true) && ($0.workflow.map { (2...6).contains($0.count) && $0.allSatisfy(\.valid) } ?? true) }) else {
            storageIssue = "Saved tasks couldn't be read. The original data was preserved."; return
        }
        tasks = saved.map { task in
            var value = task
            if value.state == .running { value.state = .paused }
            return value
        }
        persist()
    }

    @discardableResult func begin(kind: CompanionTaskRecord.Kind, request: String, language: String, resuming: UUID? = nil) -> UUID {
        if let resuming, let index = tasks.firstIndex(where: { $0.id == resuming && $0.canResume }) {
            tasks[index].state = .running; tasks[index].updatedAt = Date(); persist(); return resuming
        }
        let record = CompanionTaskRecord(id: UUID(), kind: kind, request: Self.bounded(request, bytes: 8000), language: language,
            createdAt: Date(), updatedAt: Date(), state: .running, progress: "", result: "")
        // Retain active/paused work preferentially when the journal fills up.
        if tasks.count >= 30 {
            if let index = tasks.lastIndex(where: { $0.state == .completed || $0.state == .failed }) { tasks.remove(at: index) }
            else { tasks.removeLast() }
        }
        tasks.insert(record, at: 0); persist(); return record.id
    }
    func update(_ id: UUID, state: CompanionTaskRecord.State? = nil, progress: String? = nil, result: String? = nil, guidance: WalkthroughCheckpoint? = nil, workflow: [CompanionWorkflowStep]? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let workflow, (2...6).contains(workflow.count), workflow.allSatisfy(\.valid) { tasks[index].workflow = workflow }
        if let guidance, guidance.valid { tasks[index].guidance = guidance }
        if let state { tasks[index].state = state }
        if let progress { tasks[index].progress = Self.bounded(progress, bytes: 1000) }
        if let result { tasks[index].result = Self.bounded(result, bytes: 30_000) }
        tasks[index].updatedAt = Date(); persist()
    }
    func pauseRunning() {
        for index in tasks.indices where tasks[index].state == .running { tasks[index].state = .paused; tasks[index].updatedAt = Date() }
        persist()
    }
    private func persist() {
        guard let defaults, storageIssue == nil else { return }
        guard let data = try? JSONEncoder().encode(tasks), data.count <= Self.maximumBytes else {
            storageIssue = "Task history is full. Existing saved tasks were preserved."; return
        }
        defaults.set(data, forKey: key)
    }
    private static func bounded(_ text: String, bytes: Int) -> String {
        var result = String(text.prefix(bytes))
        while result.utf8.count > bytes { result.removeLast() }
        return result
    }
}
