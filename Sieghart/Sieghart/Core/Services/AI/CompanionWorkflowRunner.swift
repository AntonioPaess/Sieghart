import Combine
import Foundation

struct CompanionWorkflowStep: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case specialist, research }
    var id = UUID()
    var kind: Kind = .specialist
    var persona: LocalChatPersona = .sig
    var request = ""
    var result: String? = nil
    var valid: Bool { !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && request.utf8.count <= 4000 && (result?.utf8.count ?? 0) <= 12_000 }
}

/// Sequential, user-reviewed steps. Completed results are checkpointed before
/// advancing. Resuming never repeats a completed step or grants desktop access.
@MainActor final class CompanionWorkflowRunner: ObservableObject {
    typealias Executor = @MainActor (CompanionWorkflowStep, String, String) async throws -> String
    @Published private(set) var activeID: UUID?
    let journal: CompanionTaskJournal
    var executor: Executor?
    private var task: Task<Void, Never>?
    init(journal: CompanionTaskJournal) { self.journal = journal }
    @discardableResult func start(title: String, steps: [CompanionWorkflowStep], language: String, resuming: UUID? = nil) throws -> UUID {
        guard activeID == nil else { throw LocalChatError.busy }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 500, (2...6).contains(steps.count), steps.allSatisfy(\.valid), Set(steps.map(\.id)).count == steps.count, executor != nil else { throw SpatialContentError.invalidContent }
        let id = journal.begin(kind: .workflow, request: title, language: language, resuming: resuming)
        activeID = id; journal.update(id, progress: language.hasPrefix("en") ? "Preparing steps…" : "Preparando as etapas…", workflow: steps)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.activeID == id { self.activeID = nil; self.task = nil } }
            var current = steps
            do {
                for index in current.indices where current[index].result == nil {
                    try Task.checkCancellation()
                    guard self.activeID == id, let execute = self.executor else { throw CancellationError() }
                    let status = "\(index+1)/\(current.count) · \(current[index].kind == .research ? (language.hasPrefix("en") ? "Research" : "Pesquisa") : current[index].persona.title)"
                    self.journal.update(id, progress: status, workflow: current)
                    let context = current.prefix(index).compactMap { step in step.result.map { "\(step.persona.title): \($0)" } }.joined(separator: "\n\n")
                    let reply = try await execute(current[index], String(context.suffix(5000)), language)
                    try Task.checkCancellation()
                    guard self.activeID == id, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reply.utf8.count <= 12_000 else { throw SpatialContentError.invalidContent }
                    current[index].result = reply
                    self.journal.update(id, progress: status, workflow: current)
                }
                let result = current.enumerated().map { "## \($0.offset+1). \($0.element.kind == .research ? "Pesquisa" : $0.element.persona.title)\n\n\($0.element.result ?? "")" }.joined(separator: "\n\n")
                self.journal.update(id, state: .completed, progress: language.hasPrefix("en") ? "All steps completed." : "Todas as etapas concluídas.", result: result, workflow: current)
            } catch {
                guard self.activeID == id else { return }
                self.journal.update(id, state: Task.isCancelled || error is CancellationError ? .paused : .failed,
                    progress: error.localizedDescription, workflow: current)
            }
        }
        return id
    }
    func cancel(_ id: UUID) {
        guard activeID == id else { return }
        task?.cancel(); task = nil; activeID = nil
        journal.update(id, state: .paused)
    }
    func shutdown() { if let activeID { cancel(activeID) } }
}
