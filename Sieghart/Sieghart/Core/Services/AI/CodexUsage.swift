import Combine
import Darwin
import Foundation

struct CodexQuotaWindow: Decodable, Equatable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?

    var title: String {
        switch windowDurationMins {
        case 300: "5-hour window"
        case 1440: "Daily"
        case 10080: "Weekly"
        case let minutes? where minutes > 0 && minutes % 60 == 0: "\(minutes / 60)-hour window"
        case let minutes? where minutes > 0: "\(minutes)-minute window"
        default: "Usage window"
        }
    }

    var resetDate: Date? { resetsAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } }
    func remainingPercent(at now: Date) -> Int? {
        guard let usedPercent, usedPercent.isFinite,
              resetDate.map({ $0 > now }) ?? true else { return nil }
        return Int((100 - min(100, max(0, usedPercent))).rounded())
    }
}

struct CodexQuotaBucket: Decodable, Sendable {
    let limitId: String?
    var planType: String? = nil
    let primary: CodexQuotaWindow?
    let secondary: CodexQuotaWindow?
}

struct CodexUsageResponse: Decodable, Sendable {
    let rateLimits: CodexQuotaBucket?
    let rateLimitsByLimitId: [String: CodexQuotaBucket]?

    var codex: CodexQuotaBucket? {
        if let bucket = rateLimitsByLimitId?["codex"] { return bucket }
        if let rateLimits, rateLimits.limitId == "codex" { return rateLimits }
        // Legacy responses predate bucket identifiers. Never substitute a
        // different model's quota when a populated multi-bucket map is present.
        if rateLimitsByLimitId?.isEmpty ?? true, rateLimits?.limitId == nil { return rateLimits }
        return nil
    }
}

enum CodexUsageError: Error, LocalizedError {
    case missingCLI, unavailable, timedOut, invalidResponse
    var errorDescription: String? {
        switch self {
        case .missingCLI: "Install Codex or its CLI, sign in with ChatGPT, then refresh."
        case .unavailable: "Could not read Codex limits. Check your Codex sign-in and connection, then retry."
        case .timedOut: "Codex took too long to respond. Try refreshing again."
        case .invalidResponse: "Codex has not returned readable usage limits."
        }
    }
}

// Short-lived read-only stdio connections for quota and account activity.
// Credentials stay inside Codex. No inference, login, turns, or reset requests.
enum LocalCodexUsage {
    static func executable() -> URL? {
        let manager = FileManager.default
        let names = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            manager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return names.first(where: { manager.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    static func fetch(executable: URL? = nil, timeout: TimeInterval = 12) throws -> CodexUsageResponse {
        let result = try JSONDecoder().decode(CodexUsageResponse.self, from: request(method: "account/rateLimits/read", executable: executable, timeout: timeout))
        guard let bucket = result.codex, bucket.primary != nil || bucket.secondary != nil else { throw CodexUsageError.invalidResponse }
        return result
    }

    static func fetchActivity() throws -> CodexAccountActivity {
        try JSONDecoder().decode(CodexAccountActivity.self, from: request(method: "account/usage/read"))
    }

    private static func request(method: String, executable: URL? = nil, timeout: TimeInterval = 12) throws -> Data {
        guard let executable = executable ?? self.executable() else { throw CodexUsageError.missingCLI }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        let termination = DispatchWorkItem {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: termination)
        defer {
            termination.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
        }
        var buffered = Data()
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func response(id: Int) throws -> Data {
            while Date() < deadline {
                while let newline = buffered.firstIndex(of: 10) {
                    let line = Data(buffered.prefix(upTo: newline))
                    buffered.removeSubrange(...newline)
                    guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          (message["id"] as? NSNumber)?.intValue == id else { continue }
                    guard message["error"] == nil, let result = message["result"] else { throw CodexUsageError.unavailable }
                    return try JSONSerialization.data(withJSONObject: result)
                }
                // A fixed-length pipe read can wait for an entire buffer while
                // the server is waiting for our next handshake message.
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else {
                    throw Date() >= deadline ? CodexUsageError.timedOut : CodexUsageError.unavailable
                }
                buffered.append(chunk)
                guard buffered.count <= 131072 else { throw CodexUsageError.invalidResponse }
            }
            throw CodexUsageError.timedOut
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "sieghart", "title": "Sieghart", "version": "0.1.0"]]])
        _ = try response(id: 1)
        try send(["method": "initialized", "params": [:]])
        try send(["id": 2, "method": method])
        return try response(id: 2)
    }
}

struct CodexAccountActivity: Decodable, Sendable {
    struct Summary: Decodable, Sendable {
        let lifetimeTokens: Int64?
        let peakDailyTokens: Int64?
        let currentStreakDays: Int64?
    }
    struct Day: Decodable, Sendable {
        let startDate: String
        let tokens: Int64
    }
    let summary: Summary?
    let dailyUsageBuckets: [Day]?
}
