import Foundation
import Darwin

struct ToolProcessResult: Sendable { var status: Int32; var output: Data; var error: Data }
protocol ToolProcessRunning: Sendable {
    func run(_ executable: URL, arguments: [String]) async throws -> ToolProcessResult
}
private final class ToolProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func start(_ process: Process) throws {
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            self.process = process; try process.run()
        }
    }
    func cancel() {
        let child = lock.withLock { cancelled = true; return process }
        if child?.isRunning == true {
            child?.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if let child, child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }
    var isCancelled: Bool { lock.withLock { cancelled } }
}
struct NativeToolProcess: ToolProcessRunning {
    func run(_ executable: URL, arguments: [String]) async throws -> ToolProcessResult {
        let box = ToolProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sieghart-process-\(UUID())", isDirectory: true)
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        defer { try? FileManager.default.removeItem(at: folder) }
                        let stdout = folder.appendingPathComponent("out"), stderr = folder.appendingPathComponent("err")
                        FileManager.default.createFile(atPath: stdout.path, contents: nil, attributes: [.posixPermissions: 0o600])
                        FileManager.default.createFile(atPath: stderr.path, contents: nil, attributes: [.posixPermissions: 0o600])
                        let out = try FileHandle(forWritingTo: stdout), err = try FileHandle(forWritingTo: stderr)
                        defer { try? out.close(); try? err.close() }
                        let process = Process(); process.executableURL = executable; process.arguments = arguments
                        process.standardOutput = out; process.standardError = err
                        try box.start(process); process.waitUntilExit()
                        if box.isCancelled { throw CancellationError() }
                        func read(_ url: URL) throws -> Data {
                            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                            return try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
                        }
                        continuation.resume(returning: try ToolProcessResult(status: process.terminationStatus, output: read(stdout), error: read(stderr)))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { box.cancel() }
    }
}
