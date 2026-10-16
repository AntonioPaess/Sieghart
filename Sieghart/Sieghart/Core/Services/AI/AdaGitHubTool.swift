import Foundation
import FoundationModels

@available(macOS 27.0, *)
private actor AdaToolBudget {
    private var remaining = 3
    func consume() -> Bool { guard remaining > 0 else { return false }; remaining -= 1; return true }
}

@available(macOS 27.0, *)
struct AdaGitHubTool: Tool {
    let name = "github_context"
    let description = "Read real GitHub account data from Sieg's configured connection: repositories, stars, own pull requests, requested reviews and default-branch CI. Also reports when GitHub is disconnected. Read only; never modifies GitHub."
    let context: AdaGitHubContext
    private let budget = AdaToolBudget()
    @Generable struct Arguments {
        @Guide(description: "One of github, repositories, stars, prs, reviews, ci")
        var topic: String
    }
    func call(arguments: Arguments) async throws -> String {
        try Task.checkCancellation()
        guard await budget.consume() else { return "GitHub tool limit reached for this reply. Use the results already returned, or ask the user for a focused follow-up." }
        let answer = await context.answer(topic: arguments.topic)
        try Task.checkCancellation()
        guard answer.utf8.count > 4_000 else { return answer }
        let bytes = Array(answer.utf8.prefix(3_800))
        return String(decoding: bytes, as: UTF8.self) + "\n[Snapshot shortened. Ask for prs, reviews, ci, stars or repositories separately for more focused information.]"
    }
}
