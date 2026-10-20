import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.spending, .localIntegration)) @MainActor
  struct LocalTokenReaderTests {
    @Test("G07.01 cumulative counters and cloned sessions do not count reasoning or cache twice")
    func codexCounters() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Sieghart.TokenChecks.\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: root) }
      let codex = root.appendingPathComponent(".codex/sessions/2026/10/05")
      let claude = root.appendingPathComponent(".claude/projects/example")
      try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
      func codexLine(_ input: Int, _ cache: Int, _ output: Int) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cache),\"output_tokens\":\(output),\"reasoning_output_tokens\":15}}}}"
      }
      let id = UUID().uuidString
      let log =
        codexLine(100, 30, 10) + "\n" + codexLine(200, 80, 40) + "\n" + codexLine(200, 80, 40)
        + "\n"
      try log.write(
        to: codex.appendingPathComponent("rollout-a-\(id).jsonl"), atomically: true, encoding: .utf8
      )
      try log.write(
        to: codex.appendingPathComponent("rollout-copy-\(id).jsonl"), atomically: true,
        encoding: .utf8)
      try (codexLine(50, 5, 20) + "\n").write(
        to: codex.appendingPathComponent("another.jsonl"), atomically: true, encoding: .utf8)
      let tokens = LocalTokenReader.read(
        .codex, home: root, codexHome: root.appendingPathComponent(".codex"))
      #expect(
        tokens
          == LocalTokenUsage(input: 250, cachedInput: 85, cacheCreation: 0, output: 60, sessions: 2)
      )
      #expect(tokens?.total == 310)  // No double counting cache or reasoning.
    }

    @Test("G07.02 latest Claude messages preserve cache creation and ignore users")
    func claudeCounters() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Sieghart.TokenChecks.\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: root) }
      let codex = root.appendingPathComponent(".codex/sessions/2026/10/05")
      let claude = root.appendingPathComponent(".claude/projects/example")
      try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
      func codexLine(_ input: Int, _ cache: Int, _ output: Int) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cache),\"output_tokens\":\(output),\"reasoning_output_tokens\":15}}}}"
      }
      let id = UUID().uuidString
      let log =
        codexLine(100, 30, 10) + "\n" + codexLine(200, 80, 40) + "\n" + codexLine(200, 80, 40)
        + "\n"
      try log.write(
        to: codex.appendingPathComponent("rollout-a-\(id).jsonl"), atomically: true, encoding: .utf8
      )
      try log.write(
        to: codex.appendingPathComponent("rollout-copy-\(id).jsonl"), atomically: true,
        encoding: .utf8)
      try (codexLine(50, 5, 20) + "\n").write(
        to: codex.appendingPathComponent("another.jsonl"), atomically: true, encoding: .utf8)
      let messages = [
        #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_read_input_tokens":50,"cache_creation_input_tokens":20,"output_tokens":10}}}"#,
        #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_read_input_tokens":50,"cache_creation_input_tokens":20,"output_tokens":30}}}"#,
        #"{"type":"user","message":{"id":"u1","content":"Must not count this","usage":{"input_tokens":999999}}}"#,
        #"{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":10,"output_tokens":5}}}"#,
      ].joined(separator: "\n")
      try messages.write(
        to: claude.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
      #expect(
        LocalTokenReader.read(.claude, home: root, codexHome: root.appendingPathComponent(".codex"))
          == LocalTokenUsage(
            input: 180, cachedInput: 50, cacheCreation: 20, output: 35, sessions: 1))
      #expect(
        LocalTokenReader.read(
          .codex, home: root.appendingPathComponent("absent"),
          codexHome: root.appendingPathComponent("absent/.codex")) == nil)
    }

    @Test("G07.03 Antigravity transcript counters traverse .system_generated logs and skip transcript_full")
    func antigravityCounters() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Sieghart.AntigravityTokenChecks.\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: root) }
      let convLogs = root.appendingPathComponent(
        ".gemini/antigravity/brain/conv-1/.system_generated/logs")
      try FileManager.default.createDirectory(at: convLogs, withIntermediateDirectories: true)
      let lines = [
        #"{"step_index":1,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-10-19T12:00:00Z","content":"hello"}"#,
        #"{"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-19T12:00:05Z","input_tokens":400,"cache_read_tokens":1200,"output_tokens":80}"#,
        #"{"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-19T12:00:05Z","input_tokens":400,"cache_read_tokens":1200,"output_tokens":150}"#,
        #"{"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-19T12:01:00Z","input_tokens":100,"cache_read_tokens":1500,"output_tokens":50}"#,
      ].joined(separator: "\n")
      try lines.write(
        to: convLogs.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
      // Must be ignored so tokens are not double-counted:
      try lines.write(
        to: convLogs.appendingPathComponent("transcript_full.jsonl"), atomically: true,
        encoding: .utf8)
      let usage = LocalTokenReader.read(.antigravity, home: root)
      #expect(
        usage
          == LocalTokenUsage(
            input: 3200, cachedInput: 2700, cacheCreation: 0, output: 200, sessions: 1)
      )
      #expect(usage?.total == 3400)
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let iso = ISO8601DateFormatter()
      let shortReset = iso.string(from: now.addingTimeInterval(2 * 3600))
      let weeklyReset = iso.string(from: now.addingTimeInterval(5 * 86400))
      let statusJSON = """
        {
          "userStatus": {
            "planStatus": {
              "planInfo": { "planName": "Pro" }
            },
            "cascadeModelConfigData": {
              "clientModelConfigs": [
                {
                  "label": "Gemini 4 Argon",
                  "quotaInfo": { "remainingFraction": 0.4, "resetTime": "\(shortReset)" }
                },
                {
                  "label": "Gemini 3.8 Flash",
                  "quotaInfo": { "remainingFraction": 0.8, "resetTime": "\(weeklyReset)" }
                }
              ]
            }
          }
        }
        """
      let report = AntigravityPlanHistory.parseUserStatus(
        Data(statusJSON.utf8), now: now)
      #expect(report?.planType == "Pro")
      #expect(report?.primary?.usedPercent == 60)
      #expect(report?.primary?.durationKnown == false)
      #expect(report?.scoped?.last?.usedPercent.rounded() == 20)
      #expect(report?.scoped?.last?.durationKnown == false)
      #expect(report?.scoped?.count == 2)
    }

  }
}

