import Combine
import Foundation
import Darwin

enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude, antigravity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .antigravity: "Antigravity"
        }
    }
    var assetName: String {
        switch self {
        case .codex: "CodexMark"
        case .claude: "ClaudeMark"
        case .antigravity: "AntigravityMark"
        }
    }
}

struct LocalTokenUsage: Equatable, Sendable {
    // Input includes cache reads/writes; output includes reasoning tokens.
    // Cache and reasoning must never be added to those totals again.
    let input: Int64
    let cachedInput: Int64
    let cacheCreation: Int64
    let output: Int64
    let sessions: Int
    var total: Int64 { input + output }
}

enum LocalTokenReader {
    static func conversationID(for url: URL) -> String {
        if let uuid = url.pathComponents.reversed().first(where: { UUID(uuidString: $0) != nil }) {
            return uuid
        }
        let stem = url.deletingPathExtension().lastPathComponent
        if let uuid = UUID(uuidString: String(stem.suffix(36)))?.uuidString {
            return uuid
        }
        return url.path
    }

    static func discoverFiles(for provider: AIProvider, home: URL, codexHome: URL? = nil, antigravityHome: URL? = nil, includeArchived: Bool = false) -> [(URL, Date, Int)] {
        let manager = FileManager.default
        var candidates: [(URL, Date, Int)] = []
        if provider == .antigravity {
            let roots = antigravityHome.map { [$0.appendingPathComponent("brain")] }
                ?? [home.appendingPathComponent(".gemini/antigravity/brain"), home.appendingPathComponent(".gemini/antigravity-cli/brain")]
            for root in roots {
                guard let items = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
                for item in items.prefix(5000) {
                    let nested = item.appendingPathComponent(".system_generated/logs/transcript.jsonl")
                    let direct = item.appendingPathComponent("transcript.jsonl")
                    let targets = item.pathExtension == "jsonl" && item.lastPathComponent != "transcript_full.jsonl" ? [item] : [nested, direct]
                    for target in targets {
                        guard let info = try? target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]),
                              info.isRegularFile == true, info.isSymbolicLink != true else { continue }
                        candidates.append((target, info.contentModificationDate ?? .distantPast, info.fileSize ?? 0))
                        break
                    }
                }
            }
            return candidates
        }
        let codexRoot = codexHome ?? home.appendingPathComponent(".codex")
        let roots: [URL] = provider == .codex
            ? (includeArchived ? [codexRoot.appendingPathComponent("sessions"), codexRoot.appendingPathComponent("archived_sessions")] : [codexRoot.appendingPathComponent("sessions")])
            : [home.appendingPathComponent(".claude/projects")]
        for root in roots {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                if candidates.count >= 5000 { break }
                guard url.pathExtension == "jsonl",
                      let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                      info.isRegularFile == true, info.isSymbolicLink != true else { continue }
                candidates.append((url, info.contentModificationDate ?? .distantPast, info.fileSize ?? 0))
            }
        }
        return candidates
    }

    static func read(_ provider: AIProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser, codexHome: URL? = nil, antigravityHome: URL? = nil) -> LocalTokenUsage? {
        let files = discoverFiles(for: provider, home: home, codexHome: codexHome, antigravityHome: antigravityHome)
        let recent = files.sorted { $0.1 > $1.1 }.prefix(80).map(\.0)
        var counters: [String: [Int64]] = [:]
        var sessions = Set<String>()
        for url in recent {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let length = try? handle.seekToEnd() else { continue }
            let offset = length > 2_097_152 ? length - 2_097_152 : 0
            try? handle.seek(toOffset: offset)
            guard let tail = try? handle.readToEnd() else { continue }
            let lines = tail.split(separator: 10, omittingEmptySubsequences: true)
            let sessionID = conversationID(for: url)
            for line in offset > 0 ? lines.dropFirst() : lines[...] {
                guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                let fields: [String: Any]
                let key: String
                let counts: [Int64]
                switch provider {
                case .codex:
                    guard record["type"] as? String == "event_msg",
                          let payload = record["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                          let info = payload["info"] as? [String: Any], let usage = info["total_token_usage"] as? [String: Any] else { continue }
                    fields = usage
                    let name = url.deletingPathExtension().lastPathComponent
                    key = UUID(uuidString: String(name.suffix(36)))?.uuidString ?? url.path
                    let input = count(fields["input_tokens"]), cached = count(fields["cached_input_tokens"])
                    counts = [input, min(input, cached), min(input - min(input, cached), count(fields["cache_write_input_tokens"])), count(fields["output_tokens"])]
                case .claude:
                    guard record["type"] as? String == "assistant", let message = record["message"] as? [String: Any],
                          let id = message["id"] as? String, let usage = message["usage"] as? [String: Any] else { continue }
                    fields = usage; key = id
                    let fresh = count(fields["input_tokens"]), cached = count(fields["cache_read_input_tokens"]), created = count(fields["cache_creation_input_tokens"])
                    counts = [fresh + cached + created, cached, created, count(fields["output_tokens"])]
                case .antigravity:
                    guard record["type"] as? String == "PLANNER_RESPONSE" || record["source"] as? String == "MODEL" else { continue }
                    fields = record
                    let fresh = count(fields["input_tokens"]), cached = count(fields["cache_read_tokens"]), created = count(fields["cache_creation_tokens"]), out = count(fields["output_tokens"])
                    guard fresh + cached + created + out > 0 else { continue }
                    let step = fields["step_index"].map { "\($0)" } ?? (fields["created_at"] as? String ?? "")
                    key = "antigravity:\(sessionID):\(step)"
                    counts = [fresh + cached + created, cached, created, out]
                }
                guard fields["input_tokens"] != nil || fields["output_tokens"] != nil || fields["cache_read_tokens"] != nil else { continue }
                if let previous = counters[key] { counters[key] = zip(previous, counts).map { max($0, $1) } }
                else { counters[key] = counts }
                switch provider {
                case .codex: sessions.insert(key)
                case .claude: sessions.insert(url.path)
                case .antigravity: sessions.insert(sessionID)
                }
            }
        }
        guard !counters.isEmpty else { return nil }
        let sums = counters.values.reduce([Int64](repeating: 0, count: 4)) { total, entry in zip(total, entry).map(+) }
        return LocalTokenUsage(input: sums[0], cachedInput: sums[1], cacheCreation: sums[2], output: sums[3], sessions: sessions.count)
    }

    private static func count(_ value: Any?) -> Int64 {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 1_000_000_000_000 else { return 0 }
        return number.int64Value
    }
}

