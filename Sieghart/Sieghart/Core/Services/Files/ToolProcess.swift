import Foundation
import Darwin

struct ToolProcessResult: Sendable { var status: Int32; var output: Data; var error: Data }
enum ToolProcessError: Error { case timedOut }
protocol ToolProcessRunning: Sendable {
    func run(_ executable: URL, arguments: [String]) async throws -> ToolProcessResult
}
private final class ToolProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var failure: (any Error)?
    private var completed = false
    private var deadline: DispatchWorkItem?
    func start(_ process: Process, timeout: TimeInterval) throws {
        try lock.withLock {
            if let failure { throw failure }
            self.process = process
            try process.run()
            let item = DispatchWorkItem { [weak self] in self?.cancel(ToolProcessError.timedOut) }
            deadline = item
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: item)
        }
    }
    func cancel(_ error: any Error = CancellationError()) {
        let child: Process? = lock.withLock {
            guard !completed else { return nil }
            if failure == nil { failure = error }
            return process
        }
        if let child, child.isRunning {
            child.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }
    func finish(_ result: Result<ToolProcessResult, any Error>, continuation: CheckedContinuation<ToolProcessResult, any Error>) {
        let final: Result<ToolProcessResult, any Error>? = lock.withLock {
            guard !completed else { return nil }
            completed = true; deadline?.cancel(); deadline = nil
            process?.terminationHandler = nil; process = nil
            return failure.map { .failure($0) } ?? result
        }
        if let final { continuation.resume(with: final) }
    }
}
struct NativeToolProcess: ToolProcessRunning {
    var timeout: TimeInterval = 60
    func run(_ executable: URL, arguments: [String]) async throws -> ToolProcessResult {
        let box = ToolProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sieghart-process-\(UUID())", isDirectory: true)
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        let stdout = folder.appendingPathComponent("out"), stderr = folder.appendingPathComponent("err")
                        FileManager.default.createFile(atPath: stdout.path, contents: nil, attributes: [.posixPermissions: 0o600])
                        FileManager.default.createFile(atPath: stderr.path, contents: nil, attributes: [.posixPermissions: 0o600])
                        let out = try FileHandle(forWritingTo: stdout), err = try FileHandle(forWritingTo: stderr)
                        let process = Process(); process.executableURL = executable; process.arguments = arguments
                        process.standardInput = FileHandle.nullDevice
                        process.standardOutput = out; process.standardError = err
                        process.terminationHandler = { child in
                            defer { try? out.close(); try? err.close(); try? FileManager.default.removeItem(at: folder) }
                            let result = Result<ToolProcessResult, any Error> {
                                func read(_ url: URL) throws -> Data {
                                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                                    return try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
                                }
                                return try ToolProcessResult(status: child.terminationStatus, output: read(stdout), error: read(stderr))
                            }
                            box.finish(result, continuation: continuation)
                        }
                        do { try box.start(process, timeout: max(0.01, timeout)) }
                        catch {
                            process.terminationHandler = nil; try? out.close(); try? err.close()
                            throw error
                        }
                    } catch {
                        try? FileManager.default.removeItem(at: folder)
                        box.finish(.failure(error), continuation: continuation)
                    }
                }
            }
        } onCancel: { box.cancel() }
    }
}