private let agyFixtureIdentity = AntigravityProcessIdentity(pid: 12345, executable: "/Applications/Antigravity.app/Contents/Resources/language_server_macos_arm", startedSeconds: 50, startedMicros: 1)
private func agyFixtureEndpoint(_ port: Int) -> AntigravityEndpoint { .init(identity: agyFixtureIdentity, port: port, token: "owned-fixture-token") }
private actor AntigravityProcessFixture: ToolProcessRunning {
    var calls: [[String]] = []
    func run(_ executable: URL, arguments: [String]) async throws -> ToolProcessResult {
        calls.append([executable.path] + arguments)
        let body = executable.lastPathComponent == "ps"
            ? "12345 language_server --csrf_token owned-fixture-token --host_bridge_url=http://127.0.0.1:1000\n99999 language_server --csrf_token unrelated-token\n"
            : "p12345\nn127.0.0.1:3456\np99999\nn127.0.0.1:1002\n"
        return .init(status: 0, output: Data(body.utf8), error: Data())
    }
}
private actor AntigravityDiscoveryFixture: AntigravityEndpointDiscovering {
    var valid = true, waiting = false, entered = false, cancelled = false
    var allowedChecks: Int?
    func set(valid: Bool = true, waiting: Bool = false, allowedChecks: Int? = nil) {
        self.valid = valid; self.waiting = waiting; self.allowedChecks = allowedChecks; entered = false
    }
    func discover() async throws -> [AntigravityEndpoint] {
        entered = true
        if waiting {
            do { try await Task.sleep(for: .seconds(20)) }
            catch { cancelled = Task.isCancelled; throw error }
        }
        return [agyFixtureEndpoint(12401)]
    }
    func owns(_ endpoint: AntigravityEndpoint) -> Bool {
        if let checks = allowedChecks { allowedChecks = checks - 1; return checks > 0 }
        return valid
    }
}
private actor AntigravityTransportFixture: AntigravityStatusTransport {
    var calls = 0
    func send(_ endpoint: AntigravityEndpoint) -> Data {
        calls += 1
        return Data(#"{"cascadeModelConfigData":{"clientModelConfigs":[{"label":"Observed fixture","quotaInfo":{"remainingFraction":0.4}}]}}"#.utf8)
    }
}
private final class AntigravityProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [Int] = [], stopped: Set<Int> = []
    func visit(_ port: Int) { lock.withLock { requests.append(port) } }
    func stop(_ port: Int) { _ = lock.withLock { stopped.insert(port) } }
    func stopped(_ port: Int) -> Bool { lock.withLock { stopped.contains(port) } }
    func count(_ port: Int) -> Int { lock.withLock { requests.filter { $0 == port }.count } }
}
private final class AntigravityURLProtocolFixture: URLProtocol, @unchecked Sendable {
    static let state = AntigravityProtocolState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let port = url.port else { return }
        Self.state.visit(port)
        guard port != 12404 && port != 12405 else { return }
        if port == 12406 {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "http://127.0.0.1:12407/leak"])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "http://127.0.0.1:12407/leak")!), redirectResponse: response)
            return
        }
        let headers = port == 12402 ? ["Content-Length": "1000000"] : [:]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        if port == 12403 {
            for _ in 0..<6 { client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 65536)) }
        } else { client?.urlProtocol(self, didLoad: Data("{}".utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { if let port = request.url?.port { Self.state.stop(port) } }
}

extension MacContractsTests {
    @Suite(.tags(.spending, .isolated), .serialized) @MainActor struct AntigravitySecurityTests {
        private func transport(deadline: TimeInterval = 2) -> URLSessionAntigravityTransport {
            URLSessionAntigravityTransport(configuration: {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [AntigravityURLProtocolFixture.self]
                return configuration
            }, deadline: deadline)
        }
        @Test("G07.03 endpoint discovery binds kernel identity and exact listener PID without adjacent probes")
        func endpointOwnership() async throws {
            let runner = AntigravityProcessFixture()
            let discovery = NativeAntigravityEndpointDiscovery(runner: runner, identity: { $0 == agyFixtureIdentity.pid ? agyFixtureIdentity : nil })
            let endpoints = try await discovery.discover()
            #expect(endpoints.count == 1 && endpoints.first?.port == 3456)
            let endpoint = try #require(endpoints.first)
            #expect(try await discovery.owns(endpoint))
            let replaced = NativeAntigravityEndpointDiscovery(runner: runner, identity: { pid in
                .init(pid: pid, executable: agyFixtureIdentity.executable, startedSeconds: 51, startedMicros: 1)
            })
            #expect(try await !replaced.owns(endpoint))
            #expect(!endpoint.description.contains(endpoint.token))
            #expect(NativeAntigravityEndpointDiscovery.ports(Data("p99999\nn127.0.0.1:3456\n".utf8), pid: 12345).isEmpty)
            let calls = await runner.calls
            #expect(calls.allSatisfy { !$0.contains("1001") && !$0.contains("1002") })
        }
        @Test("G07.03 rejected ownership never sends token; discovery cancellation tears down work")
        func rejectedOwnerAndCancellation() async throws {
            let discovery = AntigravityDiscoveryFixture(), wire = AntigravityTransportFixture()
            await discovery.set(valid: false)
            #expect(await AntigravityPlanHistory.read(discovery: discovery, transport: wire) == nil)
            #expect(await wire.calls == 0)
            await discovery.set(allowedChecks: 1)
            #expect(await AntigravityPlanHistory.read(discovery: discovery, transport: wire) == nil)
            #expect(await wire.calls == 1, "Owner changed after response: discard the quota")
            await discovery.set(waiting: true)
            let task = Task { await AntigravityPlanHistory.read(discovery: discovery, transport: wire) }
            for _ in 0..<100 {
                if await discovery.entered { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            task.cancel(); _ = await task.value
            #expect(await discovery.cancelled)
        }
        @Test("G07.03 local status transport bounds declared and streamed body and refuses redirects")
        func boundedTransport() async throws {
            let wire = transport()
            #expect(try await wire.send(agyFixtureEndpoint(12401)) == Data("{}".utf8))
            await #expect(throws: AntigravityTransportError.tooLarge) { try await wire.send(agyFixtureEndpoint(12402)) }
            await #expect(throws: AntigravityTransportError.tooLarge) { try await wire.send(agyFixtureEndpoint(12403)) }
            await #expect(throws: AntigravityTransportError.redirect) { try await wire.send(agyFixtureEndpoint(12406)) }
            #expect(AntigravityURLProtocolFixture.state.count(12407) == 0)
        }
        @Test("G07.03 total transport deadline and cancellation call stopLoading")
        func transportCancellation() async throws {
            await #expect(throws: (any Error).self) { try await transport(deadline: 0.1).send(agyFixtureEndpoint(12404)) }
            let task = Task { try await transport().send(agyFixtureEndpoint(12405)) }
            for _ in 0..<100 {
                if AntigravityURLProtocolFixture.state.count(12405) > 0 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            for _ in 0..<100 {
                if AntigravityURLProtocolFixture.state.stopped(12404) && AntigravityURLProtocolFixture.state.stopped(12405) { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(AntigravityURLProtocolFixture.state.stopped(12404) && AntigravityURLProtocolFixture.state.stopped(12405))
        }
        @Test("G07.03 quota expires, preserves observed labels and rejects old inferred cache")
        func quotaProvenance() throws {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let json = Data(#"{"cascadeModelConfigData":{"clientModelConfigs":[{"label":"Claude Other","modelId":"claude-example","quotaInfo":{"remainingFraction":0.4}}]}}"#.utf8)
            let report = try #require(AntigravityPlanHistory.parseUserStatus(json, now: now))
            #expect(report.primary?.scope == "Claude Other" && report.primary?.durationKnown == false)
            #expect(report.isCurrentAntigravity(at: now) && !report.isCurrentAntigravity(at: now.addingTimeInterval(301)))
            var legacy = report; legacy.source = nil
            #expect(!legacy.isCurrentAntigravity(at: now))
            let reset = ClaudeLimitsReport(capturedAt: now,
                primary: .init(usedPercent: 60, windowDurationMins: 1, resetsAt: now.addingTimeInterval(2).timeIntervalSince1970),
                secondary: nil, source: report.source)
            #expect(!reset.isCurrentAntigravity(at: now.addingTimeInterval(3)))
        }
    }
}
