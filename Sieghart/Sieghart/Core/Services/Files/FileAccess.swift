import Foundation

final class ScopedFile: @unchecked Sendable {
    let url: URL
    let details: FileDetails
    private let scoped: Bool
    private let lock = NSLock()
    private var closed = false
    init(url: URL) throws {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
            details = FileDetails(name: url.lastPathComponent, bytes: Int64(values.fileSize ?? 0),
                                  modifiedAt: values.contentModificationDate ?? .distantPast,
                                  resourceID: values.fileResourceIdentifier.map { String(describing: $0) } ?? url.standardizedFileURL.path,
                                  isDirectory: values.isDirectory ?? false)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw FileToolError.missing
        }
    }
    func close() {
        lock.withLock {
            guard !closed else { return }; closed = true
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
    }
    deinit { close() }
}

protocol FileAccessing: Sendable {
    func reference(for url: URL) async throws -> FileReference
    func resolve(_ reference: FileReference) async throws -> ScopedFile
    func list(_ folder: FileReference) async throws -> [DownloadFile]
}

actor LocalFileAccess: FileAccessing {
    func reference(for url: URL) throws -> FileReference {
        guard url.isFileURL else { throw FileToolError.unsupported }
        let file = try ScopedFile(url: url); defer { file.close() }
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        return FileReference(bookmark: bookmark, name: file.details.name, pathHint: url.path,
                             resourceID: file.details.resourceID, isDirectory: file.details.isDirectory)
    }
    func resolve(_ reference: FileReference) throws -> ScopedFile {
        var stale = false
        let url: URL
        do { url = try URL(resolvingBookmarkData: reference.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) }
        catch { throw FileToolError.access }
        guard url.isFileURL else { throw FileToolError.access }
        let file = try ScopedFile(url: url)
        guard file.details.resourceID == reference.resourceID else { file.close(); throw FileToolError.changed }
        return file
    }
    func list(_ folder: FileReference) throws -> [DownloadFile] {
        let file = try resolve(folder); defer { file.close() }
        guard file.details.isDirectory else { throw FileToolError.invalidDestination }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        let urls = try FileManager.default.contentsOfDirectory(at: file.url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        guard urls.count <= 10_000 else { throw FileToolError.message("This folder has too many entries. Choose a smaller downloads folder.") }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            guard values.isSymbolicLink != true else { return nil }
            let partial = DownloadFile.partialExtensions.contains(url.pathExtension.lowercased())
            guard values.isRegularFile == true || partial else { return nil }
            return DownloadFile(folderID: folder.id, name: url.lastPathComponent, bytes: Int64(values.fileSize ?? 0),
                                modifiedAt: values.contentModificationDate ?? .distantPast, partial: partial,
                                available: FileManager.default.isReadableFile(atPath: url.path),
                                resourceID: values.fileResourceIdentifier.map { String(describing: $0) } ?? url.path)
        }.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(100).map { $0 }
    }
}

protocol FilesStoring: Sendable {
    func load() async throws -> FilesSnapshot
    func save(_ snapshot: FilesSnapshot, revision: UInt64) async throws
}
actor LocalFilesStore: FilesStoring {
    private let url: URL
    private var revision: UInt64 = 0
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Sieghart/files.json")) { self.url = url }
    func load() throws -> FilesSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return FilesSnapshot() }
        guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 < 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(FilesSnapshot.self, from: Data(contentsOf: url))
    }
    func save(_ snapshot: FilesSnapshot, revision: UInt64) throws {
        guard revision >= self.revision else { return }
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        self.revision = revision
    }
}
