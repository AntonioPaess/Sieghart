import AppKit
import Combine
import Foundation

/// Structured interactive artifact produced by the autonomous background research agent.
struct ResearchArtifact: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let topic: String
    let title: String
    let summary: String
    let bulletPoints: [String]
    let suggestedActions: [String]
    let completionCue: String
    let createdAt: Date
    var sources: [ResearchSource]? = nil
    var pagesRead: Int? = nil

    init(
        id: UUID = UUID(),
        topic: String,
        title: String,
        summary: String,
        bulletPoints: [String],
        suggestedActions: [String] = ["Abrir na Ada Room", "Copiar Resumo"],
        completionCue: String = "agent-done",
        createdAt: Date = Date(),
        sources: [ResearchSource]? = nil,
        pagesRead: Int? = nil
    ) {
        self.id = id
        self.topic = topic
        self.title = title
        self.summary = summary
        self.bulletPoints = bulletPoints
        self.suggestedActions = suggestedActions
        self.completionCue = completionCue
        self.createdAt = createdAt
        self.sources = sources
        self.pagesRead = pagesRead
    }

    var markdownRepresentation: String {
        let bullets = bulletPoints.map { "• \($0)" }.joined(separator: "\n")
        let references = (sources ?? []).enumerated().map { index, source in "[\(index+1). \(source.title)](\(source.url.absoluteString))" }.joined(separator: "\n")
        return """
        **\(title)**
        \(summary)

        \(bullets)

        \(references)
        """
    }
}

/// Background lookup with source-backed artifacts. Connection failures are
/// explicit; stored artifacts remain readable without another lookup.
@MainActor
final class BackgroundResearchAgent: ObservableObject {
    @Published private(set) var isResearching = false
    @Published private(set) var activeTopic: String?
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var statusStep: String = ""
    @Published private(set) var artifacts: [ResearchArtifact] = []
    @Published private(set) var latestArtifact: ResearchArtifact?
    @Published private(set) var lastCuePlayed: String?

    private let playsSoundCue: Bool
    private let provider: any ResearchProviding
    private var requestID = UUID()
    private var activeTask: Task<ResearchArtifact?, Never>?
    var onArtifactDelivered: (@MainActor (ResearchArtifact) -> Void)?
    var onFailure: (@MainActor (String) -> Void)?

    init(stepDelay: Duration = .milliseconds(180), playsSoundCue: Bool = false, provider: any ResearchProviding = UnavailableResearchProvider()) {
        self.playsSoundCue = playsSoundCue
        self.provider = provider
    }

    /// Detects whether a spoken or typed prompt requests an autonomous background research task.
    nonisolated static func parseResearchTopic(from transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        if normalized.range(of: #"\b(?:no|na|on|using)\s+google\b|\b(?:in the browser|no navegador)\b"#,options:.regularExpression) != nil { return nil }

        let prefixes = [
            "pesquise em segundo plano sobre ",
            "pesquise em segundo plano ",
            "pesquisar em segundo plano sobre ",
            "pesquisar em background sobre ",
            "pesquise em background ",
            "investigue em segundo plano ",
            "agente de pesquisa ",
            "research in background about ",
            "research in the background ",
            "background research on ",
            "deep research on ", "look up ", "research "
        ]
        for prefix in prefixes where normalized.hasPrefix(prefix) {
            if normalized.contains("no google") || normalized.contains("on google") || normalized.contains("in the browser") || normalized.contains("no navegador") { return nil }
            let topic = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !topic.isEmpty {
                return topic
            }
        }
        if SearchVoiceParser.hasSearchIntent(trimmed) { return SearchVoiceParser.query(in:trimmed) }
        return nil
    }

    @discardableResult
    func startResearch(topic: String, language: String = "pt-BR") async -> ResearchArtifact? {
        activeTask?.cancel()
        requestID = UUID()
        let id = requestID
        let cleanedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTopic.isEmpty else { return nil }

        isResearching = true
        activeTopic = cleanedTopic
        progress = 0.12
        statusStep = language.hasPrefix("en") ? "Finding sources…" : "Buscando fontes…"

        let task = Task<ResearchArtifact?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            let artifact: ResearchArtifact
            do { artifact = try await self.provider.research(topic: cleanedTopic, language: language, progress: { [weak self] message, value in
                await self?.receiveProgress(message, value:value, id:id)
            }) }
            catch {
                guard !Task.isCancelled, self.requestID == id else { return nil }
                self.isResearching = false; self.activeTopic = nil; self.progress = 0
                self.statusStep = language.hasPrefix("en") ? "Couldn't retrieve sources. Check your connection and try again." : "Não consegui consultar fontes. Confira a conexão e tente novamente."
                self.onFailure?(self.statusStep)
                return nil
            }
            guard !Task.isCancelled, self.requestID == id else { return nil }
            self.progress = 1.0
            self.isResearching = false
            self.activeTopic = nil
            self.statusStep = language.hasPrefix("en") ? "Completed" : "Concluído"
            self.latestArtifact = artifact
            self.artifacts.insert(artifact, at: 0)
            self.artifacts = Array(self.artifacts.prefix(20))
            self.emitCompletionCue()
            self.onArtifactDelivered?(artifact)
            return artifact
        }
        activeTask = task
        return await task.value
    }

    func cancel() {
        requestID = UUID()
        activeTask?.cancel()
        activeTask = nil
        isResearching = false
        activeTopic = nil
        progress = 0.0
        statusStep = ""
    }
    private func receiveProgress(_ message: String, value: Double, id: UUID) {
        guard requestID == id, isResearching else { return }
        statusStep = message; progress = min(0.95,max(0,value))
    }

    func dismissArtifact(_ id: UUID) {
        artifacts.removeAll { $0.id == id }
        if latestArtifact?.id == id {
            latestArtifact = artifacts.first
        }
    }

    private func emitCompletionCue() {
        lastCuePlayed = "agent-done"
        if playsSoundCue {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

}
