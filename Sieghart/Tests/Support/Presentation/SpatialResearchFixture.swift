import Foundation

struct SpatialResearchFixture: ResearchProviding {
    func research(topic: String, language: String) async throws -> ResearchArtifact {
        ResearchArtifact(topic: topic, title: "Fixture references", summary: "Explicit test-provider result",
            bulletPoints: ["First", "Second", "Third"],
            sources: [.init(title: "Swift", url: URL(string: "https://www.swift.org/documentation/")!, excerpt: "Documentation")])
    }
}
