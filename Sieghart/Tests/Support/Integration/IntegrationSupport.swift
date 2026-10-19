import AppKit
import Foundation
import Testing

/// Every disk fixture owns one directory, including scripts, SQLite and logs.
final class IntegrationDirectory {
    let url: URL
    init(_ label: String = "integration") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("sieg-testing-\(label)-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { cleanup() }
    func cleanup() { try? FileManager.default.removeItem(at: url) }
    func file(_ name: String, contents: String = "fixture") throws -> URL {
        let result = url.appendingPathComponent(name)
        try Data(contents.utf8).write(to: result)
        return result
    }
    func python(_ body: String) throws -> URL {
        let interpreter = "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"
        try #require(FileManager.default.isExecutableFile(atPath: interpreter), "Owned process fixture requires Python 3.12 at \(interpreter)")
        var lines = body.components(separatedBy: "\n")
        if lines.first?.hasPrefix("#!") == true { lines.removeFirst() }
        let script = try file("runtime.py", contents: "#!\(interpreter)\n" + lines.joined(separator: "\n"))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }
}

/// Bounded coordination for native-process, stream and lifecycle delivery.
/// Yielding permits the actor to deliver events; elapsed time is only a failure bound.
@MainActor enum IntegrationWait {
    static func until(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(5))
        while !condition(), clock.now < deadline { await Task.yield() }
        try #require(condition(), "Fixture event was not delivered before its deadline", sourceLocation: sourceLocation)
    }
    static func untilAsync(_ condition: () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            if await condition() { return }
            await Task.yield()
        }
        let result = await condition()
        try #require(result, "Fixture event was not delivered before its deadline", sourceLocation: sourceLocation)
    }
}

/// A fixture rendezvous, so logical cancellation/races do not depend on sleeping.
@MainActor final class IntegrationGate {
    private(set) var entered = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false
    func suspend() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func release() {
        released = true
        let pending = continuations; continuations = []
        pending.forEach { $0.resume() }
    }
}
