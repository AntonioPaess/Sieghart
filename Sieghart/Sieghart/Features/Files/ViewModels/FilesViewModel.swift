import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor final class FilesViewModel: ObservableObject {
    enum Page: String, CaseIterable { case shelf = "Shelf", downloads = "Downloads", helpers = "File helpers" }
    @Published var page = Page.shelf
    @Published private(set) var shelf: [FileReference] = []
    @Published private(set) var folders: [WatchedFolder] = []
    @Published private(set) var recent: [DownloadFile] = []
    @Published private(set) var problems: [UUID: String] = [:]
    @Published private(set) var status = "Keep a file nearby."
    @Published private(set) var loaded = false
    @Published private(set) var needsReset = false
    @Published private(set) var isBusy = false
    @Published var previewURL: URL? { didSet { if previewURL == nil { previewScope?.close(); previewScope = nil } } }
    @Published private(set) var resolvedURLs: [UUID: URL] = [:]
    @Published private(set) var cutFiles: [FileReference] = []
    @Published private(set) var renameTarget: FileReference?
    @Published private(set) var pendingReview: ReviewedFileOperation?
    @Published private(set) var imageContents: DiskImageContents?
    @Published private(set) var pendingInstall: DiskImageInstallPlan?
    @Published var observationEnabled: Bool { didSet {
        defaults.set(observationEnabled, forKey: "files.watchEnabled")
        if lifecycleStarted { updateObservation() }
    } }
    let events: CompanionEventCenter
    let access: any FileAccessing
    private let store: any FilesStoring
    private let observer: any FolderObserving
    private let operations: any FileOperating
    private let finder: any FinderSelecting
    private let installer: any DiskImageInstalling
    private let defaults: UserDefaults
    private let observesSystem: Bool
    private var revision: UInt64 = 0
    private var persistence: Task<Void, Never>?
    private var restoreTask: Task<FilesSnapshot, Error>?
    private var watchTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var folderTasks: [UUID: Task<Void, Never>] = [:]
    private var baseline: [UUID: [DownloadFile]] = [:]
    private var leases: [UUID: ScopedFile] = [:]
    private var surfaces: Set<UUID> = []
    private var accessGeneration = 0
    private var previewScope: ScopedFile?
    private var systemObservers: [NSObjectProtocol] = []
    private var lifecycleStarted = false
    private var generation = 0
    private var suspended = false
    init(defaults: UserDefaults = .standard, events: CompanionEventCenter = CompanionEventCenter(),
         access: any FileAccessing = LocalFileAccess(), store: any FilesStoring = LocalFilesStore(),
         observer: (any FolderObserving)? = nil, operations: (any FileOperating)? = nil,
         finder: any FinderSelecting = FinderFileSelection(), installer: (any DiskImageInstalling)? = nil, observesSystem: Bool = true) {
        self.defaults = defaults; self.events = events; self.access = access; self.store = store
        self.observer = observer ?? LocalFolderObserver(access: access)
        self.operations = operations ?? LocalFileOperations(access: access)
        self.finder = finder; self.installer = installer ?? LocalDiskImageInstaller(access: access); self.observesSystem = observesSystem
        observationEnabled = defaults.bool(forKey: "files.watchEnabled")
    }
    func restore() async {
        guard !loaded else { return }
        if restoreTask == nil { let store = store; restoreTask = Task { try await store.load() } }
        do {
            let snapshot = try await restoreTask!.value
            guard !loaded else { return }
            shelf = Array(snapshot.shelf.prefix(40)); folders = Array(snapshot.folders.prefix(5))
            recent = Array(snapshot.recent.prefix(100)); loaded = true; status = "Files stay on this Mac."
        } catch { loaded = true; needsReset = true; status = "Saved file references could not be read. Reset the list to start again; your original files stay intact." }
        restoreTask = nil
    }
    func beginSurface(_ id: UUID) async { surfaces.insert(id); await restore(); await prepareShelfAccess() }
    func endSurface(_ id: UUID) { surfaces.remove(id); if surfaces.isEmpty { endShelfAccess() } }
    func report(_ message: String) { status = message }
    func copyText(_ text: String) async {
        guard ClipboardPayload(kind: .text, text: text).valid else { status = "This text is too large to copy."; return }
        status = await SystemClipboardAccess().write(ClipboardPayload(kind: .text, text: text)) != nil ? "Copied." : "Could not copy."
    }
    func resetSavedList() { shelf = []; folders = []; recent = []; endShelfAccess(); needsReset = false; save(); updateObservation() }
    func startLifecycle() {
        guard !lifecycleStarted else { return }; lifecycleStarted = true
        if observesSystem {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
                systemObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    let sleep = notification.name == NSWorkspace.willSleepNotification
                    Task { @MainActor [weak self] in self?.suspended = sleep; self?.updateObservation() }
                })
            }
        }
        updateObservation()
    }
    private func updateObservation() {
        generation += 1; let version = generation
        watchTask?.cancel(); folderTasks.values.forEach { $0.cancel() }; folderTasks = [:]; baseline = [:]
        watchTask = Task { [weak self] in
            guard let self else { return }
            await self.observer.stopAll()
            await self.restore()
            guard !Task.isCancelled, self.generation == version, self.lifecycleStarted,
                  self.observationEnabled, !self.suspended, !self.needsReset else { return }
            for folder in self.folders {
                do {
                    try await self.observer.start(folder.reference) { [weak self] id, valid in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == version, self.observationEnabled, !self.suspended else { return }
                            if valid { self.refreshFolder(id) }
                            else { await self.observer.stop(id); self.problems[id] = "Folder unavailable. Choose it again." }
                        }
                    }
                    guard !Task.isCancelled, self.generation == version else { return }
                    self.refreshFolder(folder.id)
                } catch { if !Task.isCancelled { self.problems[folder.id] = error.localizedDescription } }
            }
        }
    }
    func refreshDownloads() { for folder in folders { refreshFolder(folder.id) } }
    private func refreshFolder(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        let version = generation
        folderTasks[id]?.cancel()
        folderTasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let files = try await self.access.list(folder.reference)
                guard !Task.isCancelled, self.generation == version, self.folders.contains(where: { $0.id == id }) else { return }
                self.acceptFolderScan(id, files: files)
                if self.observationEnabled { await self.observer.updatePartials(folder.reference, files: files) }
            } catch { if !Task.isCancelled, self.generation == version { self.problems[id] = error.localizedDescription } }
        }
    }
    func acceptFolderScan(_ id: UUID, files: [DownloadFile]) {
        guard folders.contains(where: { $0.id == id }) else { return }
        let previous = baseline[id]
        let partialNames = Set((previous ?? []).filter(\.partial).map(\.finalName))
        let currentPartials = Set(files.filter(\.partial).map(\.finalName))
        var updated = files
        for index in updated.indices {
            let old = recent.first { $0.id == updated[index].id }
            let sameFile = old?.signature == updated[index].signature
            let formerFinal = previous?.first { !$0.partial && $0.name == updated[index].name }
            let newFinal = formerFinal == nil || formerFinal?.signature != updated[index].signature
            let completed = previous != nil && partialNames.contains(updated[index].name) && !currentPartials.contains(updated[index].name)
                && newFinal && !updated[index].partial && updated[index].available && updated[index].bytes > 0
            updated[index].readyAfterPartial = (sameFile && old?.readyAfterPartial == true) || completed
            if completed {
                let item = updated[index]
                events.post(.downloadReady, key: "download:\(item.id):\(item.signature)", title: "Download ready", detail: item.name)
            }
        }
        baseline[id] = files; problems[id] = nil
        // Missing former files remain useful history, marked unavailable.
        let names = Set(files.map(\.name))
        let missing = recent.filter { $0.folderID == id && !names.contains($0.name) }.map { item in var item = item; item.available = false; return item }
        recent = Array((recent.filter { $0.folderID != id } + updated + missing).sorted { $0.modifiedAt > $1.modifiedAt }.prefix(100))
        save()
    }
    func add(_ urls: [URL], announce: Bool = true) async {
        await restore(); guard !needsReset else { return }
        var prepared: [FileReference] = []
        for url in urls.prefix(50) {
            do {
                try Task.checkCancellation()
                prepared.append(try await access.reference(for: url))
                try Task.checkCancellation()
            } catch is CancellationError { return }
            catch { status = error.localizedDescription }
        }
        _ = await addPrepared(prepared, announce: announce)
    }
    @discardableResult func addPrepared(_ references: [FileReference], announce: Bool = true) async -> [FileReference] {
        await restore(); guard !needsReset, !Task.isCancelled else { return [] }
        var added = 0, rejected = 0, kept: [FileReference] = []
        var names: [String] = []
        for original in references.prefix(50) {
                guard !kept.contains(where: { $0.resourceID == original.resourceID }) else { continue }
                var reference = original
                if let existing = shelf.firstIndex(where: { $0.resourceID == reference.resourceID }) {
                    reference.id = shelf[existing].id; shelf[existing] = reference
                } else if shelf.count < 40 { shelf.insert(reference, at: 0); added += 1 }
                else { status = "The shelf holds up to forty files. Remove a reference to make room."; rejected += 1; break }
                names.append(reference.name); kept.append(reference)
        }
        if added > 0 {
            status = "\(added) file\(added == 1 ? "" : "s") added to the shelf." + (rejected > 0 ? " \(rejected) could not be added." : "")
            if announce { events.post(.fileReceived, key: "shelf-batch:\(UUID())", title: added == 1 ? "File kept nearby" : "\(added) files kept nearby", detail: names.prefix(3).joined(separator: ", ")) }
        }
        save(); await prepareShelfAccess()
        return kept
    }
    func addFolder(_ url: URL) async {
        await restore(); guard !needsReset else { return }
        do {
            let reference = try await access.reference(for: url)
            guard reference.isDirectory else { throw FileToolError.invalidDestination }
            if folders.contains(where: { $0.reference.resourceID == reference.resourceID }) { status = "This folder is already selected."; return }
            guard folders.count < 5 else { throw FileToolError.message("Choose up to five folders.") }
            folders.append(WatchedFolder(reference: reference)); save()
            observationEnabled = true
            status = "Watching only the folders you chose."
            if !lifecycleStarted { refreshFolder(reference.id) }
        } catch { status = error.localizedDescription }
    }
    func removeFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }; recent.removeAll { $0.folderID == id }; problems[id] = nil
        save(); updateObservation()
    }
    func remove(_ id: UUID) {
        shelf.removeAll { $0.id == id }; leases.removeValue(forKey: id)?.close(); resolvedURLs[id] = nil; problems[id] = nil
        save(); status = "Reference removed. The original file stays intact."
    }
    func clearShelf() { shelf = []; endShelfAccess(); save(); status = "Shelf cleared. Original files stay intact." }
    func clearDownloadHistory() { recent = []; save(); status = "Recent list cleared. Downloaded files stay intact." }
    func relink(_ id: UUID, to url: URL) async {
        do {
            var replacement = try await access.reference(for: url); replacement.id = id
            if let i = shelf.firstIndex(where: { $0.id == id }) { shelf[i] = replacement }
            else if let i = folders.firstIndex(where: { $0.id == id }) {
                guard replacement.isDirectory else { throw FileToolError.invalidDestination }; folders[i].reference = replacement
                recent.removeAll { $0.folderID == id }; updateObservation()
            }
            endShelfAccess(); problems[id] = nil; save(); await prepareShelfAccess()
        } catch { status = error.localizedDescription }
    }
    func prepareShelfAccess() async {
        guard !surfaces.isEmpty else { return }
        let version = accessGeneration
        for reference in shelf {
            guard leases[reference.id] == nil else { continue }
            do {
                let file = try await access.resolve(reference)
                guard !Task.isCancelled, version == accessGeneration, !surfaces.isEmpty,
                      shelf.contains(reference) else { file.close(); continue }
                if file.details.name != reference.name || file.url.path != reference.pathHint,
                   var refreshed = try? await access.reference(for: file.url) {
                    guard !Task.isCancelled, version == accessGeneration, let index = shelf.firstIndex(of: reference) else { file.close(); continue }
                    refreshed.id = reference.id; refreshed.addedAt = reference.addedAt
                    shelf[index] = refreshed; save()
                }
                leases[reference.id] = file; resolvedURLs[reference.id] = file.url; problems[reference.id] = nil
            } catch { problems[reference.id] = error.localizedDescription }
        }
    }
    func endShelfAccess() { accessGeneration += 1; leases.values.forEach { $0.close() }; leases = [:]; resolvedURLs = [:] }
    func open(_ reference: FileReference, reveal: Bool = false, preview: Bool = false) async {
        do {
            let file = try await access.resolve(reference)
            if preview {
                previewScope?.close(); previewScope = file; previewURL = file.url
            } else {
                defer { file.close() }
                if reveal { NSWorkspace.shared.activateFileViewerSelecting([file.url]); status = "Shown in Finder." }
                else { status = NSWorkspace.shared.open(file.url) ? "Opened \(file.details.name)." : "This file could not be opened." }
            }
        } catch { problems[reference.id] = error.localizedDescription; status = error.localizedDescription }
    }
    func downloadReference(_ item: DownloadFile) async throws -> FileReference {
        guard !item.partial, item.available, let folder = folders.first(where: { $0.id == item.folderID }) else { throw FileToolError.missing }
        let file = try await access.resolve(folder.reference); defer { file.close() }
        guard LocalFileOperations.validName(item.name) else { throw FileToolError.invalidName }
        return try await access.reference(for: file.url.appendingPathComponent(item.name))
    }
    func keepDownload(_ item: DownloadFile) async {
        do { let ref = try await downloadReference(item); await add([URL(fileURLWithPath: ref.pathHint)]) }
        catch { status = error.localizedDescription }
    }
    func openDownload(_ item: DownloadFile, reveal: Bool = false) async {
        do { await open(try await downloadReference(item), reveal: reveal) } catch { status = error.localizedDescription }
    }
    func chooseFiles(folder: Bool = false) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = folder; panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = !folder; panel.prompt = folder ? "Watch this folder" : "Keep nearby"
        panel.begin { [weak self] response in
            guard response == .OK else { return }; let urls = panel.urls
            Task { @MainActor [weak self] in if folder, let url = urls.first { await self?.addFolder(url) } else { await self?.add(urls) } }
        }
    }
    func chooseRelink(_ reference: FileReference) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = reference.isDirectory; panel.canChooseFiles = !reference.isDirectory; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in await self?.relink(reference.id, to: url) }
        }
    }
    func cut(_ references: [FileReference]) { cutFiles = Array(references.prefix(50)); pendingReview = nil; status = "\(cutFiles.count) file(s) prepared to move. Choose a destination and review." }
    func chooseCutFiles() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true; panel.prompt = "Prepare to move"
        panel.begin { [weak self] response in
            guard response == .OK else { return }; let urls = panel.urls
            self?.run {
                guard let self else { return }; var references: [FileReference] = []
                for url in urls.prefix(50) { references.append(try await self.access.reference(for: url)) }
                self.cut(references)
            }
        }
    }
    func cancelCut() { cutFiles = []; pendingReview = nil; status = "Move cancelled. Files stayed in place." }
    func cutFinderSelection() { run {
        let urls = try await self.finder.selection()
        var refs: [FileReference] = []
        for url in urls { refs.append(try await self.access.reference(for: url)) }
        self.cut(refs)
    } }
    func prepareFinderRename() { run {
        let urls = try await self.finder.selection()
        guard urls.count == 1, let url = urls.first else { throw FileToolError.message("Select one file in Finder to rename.") }
        self.renameTarget = try await self.access.reference(for: url)
        self.page = .helpers; self.status = "Enter a new name, then review the rename."
    } }
    func chooseMoveDestination(conflict: FileConflictPolicy) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Review destination"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.run { guard let self else { return }; try await self.reviewMove(to: url, conflict: conflict) }
        }
    }
    func useFinderDestination(conflict: FileConflictPolicy) {
        guard !cutFiles.isEmpty else { status = "Prepare some files to move first."; return }
        run { try await self.reviewMove(to: self.finder.insertionFolder(), conflict: conflict) }
    }
    func reviewMove(to url: URL, conflict: FileConflictPolicy) async throws {
        let dest = try await access.reference(for: url)
        pendingReview = try await operations.review(.move, sources: cutFiles, destination: dest, rename: nil, conflict: conflict)
        status = "Review the move below. Files stay in place until you confirm."
    }
    func reviewRename(_ reference: FileReference, name: String, conflict: FileConflictPolicy) { run {
        let file = try await self.access.resolve(reference); defer { file.close() }
        let dest = try await self.access.reference(for: file.url.deletingLastPathComponent())
        self.pendingReview = try await self.operations.review(.rename, sources: [reference], destination: dest, rename: name, conflict: conflict)
    } }
    func confirmReview() { guard let review = pendingReview else { return }; pendingReview = nil
        run {
            let changed = try await self.operations.perform(review)
            for ref in changed {
                if let i = self.shelf.firstIndex(where: { $0.id == ref.id }) { self.shelf[i] = ref }
            }
            self.events.post(.fileReady, key: "operation:\(review.id)", title: "\(review.kind.rawValue) complete", detail: changed.prefix(3).map(\.name).joined(separator: ", "))
            self.cutFiles = []; self.endShelfAccess(); self.save(); await self.prepareShelfAccess()
            if review.kind == .rename { self.renameTarget = nil }
            self.status = "\(review.kind.rawValue) complete."
        }
    }
    func cancelReview() { pendingReview = nil; pendingInstall = nil; status = "Review cancelled. No file action was executed." }
    func chooseDiskImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.diskImage]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.run { guard let self else { return }; self.imageContents = try await self.installer.inspect(self.access.reference(for: url)); self.status = "Choose the app and a destination, then review the install." }
        }
    }
    func chooseInstallDestination(app: String, conflict: FileConflictPolicy) {
        guard let contents = imageContents else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Review install"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.run { guard let self else { return }; self.pendingInstall = try await self.installer.review(session: contents.id, app: app, destination: self.access.reference(for: url), conflict: conflict) }
        }
    }
    func confirmInstall() { guard let plan = pendingInstall else { return }; pendingInstall = nil
        run {
            let ref = try await self.installer.install(plan); self.imageContents = nil
            self.status = "Installed \(ref.name). Open it yourself when you're ready."
            self.events.post(.fileReady, key: "install:\(plan.id)", title: "App copied", detail: ref.name)
        }
    }
    func closeDiskImage() { imageContents = nil; pendingInstall = nil; Task { await installer.close() } }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }; isBusy = true
        actionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            do { try await action() }
            catch is CancellationError { self.status = "Action cancelled." }
            catch { self.status = error.localizedDescription; self.events.post(.failed, key: "failure:\(UUID())", title: "File action stopped", detail: error.localizedDescription) }
        }
    }
    func cancelAction() { actionTask?.cancel() }
    private func save() {
        guard loaded, !needsReset else { return }; revision += 1
        let snapshot = FilesSnapshot(shelf: shelf, folders: folders, recent: recent), revision = revision, store = store
        persistence?.cancel()
        persistence = Task { [weak self] in
            do { try await store.save(snapshot, revision: revision) } catch { self?.status = "The list changed but could not be saved." }
        }
    }
    func flush() async { await persistence?.value }
    func stopLifecycle() {
        lifecycleStarted = false; generation += 1; watchTask?.cancel(); folderTasks.values.forEach { $0.cancel() }
        folderTasks = [:]; baseline = [:]
        systemObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; systemObservers = []
        Task { await observer.stopAll() }
    }
    func shutdownAndFlush() async {
        stopLifecycle(); actionTask?.cancel(); await actionTask?.value
        await observer.stopAll(); await installer.close(); endShelfAccess(); previewScope?.close(); previewScope = nil; previewURL = nil; await flush()
    }
}
