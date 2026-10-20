import Foundation
import Darwin

@MainActor final class AgentRPCProcess {
    var onMessage: ((AgentJSON) -> Void)?
    var onDisconnect: (() -> Void)?
    private var process: Process?
    private var input: RPCInputWriter?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var buffer = Data()
    private var generation = 0
    private var counter = 0
    private var pending: [String: CheckedContinuation<AgentJSON, any Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    var running: Bool { process?.isRunning == true }

    func start(_ executable: URL, arguments: [String], environment: [String: String]? = nil) throws {
        stop(notify: false); generation += 1; let version = generation
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = executable; child.arguments = arguments; child.environment = environment
        child.currentDirectoryURL = FileManager.default.temporaryDirectory
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        input = try RPCInputWriter(stdin.fileHandleForWriting); output = stdout.fileHandleForReading; errors = stderr.fileHandleForReading
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in self?.consume(data, generation: version) }
        }
        // Drain stderr without exposing credentials or arbitrary diagnostic text.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in guard self?.generation == version else { return }; self?.stop() }
        }
        process = child
        do { try child.run() } catch { stop(notify: false); throw CodingAgentError.unavailable("The coding runtime could not start. Check its executable path.") }
    }

    func request(_ method: String, params: AgentJSON = .object([:]), timeout: Duration = .seconds(20)) async throws -> AgentJSON {
        guard running else { throw CodingAgentError.disconnected }
        counter += 1; let id = "sieg-\(counter)"
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.finish(id, result: .failure(CodingAgentError.timedOut))
                }
                do { try send(.object(["id": .string(id), "method": .string(method), "params": params])) }
                catch { finish(id, result: .failure(error)) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) } }
    }

    func send(_ packet: AgentJSON) throws {
        guard running, let input else { throw CodingAgentError.disconnected }
        var data = try JSONEncoder().encode(packet)
        guard data.count <= 262_144 else { throw CodingAgentError.invalidResponse }
        data.append(10)
        let payload = data, version = generation
        input.send(payload) { [weak self] in
            Task { @MainActor [weak self] in guard self?.generation == version else { return }; self?.stop() }
        }
    }
    private func consume(_ data: Data, generation version: Int) {
        guard generation == version else { return }
        guard !data.isEmpty else { stop(); return }
        buffer.append(data)
        guard buffer.count <= 8 * 1024 * 1024 else { stop(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer.prefix(upTo: newline)); buffer.removeSubrange(...newline)
            guard !line.isEmpty, let message = try? JSONDecoder().decode(AgentJSON.self, from: line) else { continue }
            if let id = message["id"].string, pending[id] != nil, message["method"] == .null {
                if message["error"] != .null {
                    let reason = String((message["error"]["message"].string ?? "The coding runtime rejected the request.").prefix(500))
                    finish(id, result: .failure(CodingAgentError.unavailable(reason)))
                } else { finish(id, result: .success(message["result"])) }
            } else { onMessage?(message) }
        }
    }
    private func finish(_ id: String, result: Result<AgentJSON, any Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }
    func stop(notify: Bool = true) {
        generation += 1
        output?.readabilityHandler = nil; errors?.readabilityHandler = nil
        let child = process; process = nil
        if child?.isRunning == true {
            child?.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if let child, child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        }
        input?.close(); try? output?.close(); try? errors?.close()
        input = nil; output = nil; errors = nil; buffer.removeAll(keepingCapacity: false)
        for id in Array(pending.keys) { finish(id, result: .failure(CodingAgentError.disconnected)) }
        if notify { onDisconnect?() }
    }
}

// One queue owns all writes AND the final close. Nonblocking writes allow stop
// to interrupt a full pipe without blocking the main actor or leaking a worker.
private final class RPCInputWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "sieg.agent-rpc.write", qos: .utility)
    private let lock = NSLock()
    private var stopped = false
    init(_ handle: FileHandle) throws {
        self.handle = handle
        let fd = handle.fileDescriptor
        guard fcntl(fd, F_SETNOSIGPIPE, 1) != -1,
              fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else {
            try? handle.close(); throw CodingAgentError.disconnected
        }
    }
    private var isStopped: Bool { lock.withLock { stopped } }
    func send(_ payload: Data, failed: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            guard !isStopped else { return }
            let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
            let success = payload.withUnsafeBytes { bytes -> Bool in
                guard let base = bytes.baseAddress else { return true }
                var offset = 0
                while offset < bytes.count {
                    guard !isStopped, DispatchTime.now().uptimeNanoseconds < deadline else { return false }
                    let count = Darwin.write(handle.fileDescriptor, base.advanced(by: offset), bytes.count - offset)
                    if count > 0 { offset += count; continue }
                    if count < 0 && errno == EINTR { continue }
                    guard count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) else { return false }
                    var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&descriptor, 1, 50)
                }
                return true
            }
            if !success && !isStopped { failed() }
        }
    }
    func close() {
        let first = lock.withLock { let first = !stopped; stopped = true; return first }
        guard first else { return }
        queue.async { [self] in try? handle.close() }
    }
}
