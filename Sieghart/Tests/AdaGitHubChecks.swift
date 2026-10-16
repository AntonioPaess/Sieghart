import Foundation

private actor AdaGitHubFixtureCredentials: AdaGitHubCredentialStoring {
    var token: String?
    var loads = 0, saves = 0, clears = 0
    init(token: String? = nil) { self.token = token }
    func load() -> String? { loads += 1; return token }
    func save(_ token: String) { saves += 1; self.token = token }
    func clear() { clears += 1; token = nil }
}

private actor AdaGitHubFixtureTransport: AdaGitHubTransport {
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
        let url = request.url!
        return .init(statusCode: statusCode, data: responses[url.path] ?? Data(), url: redirectedURL ?? url)
    }
}

private final class AdaGitHubFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance() { lock.lock(); date += 61; lock.unlock() }
}

/// Fixtures use only injected memory credentials and transport. Never real accounts or URLSession.
enum AdaGitHubChecks {
    private static let token = "github_pat_" + String(repeating: "x", count: 64)

    static func run() async throws {
        try await connectionChecks()
        try await errorChecks()
        try await cancellationChecks()
        try await chatRestoreChecks()
        print("PASS: Coucou-style Ada GitHub connection, snapshot, cache, bounds, cancellation and isolation. No network or Keychain reads.")
    }

    @MainActor private static func chatRestoreChecks() async throws {
        let credentials = AdaGitHubFixtureCredentials(token: token)
        let transport = AdaGitHubFixtureTransport(responses: try responses())
        let service = AdaGitHubContext(transport: transport, credentials: credentials)
        let connection = AdaGitHubViewModel(service: service)
        let chat = LocalChatViewModel(generator: UnavailableLocalChatEngine(), github: connection)
        let initialLoads = await credentials.loads
        precondition(initialLoads == 0 && !connection.status.connected)
        await chat.prepare()
        precondition(connection.status.connected && connection.status.login == "fixture-user")
        await chat.prepare()
        let loads = await credentials.loads, firstRequests = await transport.requests
        precondition(loads == 1 && firstRequests.count == 1)
        await connection.disconnect(); await chat.prepare()
        let finalRequests = await transport.requests
        precondition(!connection.status.connected && finalRequests.count == firstRequests.count)
        chat.shutdown()
    }

    private static func connectionChecks() async throws {
        let credentials = AdaGitHubFixtureCredentials()
        let transport = AdaGitHubFixtureTransport(responses: try responses())
        let clock = AdaGitHubFixtureClock()
        let context = AdaGitHubContext(transport: transport, credentials: credentials, now: { clock.now() })
        let initial = await context.status(), loads = await credentials.loads, requests = await transport.requests
        precondition(!initial.connected && initial.snapshot == nil && loads == 0 && requests.isEmpty)
        let disconnected = await context.answer()
        precondition(disconnected.contains("Connect GitHub"))
        do {
            let requests = await transport.requests
            precondition(requests.isEmpty)
        }
        try await context.restore()
        try await context.restore()
        let restoreLoads = await credentials.loads, restoreRequests = await transport.requests
        precondition(restoreLoads == 1 && restoreRequests.isEmpty)
        for value in ["", "short", "\(token)\n", "bearer \(token)", "https://github.com/token", String(repeating: "x", count: 256)] {
            try await expect(.invalidToken) { try await context.connect(token: value) }
        }
        try await context.connect(token: token)
        let connected = await context.status(), saved = await credentials.token
        precondition(connected.connected && connected.login == "fixture-user" && connected.snapshot == nil && saved == token)
        try await context.refresh()
        let ready = await context.status()
        precondition(ready.snapshot?.repositoryCount == 5 && ready.snapshot?.stars == 42)
        precondition(ready.snapshot?.myPRs.first?.ci == "failure" && ready.snapshot?.reviewCount == 1)
        precondition(ready.snapshot?.defaultBranchCI.first?.ci == "success")
        let answer = await context.answer(), firstRequests = await transport.requests
        precondition(firstRequests.count == 4 && answer.contains("fixture-user") && answer.contains("owner/project#7"))
        precondition(answer.contains("failure") && answer.contains("maximum 100") && !answer.contains(token))
        precondition(answer.utf8.count <= AdaGitHubContext.maximumOutputBytes)
        let ci = await context.answer(topic: "ci")
        precondition(ci.contains("Default-branch CI") && !ci.contains("Stars:"))
        clock.advance()
        _ = await context.answer()
        let afterTTL = await transport.requests
        precondition(afterTTL.count == 7)
        _ = await context.answer(topic: "edit_code")
        let afterUnknown = await transport.requests
        precondition(afterUnknown.count == 7)
        for request in afterTTL {
            precondition(request.url?.host == "api.github.com" && request.url?.scheme == "https")
            precondition(["/user", "/user/repos", "/graphql"].contains(request.url!.path))
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
            if request.url?.path == "/graphql" {
                precondition(request.httpMethod == "POST")
                let body = String(data: request.httpBody!, encoding: .utf8)!
                precondition(body.contains("query") && !body.contains("mutation") && !body.contains(token))
            } else { precondition(request.httpMethod == "GET" && request.httpBody == nil) }
        }
        try await context.disconnect()
        let empty = await context.status(), cleared = await credentials.token
        precondition(!empty.connected && empty.login == nil && empty.snapshot == nil && cleared == nil)
        let count = afterTTL.count
        _ = await context.answer()
        let finalRequests = await transport.requests
        precondition(finalRequests.count == count)

        let restoredCredentials = AdaGitHubFixtureCredentials(token: token)
        let restoredContext = AdaGitHubContext(transport: transport, credentials: restoredCredentials)
        let beforeRestore = await restoredCredentials.loads
        precondition(beforeRestore == 0)
        try await restoredContext.restore()
        let restoredStatus = await restoredContext.status(), restores = await restoredCredentials.loads, saves = await restoredCredentials.saves
        precondition(restoredStatus.connected && restores == 1 && saves == 0)
    }