struct TokenPrices: Codable, Equatable, Sendable {
    var inputUSD: Decimal?
    var outputUSD: Decimal?
    var cachedInputUSD: Decimal?
    var cacheCreationUSD: Decimal?

    func estimate(_ usage: LocalTokenUsage?) -> Decimal? {
        guard let usage, let inputUSD, let outputUSD, inputUSD >= 0, outputUSD >= 0 else { return nil }
        let fresh = max(0, usage.input - usage.cachedInput - usage.cacheCreation)
        return (Decimal(fresh) * inputUSD + Decimal(usage.cachedInput) * (cachedInputUSD ?? inputUSD)
            + Decimal(usage.cacheCreation) * (cacheCreationUSD ?? inputUSD) + Decimal(usage.output) * outputUSD) / 1_000_000
    }
}

enum SpendCurrency: String, Codable, CaseIterable { case USD, BRL }
enum SpendKind: String, Codable, CaseIterable { case subscription = "Subscription", api = "API" }
struct RecordedCharge: Codable, Identifiable {
    var id = UUID()
    let provider: AIProvider
    let date: Date
    let amount: Decimal
    let currency: SpendCurrency
    let kind: SpendKind
    var externalID: String? = nil
    var source: String? = nil
}

struct AIUsageLedger: Codable {
    var prices: [AIProvider: TokenPrices] = [:]
    var charges: [RecordedCharge] = []
    var usdToBRL: Decimal?
    var exchangeRateDate: Date?
    var customPriceProviders: [AIProvider]?
    var customExchangeRate: Bool?

