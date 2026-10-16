import Foundation
import Darwin

struct DiskImageCandidate: Identifiable, Sendable { var id: String; var name: String }
struct DiskImageContents: Identifiable, Sendable { var id: UUID; var imageName: String; var apps: [DiskImageCandidate] }
struct DiskImageInstallPlan: Identifiable, Sendable {
    var id = UUID()
    var session: UUID
    var candidate: DiskImageCandidate
    var destination: FileReference
    var targetName: String
}
protocol DiskImageInstalling: Sendable {
    func inspect(_ image: FileReference) async throws -> DiskImageContents
    func review(session: UUID, app: String, destination: FileReference, conflict: FileConflictPolicy) async throws -> DiskImageInstallPlan
    func install(_ plan: DiskImageInstallPlan) async throws -> FileReference
    func close() async
}

actor LocalDiskImageInstaller: DiskImageInstalling {
    private let access: any FileAccessing
    private let process: any ToolProcessRunning
    private var session: (id: UUID, root: URL, image: ScopedFile, apps: [String: URL])?
    init(access: any FileAccessing = LocalFileAccess(), process: any ToolProcessRunning = NativeToolProcess()) {
        self.access = access; self.process = process
    }
    func inspect(_ image: FileReference) async throws -> DiskImageContents {
        await close()
        let file = try await access.resolve(image)
        guard file.url.pathExtension.lowercased() == "dmg" else { file.close(); throw FileToolError.unsupported }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sieghart-dmg-\(UUID())", isDirectory: true)
        let mount = root.appendingPathComponent("volume", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let result = try await process.run(URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, file.url.path])
            guard result.status == 0 else { throw FileToolError.message("This disk image could not be mounted. It may be encrypted, unsupported or damaged.") }
            try Task.checkCancellation()
            let candidates = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                .filter { url in
                    guard url.pathExtension.lowercased() == "app", let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
                    guard values.isDirectory == true, values.isSymbolicLink != true,
                          let bundle = Bundle(url: url), bundle.bundleIdentifier?.isEmpty == false,
                          let executable = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
                          LocalFileOperations.validName(executable) else { return false }
                    return FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/" + executable).path)
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !candidates.isEmpty, candidates.count <= 20 else { throw FileToolError.message("No supported app bundle was found at the top of this disk image.") }
            let id = UUID(), apps = Dictionary(uniqueKeysWithValues: candidates.map { ($0.lastPathComponent, $0) })
            session = (id, root, file, apps)
            return DiskImageContents(id: id, imageName: image.name, apps: candidates.map { DiskImageCandidate(id: $0.lastPathComponent, name: $0.lastPathComponent) })
        } catch {
            // The mount point is owned and known even if attach is interrupted.
            await cleanup(root: root, file: file)
            throw error
        }
    }
    func review(session id: UUID, app: String, destination: FileReference, conflict: FileConflictPolicy) async throws -> DiskImageInstallPlan {
        guard let session, session.id == id, session.apps[app] != nil else { throw FileToolError.changed }
        let folder = try await access.resolve(destination); defer { folder.close() }
        guard folder.details.isDirectory, FileManager.default.isWritableFile(atPath: folder.url.path),
              !folder.url.standardizedFileURL.path.hasPrefix(session.root.path) else { throw FileToolError.invalidDestination }
        var name = app
        if FileManager.default.fileExists(atPath: folder.url.appendingPathComponent(name).path) {
            guard conflict == .keepBoth else { throw FileToolError.conflict(name) }
            name = LocalFileOperations.availableName(name, in: folder.url)
        }
        return DiskImageInstallPlan(session: id, candidate: DiskImageCandidate(id: app, name: app), destination: destination, targetName: name)
    }
    func install(_ plan: DiskImageInstallPlan) async throws -> FileReference {
        guard let session, session.id == plan.session, let source = session.apps[plan.candidate.id],
              LocalFileOperations.validName(plan.targetName), plan.targetName.hasSuffix(".app") else { throw FileToolError.changed }
        let folder = try await access.resolve(plan.destination); defer { folder.close() }
        guard !folder.url.standardizedFileURL.path.hasPrefix(session.root.path) else { throw FileToolError.invalidDestination }
        let target = folder.url.appendingPathComponent(plan.targetName)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw FileToolError.conflict(plan.targetName) }
        let staged = folder.url.appendingPathComponent(".sieghart-install-\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: staged) }
        try Task.checkCancellation()
        try FileManager.default.copyItem(at: source, to: staged)
        try Task.checkCancellation()
        // moveItem fails on a destination created since review. No overwrite,
        // source-image deletion or automatic app execution is performed.
        try FileManager.default.moveItem(at: staged, to: target)
        let installed = try await access.reference(for: target)
        await close()
        return installed
    }
    func close() async {
        guard let saved = session else { return }; session = nil
        await cleanup(root: saved.root, file: saved.image)
    }
    private func cleanup(root: URL, file: ScopedFile) async {
        let runner = process, mount = root.appendingPathComponent("volume")
        // Teardown must run even when the owning user action was cancelled.
        let result = await Task.detached(priority: .utility) {
            try? await runner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["detach", mount.path])
        }.value
        // Never recursively remove a volume that is still mounted. A failed
        // attach can leave an ordinary empty folder; compare its device with
        // its owned parent before cleaning that case up.
        var mounted = stat(), parent = stat()
        let ordinaryFolder = stat(mount.path, &mounted) == 0 && stat(root.path, &parent) == 0 && mounted.st_dev == parent.st_dev
        if result?.status == 0 || ordinaryFolder { try? FileManager.default.removeItem(at: root) }
        file.close()
    }
}
