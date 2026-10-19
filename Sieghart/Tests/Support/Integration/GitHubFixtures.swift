import Foundation
import Testing

actor IntegrationGitHubCredentials: AdaGitHubCredentialStoring {
    var token: String?
    var loads = 0, saves = 0, clears = 0
    init(token: String? = nil) { self.token = token }
    func load() -> String? { loads += 1; return token }
    func save(_ token: String) { saves += 1; self.token = token }
    func clear() { clears += 1; token = nil }
}

actor IntegrationGitHubTransport: AdaGitHubTransport {
    var requests: [URLRequest] = []
    var responses: [String: Data]
    var statusCode = 200
    var redirectedURL: URL?
    var pause = false
    var waiting: [CheckedContinuation<Void, Never>] = []

    init(responses: [String: Data]) { self.responses = responses }
    func set(data: Data, for path: String) { responses[path] = data }
    func set(status: Int, redirectedURL: URL? = nil) { statusCode = status; self.redirectedURL = redirectedURL }
    func setPaused(_ value: Bool) { pause = value }
    func release() { let pending = waiting; waiting = []; pause = false; pending.forEach { $0.resume() } }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> AdaGitHubResponse {
        requests.append(request)
        if pause { await withCheckedContinuation { waiting.append($0) } }
        // Deliberately ignores cancellation: the service must still suppress stale data.
        let url = try #require(request.url)
        return .init(statusCode: statusCode, data: responses[url.path] ?? Data(), url: redirectedURL ?? url)
    }
}

final class IntegrationGitHubClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance() { lock.lock(); date += 61; lock.unlock() }
}


enum IntegrationGitHubPayloads {
    static func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    static func responses() throws -> [String: Data] {
        ["/user": try json(["login": "fixture-user", "public_repos": 3, "owned_private_repos": 2]),
         "/user/repos": try json([["stargazers_count": 30], ["stargazers_count": 12]]),
         "/graphql": try pulse()]
    }
    static func pulse(title: String = "Fix the build") throws -> Data {
        let repo: [String: Any] = ["nameWithOwner": "owner/project"]
        let pr: [String: Any] = ["number": 7, "title": title, "repository": repo, "isDraft": false,
            "reviewDecision": "REVIEW_REQUIRED", "commits": ["nodes": [["commit": ["statusCheckRollup": ["state": "FAILURE"]]]]]]
        let branch: [String: Any] = ["nameWithOwner": "owner/project", "isArchived": false,
            "defaultBranchRef": ["name": "main", "target": ["statusCheckRollup": ["state": "SUCCESS"]]]]
        return try json(["data": ["viewer": ["login": "fixture-user", "pullRequests": ["nodes": [pr]],
            "repositories": ["nodes": [branch]]], "reviewRequested": ["issueCount": 1, "nodes": [pr]]]])
    }
}
