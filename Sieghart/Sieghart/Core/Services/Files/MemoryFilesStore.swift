import Foundation

actor MemoryFilesStore: FilesStoring {
    private var snapshot: FilesSnapshot
    private var revision: UInt64 = 0
    init(_ snapshot: FilesSnapshot = FilesSnapshot()) { self.snapshot = snapshot }
    func load() -> FilesSnapshot { snapshot }
    func save(_ snapshot: FilesSnapshot, revision: UInt64) {
        guard revision >= self.revision else { return }; self.snapshot = snapshot; self.revision = revision
    }
}
actor InactiveFolderObserver: FolderObserving {
    func start(_ folder: FileReference, changed: @escaping @Sendable (UUID, Bool) -> Void) throws { throw FileToolError.access }
    func stop(_ id: UUID) {}
    func stopAll() {}
}
