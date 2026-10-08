import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import Combine
import IOKit
import Darwin

// Native clipboard data stays local. File entries store references, never file contents.
enum ClipboardCleanup: String, CaseIterable, Identifiable {
    case afterDays = "After a number of days", shutdown = "When the Mac shuts down", lidClose = "When the lid closes"
    var id: String { rawValue }
}
enum ClipboardKind: String, Codable, CaseIterable, Sendable { case text, image, files }
struct ClipboardPayload: Codable, Equatable, Sendable {
    var kind: ClipboardKind
    var text: String = ""
    var image: Data = Data()
    var files: [URL] = []
    var byteCount: Int { text.utf8.count + image.count + files.reduce(0) { $0 + $1.absoluteString.utf8.count } }
    var title: String {
        switch kind {
        case .text: return String(text.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(140) ?? "".prefix(140))
        case .image: return "Copied image"
        case .files: return files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        }
    }
    var valid: Bool {
        switch kind {
        case .text: return !text.isEmpty && text.utf8.count <= 512 * 1024 && image.isEmpty && files.isEmpty
        case .image: return !image.isEmpty && image.count <= 8 * 1024 * 1024 && text.isEmpty && files.isEmpty && image.starts(with: [137,80,78,71,13,10,26,10])
        case .files: return !files.isEmpty && files.count <= 50 && files.allSatisfy { $0.isFileURL && $0.absoluteString.utf8.count <= 8192 } && text.isEmpty && image.isEmpty
        }
    }
    var fingerprint: String {
        var data = Data(kind.rawValue.utf8)
        data.append(Data(text.utf8)); data.append(image)
        for url in files { data.append(0); data.append(Data(url.absoluteString.utf8)) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
struct ClipboardEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var payload: ClipboardPayload
    var copiedAt = Date()
    var sourceName: String
    var sourceBundle: String
    var pinned = false
}
struct ClipboardRead: Sendable {
    var changeCount: Int
    var payload: ClipboardPayload?
}

@MainActor protocol ClipboardAccess: AnyObject {
    func read(after changeCount: Int?, includeMedia: Bool) async -> ClipboardRead?
    func write(_ payload: ClipboardPayload) async -> Int?
}
protocol ClipboardStorage: Sendable {
    func load() async throws -> [ClipboardEntry]
    func save(_ entries: [ClipboardEntry], revision: UInt64) async throws
}
actor LocalClipboardStorage: ClipboardStorage {
    private let url: URL
    private var lastRevision: UInt64 = 0
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sieghart/Clipboard/history.json")) { self.url = url }
    func load() throws -> [ClipboardEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= 60 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: url))
    }
    func save(_ entries: [ClipboardEntry], revision: UInt64) throws {
        guard revision >= lastRevision else { return }
        let data = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        lastRevision = revision
    }
}

// A slow promised pasteboard provider cannot block the main thread or queue
// unlimited reads. A timeout discards its result; the worker remains reserved
// until the original operation actually returns.
private final class PasteboardWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sieghart.clipboard", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T? {
        guard lock.withLock({ if busy { return false }; busy = true; return true }) else { return nil }
        return await withCheckedContinuation { continuation in
            let delivery = PasteboardDelivery<T>(continuation)
            queue.async { [self] in
                let result = body()
                lock.withLock { busy = false }
                delivery.finish(result)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { delivery.finish(nil) }
        }
    }
}
private final class PasteboardDelivery<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }
    func finish(_ value: T?) {
        let pending = lock.withLock { let pending = continuation; continuation = nil; return pending }
        pending?.resume(returning: value)
    }
}
@MainActor final class SystemClipboardAccess: ClipboardAccess {
    private let worker = PasteboardWorker()
    nonisolated static let excludedTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
    func read(after changeCount: Int?, includeMedia: Bool) async -> ClipboardRead? {
        await worker.run {
            let board = NSPasteboard.general, count = board.changeCount
            // Baseline only: enabling/resuming does not capture an earlier copy.
            guard let changeCount, count != changeCount else { return ClipboardRead(changeCount: count, payload: nil) }
            let types = Set((board.types ?? []).map(\.rawValue))
            guard types.isDisjoint(with: Self.excludedTypes) else { return ClipboardRead(changeCount: count, payload: nil) }
            var payload: ClipboardPayload?
            if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
                if includeMedia, let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], urls.count <= 50 {
                    payload = ClipboardPayload(kind: .files, files: urls)
                }
            } else if includeMedia && (types.contains(NSPasteboard.PasteboardType.png.rawValue) || types.contains(NSPasteboard.PasteboardType.tiff.rawValue)) {
                let raw = board.data(forType: .png) ?? board.data(forType: .tiff)
                if let raw, raw.count <= 8 * 1024 * 1024, let bitmap = NSBitmapImageRep(data: raw), bitmap.pixelsWide <= 8192, bitmap.pixelsHigh <= 8192,
                   let png = bitmap.representation(using: .png, properties: [:]), png.count <= 8 * 1024 * 1024 {
                    payload = ClipboardPayload(kind: .image, image: png)
                }
            } else if let text = board.string(forType: .string), text.utf8.count <= 512 * 1024 { payload = ClipboardPayload(kind: .text, text: text) }
            guard board.changeCount == count else { return ClipboardRead(changeCount: count, payload: nil) }
            return ClipboardRead(changeCount: count, payload: payload?.valid == true ? payload : nil)
        }
    }
    func write(_ payload: ClipboardPayload) async -> Int? {
        guard payload.valid else { return nil }
        return await worker.run {
            let board = NSPasteboard.general
            board.clearContents()
            let success: Bool
            switch payload.kind {
            case .text: success = board.setString(payload.text, forType: .string)
            case .image: success = board.setData(payload.image, forType: .png)
            case .files: success = board.writeObjects(payload.files.map { $0 as NSURL })
            }
            return success ? board.changeCount : -1
        }.flatMap { $0 >= 0 ? $0 : nil }
    }
}
