import Foundation
import Darwin

protocol FolderObserving: Sendable {
    func start(_ folder: FileReference, changed: @escaping @Sendable (UUID, Bool) -> Void) async throws
    func stop(_ id: UUID) async
    func stopAll() async
    func updatePartials(_ folder: FileReference, files: [DownloadFile]) async
}
extension FolderObserving { func updatePartials(_ folder: FileReference, files: [DownloadFile]) async {} }

actor LocalFolderObserver: FolderObserving {
    private let access: any FileAccessing
    private var watches: [UUID: FolderWatch] = [:]
    private var generation = 0
    private var partials: [UUID: [String: FolderWatch]] = [:]
    private var callbacks: [UUID: @Sendable (UUID, Bool) -> Void] = [:]
    init(access: any FileAccessing = LocalFileAccess()) { self.access = access }
    func start(_ folder: FileReference, changed: @escaping @Sendable (UUID, Bool) -> Void) async throws {
        guard watches[folder.id] == nil else { return }
        let version = generation
        let file = try await access.resolve(folder)
        guard !Task.isCancelled, generation == version else { file.close(); throw CancellationError() }
        guard file.details.isDirectory else { file.close(); throw FileToolError.invalidDestination }
        watches[folder.id] = try FolderWatch(file: file) { valid in changed(folder.id, valid) }
        callbacks[folder.id] = changed
    }
    func updatePartials(_ folder: FileReference, files: [DownloadFile]) async {
        guard watches[folder.id] != nil, let callback = callbacks[folder.id] else { return }
        let version = generation
        guard let parent = try? await access.resolve(folder) else { return }; defer { parent.close() }
        guard !Task.isCancelled, generation == version else { return }
        let names = Set(files.filter { $0.partial && LocalFileOperations.validName($0.name) }.prefix(25).map(\.name))
        for old in Array(partials[folder.id]?.keys ?? Dictionary<String, FolderWatch>().keys) where !names.contains(old) {
            partials[folder.id]?.removeValue(forKey: old)?.stop()
        }
        for name in names where partials[folder.id]?[name] == nil {
            guard let child = try? ScopedFile(url: parent.url.appendingPathComponent(name)) else { continue }
            // Any child write/rename/delete asks for a parent scan; it never
            // marks the chosen folder itself unavailable.
            if let watch = try? FolderWatch(file: child, changed: { _ in callback(folder.id, true) }) {
                partials[folder.id, default: [:]][name] = watch
            }
        }
    }
    func stop(_ id: UUID) {
        generation += 1; partials.removeValue(forKey: id)?.values.forEach { $0.stop() }
        callbacks[id] = nil; watches.removeValue(forKey: id)?.stop()
    }
    func stopAll() {
        generation += 1; partials.values.forEach { $0.values.forEach { $0.stop() } }; partials = [:]; callbacks = [:]
        watches.values.forEach { $0.stop() }; watches.removeAll()
    }
}

// Kernel directory notifications plus one debounced scan, never a polling loop.
private final class FolderWatch: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private let file: ScopedFile
    private let queue = DispatchQueue(label: "sieghart.files.folder", qos: .utility)
    private let lock = NSLock()
    private var pending: DispatchWorkItem?
    private var stopped = false
    private var invalidated = false
    init(file: ScopedFile, changed: @escaping @Sendable (Bool) -> Void) throws {
        self.file = file
        let descriptor = open(file.url.path, O_EVTONLY)
        guard descriptor >= 0 else { file.close(); throw FileToolError.access }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .revoke], queue: queue)
        source.setCancelHandler { close(descriptor); file.close() }
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let invalid = !self.source.data.intersection([.rename, .delete, .revoke]).isEmpty
            self.lock.withLock {
                guard !self.stopped else { return }
                self.invalidated = self.invalidated || invalid
                guard self.pending == nil else { return }
                let next = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let valid: Bool? = self.lock.withLock {
                        self.pending = nil; guard !self.stopped else { return nil }
                        return !self.invalidated
                    }
                    if let valid { changed(valid) }
                }
                self.pending = next
                self.queue.asyncAfter(deadline: .now() + 0.65, execute: next)
            }
        }
        source.resume()
    }
    func stop() { lock.withLock { guard !stopped else { return }; stopped = true; pending?.cancel(); source.cancel() } }
    deinit { stop() }
}
