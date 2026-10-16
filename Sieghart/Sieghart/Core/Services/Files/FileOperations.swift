import AppKit
import Foundation

protocol FileOperating: Sendable {
    func review(_ kind: FileOperationKind, sources: [FileReference], destination: FileReference, rename: String?, conflict: FileConflictPolicy) async throws -> ReviewedFileOperation
    func perform(_ review: ReviewedFileOperation) async throws -> [FileReference]
}

actor LocalFileOperations: FileOperating {
    private let access: any FileAccessing
    init(access: any FileAccessing = LocalFileAccess()) { self.access = access }
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":")
            && name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
    func review(_ kind: FileOperationKind, sources: [FileReference], destination: FileReference, rename: String?, conflict: FileConflictPolicy) async throws -> ReviewedFileOperation {
        guard kind != .install, !sources.isEmpty, sources.count <= 50,
              Set(sources.map(\.resourceID)).count == sources.count,
              kind != .rename || sources.count == 1 else { throw FileToolError.unsupported }
        let folder = try await access.resolve(destination); defer { folder.close() }
        guard folder.details.isDirectory, FileManager.default.isWritableFile(atPath: folder.url.path) else { throw FileToolError.invalidDestination }
        var details: [FileDetails] = [], names: [String] = []
        for source in sources {
            try Task.checkCancellation()
            let file = try await access.resolve(source); defer { file.close() }
            let directoryPath = folder.url.resolvingSymlinksInPath().standardizedFileURL.path
            let sourcePath = file.url.resolvingSymlinksInPath().standardizedFileURL.path
            guard directoryPath != sourcePath, !directoryPath.hasPrefix(sourcePath + "/") else { throw FileToolError.invalidDestination }
            var name = kind == .rename ? rename ?? "" : file.details.name
            guard Self.validName(name) else { throw FileToolError.invalidName }
            if FileManager.default.fileExists(atPath: folder.url.appendingPathComponent(name).path) || names.contains(name) {
                guard conflict == .keepBoth else { throw FileToolError.conflict(name) }
                name = Self.availableName(name, in: folder.url, reserved: Set(names))
            }
            details.append(file.details); names.append(name)
        }
        return ReviewedFileOperation(kind: kind, sources: sources, details: details, destination: destination, targetNames: names)
    }
    static func availableName(_ name: String, in folder: URL, reserved: Set<String> = []) -> String {
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        for i in 2...10_000 {
            let candidate = "\(stem) \(i)" + (ext.isEmpty ? "" : ".\(ext)")
            if !reserved.contains(candidate) && !FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) { return candidate }
        }
        return UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
    }
    func perform(_ review: ReviewedFileOperation) async throws -> [FileReference] {
        guard review.kind != .install, !review.sources.isEmpty,
              review.sources.count == review.details.count, review.sources.count == review.targetNames.count,
              Set(review.targetNames).count == review.targetNames.count,
              review.targetNames.allSatisfy(Self.validName) else { throw FileToolError.changed }
        let folder = try await access.resolve(review.destination); defer { folder.close() }
        guard folder.details.isDirectory, FileManager.default.isWritableFile(atPath: folder.url.path) else { throw FileToolError.invalidDestination }
        var files: [ScopedFile] = []
        defer { files.forEach { $0.close() } }
        for (index, reference) in review.sources.enumerated() {
            let file = try await access.resolve(reference); files.append(file)
            guard file.details == review.details[index] else { throw FileToolError.changed }
            let path = folder.url.resolvingSymlinksInPath().standardizedFileURL.path
            let source = file.url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path != source, !path.hasPrefix(source + "/") else { throw FileToolError.invalidDestination }
            guard !FileManager.default.fileExists(atPath: folder.url.appendingPathComponent(review.targetNames[index]).path) else { throw FileToolError.conflict(review.targetNames[index]) }
        }
        var moved: [(URL, URL)] = [], output: [FileReference] = []
        do {
            for (index, file) in files.enumerated() {
                try Task.checkCancellation()
                let target = folder.url.appendingPathComponent(review.targetNames[index])
                try FileManager.default.moveItem(at: file.url, to: target)
                moved.append((file.url, target))
                var reference = (try? await access.reference(for: target)) ?? review.sources[index]
                reference.id = review.sources[index].id; reference.name = target.lastPathComponent; reference.pathHint = target.path
                output.append(reference)
            }
            return output
        } catch {
            var failed = 0
            for (original, target) in moved.reversed() {
                do { try FileManager.default.moveItem(at: target, to: original) } catch { failed += 1 }
            }
            if failed > 0 { throw FileToolError.message("Some files moved before the action stopped. Check the source and destination folders before trying again.") }
            throw error
        }
    }
}

protocol FinderSelecting: Sendable {
    func selection() async throws -> [URL]
    func insertionFolder() async throws -> URL
}
actor FinderFileSelection: FinderSelecting {
    private func evaluate(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw FileToolError.unsupported }
        let result = script.executeAndReturnError(&error)
        if error != nil { throw FileToolError.message("Allow Sieghart to control Finder in System Settings → Privacy & Security → Automation, or use Choose files.") }
        return result
    }
    func selection() throws -> [URL] {
        let result = try evaluate("""
            tell application "Finder"
                set paths to {}
                repeat with selectedItem in (get selection)
                    set end of paths to POSIX path of (selectedItem as alias)
                end repeat
                return paths
            end tell
            """)
        guard result.numberOfItems > 0, result.numberOfItems <= 50 else { throw FileToolError.message("Select between one and fifty files in Finder first.") }
        return (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }.map { URL(fileURLWithPath: $0) }
    }
    func insertionFolder() throws -> URL {
        let result = try evaluate("tell application \"Finder\" to return POSIX path of (insertion location as alias)")
        guard let path = result.stringValue else { throw FileToolError.invalidDestination }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

struct URLCleanupReview: Equatable {
    var original: String
    var cleaned: String
    var removed: [String]
    var isSigned: Bool
}
enum URLTrackingCleanup {
    static func review(_ text: String) throws -> URLCleanupReview {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard original.utf8.count <= 512 * 1024 else { throw FileToolError.message("This link is too large to review.") }
        guard var components = URLComponents(string: original), ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false else { throw FileToolError.message("Enter a complete http or https link.") }
        let parts = components.percentEncodedQuery?.components(separatedBy: "&") ?? []
        func name(_ part: String) -> String { String(part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0]).removingPercentEncoding?.lowercased() ?? "" }
        let signed = parts.contains { ["signature", "sig", "x-amz-signature", "x-goog-signature"].contains(name($0)) }
        guard !signed else { return URLCleanupReview(original: original, cleaned: original, removed: [], isSigned: true) }
        let known: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid"]
        let removed = parts.filter { name($0).hasPrefix("utm_") || known.contains(name($0)) }
        let kept = parts.filter { !removed.contains($0) }
        // Keep the encoded values, order, duplicates, fragment and functional
        // query parameters byte-for-byte rather than decode/re-encode them.
        if !removed.isEmpty { components.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&") }
        return URLCleanupReview(original: original, cleaned: removed.isEmpty ? original : components.string ?? original,
                                removed: removed.map(name), isSigned: false)
    }
}