    private static func errorChecks() async throws {
        let credentials = AdaGitHubFixtureCredentials()
        let transport = AdaGitHubFixtureTransport(responses: try responses())
        let context = AdaGitHubContext(transport: transport, credentials: credentials)
        await transport.set(status: 302)
        try await expect(.redirectDenied) { try await context.connect(token: token) }
        await transport.set(status: 200, redirectedURL: URL(string: "https://evil.example/user")!)
        try await expect(.redirectDenied) { try await context.connect(token: token) }
        await transport.set(status: 401)
        try await expect(.accessUnavailable) { try await context.connect(token: token) }
        await transport.set(status: 429)
        try await expect(.rateLimited) { try await context.connect(token: token) }
        await transport.set(status: 200)
        await transport.set(data: Data(repeating: 120, count: 131_073), for: "/user")
        try await expect(.responseTooLarge) { try await context.connect(token: token) }
        let saved = await credentials.saves, status = await context.status()
        precondition(saved == 0 && !status.connected)
        await transport.set(data: Data("not json".utf8), for: "/user")
        try await expect(.invalidResponse) { try await context.connect(token: token) }
        await transport.set(data: try responses()["/user"]!, for: "/user")
        try await context.connect(token: token)
        await transport.set(data: try json(["data": ["viewer": ["login": "other-user"]]]), for: "/graphql")
        try await expect(.invalidResponse) { try await context.refresh() }
        let failed = await context.status()
        precondition(failed.snapshot == nil && !failed.detail.contains(token))
        let longTitle = String(repeating: "🌱", count: 10_000)
        let large = try pulse(title: longTitle)
        // The body is below the transport cap, and the projected PR title must be capped.
        precondition(large.count < 131_072)
        await transport.set(data: large, for: "/graphql")
        try await context.refresh()
        let bounded = await context.answer()
        precondition(bounded.utf8.count <= AdaGitHubContext.maximumOutputBytes)
    }

    private static func cancellationChecks() async throws {
        let credentials = AdaGitHubFixtureCredentials()
        let transport = AdaGitHubFixtureTransport(responses: try responses())
        let context = AdaGitHubContext(transport: transport, credentials: credentials)
        await transport.setPaused(true)
        let connecting = Task { try await context.connect(token: token) }
        try await waitForRequest(transport)
        connecting.cancel()
        await transport.release()
        do { try await connecting.value; preconditionFailure("Cancellation ignored") } catch is CancellationError {}
        let saves = await credentials.saves
        precondition(saves == 0)
        try await context.connect(token: token)
        await transport.setPaused(true)
        let refreshing = Task { try await context.refresh() }
        for _ in 0..<100 {
            if await transport.waiting.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await expect(.busy) { try await context.refresh() }
        try await context.disconnect()
        await transport.release()
        do { try await refreshing.value; preconditionFailure("Disconnected request restored data") }
        catch { precondition(error is CancellationError || error as? AdaGitHubError == .superseded) }
        let final = await context.status(), stored = await credentials.token
        precondition(!final.connected && final.snapshot == nil && stored == nil)
    }

    private static func waitForRequest(_ transport: AdaGitHubFixtureTransport) async throws {
        for _ in 0..<100 {
            if await transport.requests.count > 0 { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("GitHub fixture did not receive a request")
    }
    private static func expect(_ expected: AdaGitHubError, _ action: () async throws -> Void) async throws {
        do { try await action(); preconditionFailure("Expected \(expected)") }
        catch { precondition(error as? AdaGitHubError == expected, "Unexpected fixture error") }
    }
    private static func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private static func responses() throws -> [String: Data] {
        ["/user": try json(["login": "fixture-user", "public_repos": 3, "owned_private_repos": 2]),
         "/user/repos": try json([["stargazers_count": 30], ["stargazers_count": 12]]),
         "/graphql": try pulse()]
    }
    private static func pulse(title: String = "Fix the build") throws -> Data {
        let repo: [String: Any] = ["nameWithOwner": "owner/project"]
        let pr: [String: Any] = ["number": 7, "title": title, "repository": repo, "isDraft": false,
            "reviewDecision": "REVIEW_REQUIRED", "commits": ["nodes": [["commit": ["statusCheckRollup": ["state": "FAILURE"]]]]]]
        let branch: [String: Any] = ["nameWithOwner": "owner/project", "isArchived": false,
            "defaultBranchRef": ["name": "main", "target": ["statusCheckRollup": ["state": "SUCCESS"]]]]
        return try json(["data": ["viewer": ["login": "fixture-user", "pullRequests": ["nodes": [pr]],
            "repositories": ["nodes": [branch]]], "reviewRequested": ["issueCount": 1, "nodes": [pr]]]])
    }
}