    func recorded(_ provider: AIProvider, currency: SpendCurrency, month: Date, calendar: Calendar = .current) -> Decimal? {
        let entries = charges.filter { $0.provider == provider && $0.currency == currency && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        guard !entries.isEmpty else { return nil }
        return entries.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

// Claude desktop history supplies measured percentages; renewal dates are
// absent in that source. Dated reports can supply explicit renewal dates.
struct ClaudeLimitsReport: Codable, Sendable {
    let capturedAt: Date
    let primary: ReportWindow?
    let secondary: ReportWindow?
    var scoped: [ReportWindow]? = nil
    var planType: String? = nil
    var source: String? = nil
    struct ReportWindow: Codable, Sendable {
        let usedPercent: Double
        let windowDurationMins: Int
        let resetsAt: TimeInterval?
        var scope: String? = nil
        var durationKnown: Bool? = nil
        var window: CodexQuotaWindow { CodexQuotaWindow(usedPercent: usedPercent, windowDurationMins: windowDurationMins, resetsAt: resetsAt) }
    }
    func isCurrentAntigravity(at now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        let windows = (scoped ?? []) + [primary, secondary].compactMap { $0 }
        return source == "antigravity-local-v2" && isValid(now: now) && age >= -30 && age <= 300 &&
            windows.allSatisfy { $0.resetsAt.map { $0 > now.timeIntervalSince1970 } ?? true }
    }
    func isValid(now: Date = .now) -> Bool {
        let windows = [primary, secondary].compactMap { $0 } + (scoped ?? [])
        return capturedAt <= now.addingTimeInterval(300) && !windows.isEmpty && windows.allSatisfy {
            $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) && $0.windowDurationMins > 0 && ($0.resetsAt.map { $0.isFinite && $0 > 0 } ?? true)
        }
    }
}

enum AntigravityPlanHistory {
    static func read(now: Date = .now, discovery: any AntigravityEndpointDiscovering = NativeAntigravityEndpointDiscovery(),
                     transport: any AntigravityStatusTransport = URLSessionAntigravityTransport()) async -> ClaudeLimitsReport? {
        do {
            return try await withThrowingTaskGroup(of: ClaudeLimitsReport?.self) { group in
                group.addTask {
                    for endpoint in try await discovery.discover().prefix(4) {
                        try Task.checkCancellation()
                        guard try await discovery.owns(endpoint) else { continue }
                        do {
                            let data = try await transport.send(endpoint)
                            try Task.checkCancellation()
                            guard try await discovery.owns(endpoint) else { continue }
                            if let report = parseUserStatus(data, now: now) { return report }
                        } catch is CancellationError { throw CancellationError() }
                        catch { continue }
                    }
                    return nil
                }
                group.addTask { try await Task.sleep(for: .seconds(8)); return nil }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
        } catch { return nil }
    }
    static func parseUserStatus(_ data: Data, now: Date = .now) -> ClaudeLimitsReport? {
        guard data.count <= 262_144, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let status = (root["userStatus"] as? [String: Any]) ?? root
        let planInfo = (status["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any]
        let plan = (planInfo?["planName"] as? String) ?? ((status["userTier"] as? [String: Any])?["name"] as? String)
        guard let cascade = status["cascadeModelConfigData"] as? [String: Any],
              let configs = cascade["clientModelConfigs"] as? [[String: Any]], !configs.isEmpty else { return nil }
        let active = ((cascade["defaultOverrideModelConfig"] as? [String: Any])?["modelOrAlias"] as? [String: Any])?["model"] as? String
        var windows: [(String?, ClaudeLimitsReport.ReportWindow)] = []
        for config in configs.prefix(100) {
            guard let quota = config["quotaInfo"] as? [String: Any], let fraction = quota["remainingFraction"] as? NSNumber,
                  CFGetTypeID(fraction) != CFBooleanGetTypeID(), fraction.doubleValue.isFinite,
                  (0...1).contains(fraction.doubleValue) else { continue }
            let reset = (quota["resetTime"] as? String).flatMap { AIActivityParser.parseDate($0) }
            if quota["resetTime"] != nil && reset == nil { continue }
            if let reset, reset <= now { continue }
            let duration = (quota["windowDurationMins"] as? NSNumber)?.intValue
            let known = duration.map { (1...525600).contains($0) } ?? false
            let id = ((config["modelOrAlias"] as? [String: Any])?["model"] as? String)
            let label = (config["label"] as? String) ?? (config["modelId"] as? String) ?? id ?? "Model allowance"
            // One minute is an internal placeholder only. Unknown durations
            // render as an allowance with a reset time, never as 5h/weekly.
            windows.append((id, .init(usedPercent: (1 - fraction.doubleValue) * 100,
                windowDurationMins: known ? duration! : 1, resetsAt: reset?.timeIntervalSince1970,
                scope: String(label.prefix(100)), durationKnown: known)))
        }
        guard let primary = windows.first(where: { active != nil && $0.0 == active })?.1 ?? windows.first?.1 else { return nil }
        return ClaudeLimitsReport(capturedAt: now, primary: primary, secondary: nil, scoped: windows.map(\.1),
            planType: plan.map { String($0.prefix(100)) }, source: "antigravity-local-v2")
    }
}

struct AntigravityProcessIdentity: Equatable, Sendable {
    let pid: Int32
    let executable: String
    let startedSeconds: UInt64
    let startedMicros: UInt64
}
struct AntigravityEndpoint: Sendable, CustomStringConvertible {
    let identity: AntigravityProcessIdentity
    let port: Int
    let token: String
    var description: String { "Antigravity local endpoint (pid \(identity.pid))" }
    var url: URL { URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus")! }
}
protocol AntigravityEndpointDiscovering: Sendable {
    func discover() async throws -> [AntigravityEndpoint]
    func owns(_ endpoint: AntigravityEndpoint) async throws -> Bool
}
struct NativeAntigravityEndpointDiscovery: AntigravityEndpointDiscovering {
    var runner: any ToolProcessRunning = NativeToolProcess(timeout: 1)
    var identity: @Sendable (Int32) -> AntigravityProcessIdentity? = Self.processIdentity
    static func processIdentity(_ pid: Int32) -> AntigravityProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == getuid() else { return nil }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let executable = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard executable.lowercased().contains("/antigravity.app/contents/"),
              URL(fileURLWithPath: executable).lastPathComponent.hasPrefix("language_server") else { return nil }
        return AntigravityProcessIdentity(pid: pid, executable: executable, startedSeconds: info.pbi_start_tvsec, startedMicros: info.pbi_start_tvusec)
    }
    static func token(in arguments: String) -> String? {
        let parts = arguments.split(whereSeparator: \.isWhitespace).map(String.init)
        let token: String?
        if let flag = parts.first(where: { $0.hasPrefix("--csrf_token=") }) { token = String(flag.dropFirst("--csrf_token=".count)) }
        else if let index = parts.firstIndex(of: "--csrf_token"), index + 1 < parts.count { token = parts[index + 1] }
        else { return nil }
        guard let token, !token.isEmpty, token.utf8.count <= 512,
              token.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return token
    }
    static func ports(_ data: Data, pid: Int32) -> [Int] {
        var current: Int32?, result = Set<Int>()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            if line.first == "p" { current = Int32(line.dropFirst()); continue }
            guard current == pid, line.hasPrefix("n127.0.0.1:") || line.hasPrefix("n*:"),
                  let port = line.split(separator: ":").last.flatMap({ Int($0) }), (1...65535).contains(port) else { continue }
            result.insert(port)
        }
        return Array(result.sorted().prefix(4))
    }
    private func listeningPorts(_ pid: Int32) async throws -> [Int] {
        let output = try await runner.run(URL(fileURLWithPath: "/usr/sbin/lsof"), arguments: ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"])
        return output.status == 0 ? Self.ports(output.output, pid: pid) : []
    }
    func discover() async throws -> [AntigravityEndpoint] {
        let output = try await runner.run(URL(fileURLWithPath: "/bin/ps"), arguments: ["-axo", "pid=,args="])
        guard output.status == 0 else { return [] }
        var endpoints: [AntigravityEndpoint] = []
        for line in String(decoding: output.output, as: UTF8.self).split(separator: "\n") {
            try Task.checkCancellation()
            guard line.count < 16_384, line.contains("language_server"), line.contains("--csrf_token") else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let pid = Int32(parts[0]), let owner = identity(pid), let token = Self.token(in: String(parts[1])) else { continue }
            // The kernel executable/launch identity and lsof's exact PID bind
            // the token to a real listener. No adjacent ports are probed.
            for port in try await listeningPorts(pid) {
                guard identity(pid) == owner else { break }
                endpoints.append(AntigravityEndpoint(identity: owner, port: port, token: token))
                if endpoints.count == 4 { return endpoints }
            }
        }
        return endpoints
    }
    func owns(_ endpoint: AntigravityEndpoint) async throws -> Bool {
        guard identity(endpoint.identity.pid) == endpoint.identity else { return false }
        let ports = try await listeningPorts(endpoint.identity.pid)
        return ports.contains(endpoint.port) && identity(endpoint.identity.pid) == endpoint.identity
    }
}

enum AntigravityTransportError: Error { case invalidEndpoint, invalidResponse, tooLarge, redirect, deadline }
protocol AntigravityStatusTransport: Sendable {
    func send(_ endpoint: AntigravityEndpoint) async throws -> Data
}
struct URLSessionAntigravityTransport: AntigravityStatusTransport {
    var configuration: @Sendable () -> URLSessionConfiguration = { .ephemeral }
    var deadline: TimeInterval = 2
    var maximumBytes: Int = 262_144
    func send(_ endpoint: AntigravityEndpoint) async throws -> Data {
        guard (1...65535).contains(endpoint.port), !endpoint.token.isEmpty, endpoint.token.utf8.count <= 512,
              !endpoint.token.contains(where: { $0.isWhitespace || $0.isNewline }),
              maximumBytes > 0, maximumBytes <= 262_144 else { throw AntigravityTransportError.invalidEndpoint }
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"; request.timeoutInterval = max(0.01, min(2, deadline))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(endpoint.token, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data("{}".utf8)
        let operation = AntigravityStatusOperation(request: request, configuration: configuration(), limit: maximumBytes, deadline: max(0.01, min(2, deadline)))
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { operation.begin($0) }
        } onCancel: { operation.cancel() }
    }
}
private final class AntigravityStatusOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let limit: Int
    private let deadline: TimeInterval
    private var session: URLSession?
    private var continuation: CheckedContinuation<Data, any Error>?
    private var timer: DispatchWorkItem?
    private var data = Data()
    private var validResponse = false
    private var finished = false
    init(request: URLRequest, configuration: URLSessionConfiguration, limit: Int, deadline: TimeInterval) {
        self.request = request; self.configuration = configuration; self.limit = limit; self.deadline = deadline
    }
    func begin(_ continuation: CheckedContinuation<Data, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false; configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = deadline; configuration.timeoutIntervalForResource = deadline
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.dataTask(with: request)
        let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(AntigravityTransportError.deadline)) }
        timer = timeout
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deadline, execute: timeout)
        task.resume()
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<Data, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; timer?.cancel(); timer = nil
        let continuation = continuation, session = session
        self.continuation = nil; self.session = nil
        lock.unlock()
        session?.invalidateAndCancel(); continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.url == request.url, http.statusCode == 200 else {
            completionHandler(.cancel); finish(.failure(AntigravityTransportError.invalidResponse)); return
        }
        guard response.expectedContentLength <= limit else {
            completionHandler(.cancel); finish(.failure(AntigravityTransportError.tooLarge)); return
        }
        lock.lock(); validResponse = true; let active = !finished; lock.unlock()
        completionHandler(active ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count + chunk.count <= limit else {
            lock.unlock(); finish(.failure(AntigravityTransportError.tooLarge)); return
        }
        data.append(chunk); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if error != nil { finish(.failure(AntigravityTransportError.invalidResponse)); return }
        lock.lock(); let result = data, valid = validResponse; lock.unlock()
        finish(valid ? .success(result) : .failure(AntigravityTransportError.invalidResponse))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(AntigravityTransportError.redirect))
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
