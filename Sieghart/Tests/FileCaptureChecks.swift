import AppKit
import CoreImage
import CoreText
import ImageIO
import Foundation

private actor RecordingObserver: FolderObserving {
    var watched: Set<UUID> = []
    var stopped = 0
    func start(_ folder: FileReference, changed: @escaping @Sendable (UUID, Bool) -> Void) { watched.insert(folder.id) }
    func stop(_ id: UUID) { watched.remove(id) }
    func stopAll() { watched = []; stopped += 1 }
    func ids() -> Set<UUID> { watched }
}
private actor WatchCounter { var count = 0; func bump() { count += 1 }; func value() -> Int { count } }
private actor TestDropReader: FileDropReading {
    let urls: [URL]
    init(_ urls: [URL]) { self.urls = urls }
    func read(pasteboard: String, changeCount: Int) -> [URL] { urls }
}
private actor DelayedDropAccess: FileAccessing {
    let native = LocalFileAccess()
    func reference(for url: URL) async throws -> FileReference {
        if url.lastPathComponent == "slow-drop.txt" { try await Task.sleep(for: .milliseconds(250)) }
        return try await native.reference(for: url)
    }
    func resolve(_ reference: FileReference) async throws -> ScopedFile { try await native.resolve(reference) }
    func list(_ folder: FileReference) async throws -> [DownloadFile] { try await native.list(folder) }
}
private actor TestFinder: FinderSelecting {
    let source: URL, destination: URL
    var reads = 0
    init(source: URL, destination: URL) { self.source = source; self.destination = destination }
    func selection() -> [URL] { reads += 1; return [source] }
    func insertionFolder() -> URL { reads += 1; return destination }
    func count() -> Int { reads }
}
private actor RollbackAccess: FileAccessing {
    let native = LocalFileAccess()
    var removeOnResolve = false
    func arm() { removeOnResolve = true }
    func reference(for url: URL) async throws -> FileReference { try await native.reference(for: url) }
    func list(_ folder: FileReference) async throws -> [DownloadFile] { try await native.list(folder) }
    func resolve(_ reference: FileReference) async throws -> ScopedFile {
        let scoped = try await native.resolve(reference)
        if removeOnResolve && reference.name == "rollback-b.txt" { removeOnResolve = false; try FileManager.default.removeItem(at: scoped.url) }
        return scoped
    }
}
private actor FixtureImageProcess: ToolProcessRunning {
    var mounts: [URL] = []
    var detachCount = 0
    var cancelAttach = false
    func shouldCancel() { cancelAttach = true }
    func state() -> ([URL], Int) { (mounts, detachCount) }
    func run(_ executable: URL, arguments: [String]) throws -> ToolProcessResult {
        guard executable.lastPathComponent == "hdiutil" else { preconditionFailure("Never execute a native capture or app from this fixture") }
        if arguments.first == "attach" {
            let index = arguments.firstIndex(of: "-mountpoint")!, mount = URL(fileURLWithPath: arguments[index + 1])
            mounts.append(mount)
            let app = mount.appendingPathComponent("Fixture.app/Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": "org.sieg.fixture", "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
            let executable = app.appendingPathComponent("MacOS/Fixture")
            try Data("fixture bytes, never execute".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            if cancelAttach { throw CancellationError() }
        } else if arguments.first == "detach" { detachCount += 1 }
        return ToolProcessResult(status: 0, output: Data(), error: Data())
    }
}
@MainActor private final class TestTaskNotifier: CompanionTaskNotifying {
    var events: [CompanionTaskEvent] = []
    func post(_ event: CompanionTaskEvent) async { events.append(event) }
    func requestAccess() async -> Bool { true }
}
@MainActor private final class TestPlainBoard: PlainClipboardAccess {
    var value = PlainClipboardSnapshot(changeCount: 1, text: "Keep literal $() and accents: ação", items: [
        "public.utf8-plain-text": Data("Keep literal $() and accents: ação".utf8), "public.rtf": Data("rich original".utf8)
    ].map { [$0.key: $0.value] })
    var reads = 0
    func snapshot() async throws -> PlainClipboardSnapshot { reads += 1; return value }
    func writePlain(_ saved: PlainClipboardSnapshot) async throws -> Int {
        guard value.changeCount == saved.changeCount else { throw FileToolError.changed }
        value.changeCount += 1; value.items = [["public.utf8-plain-text": Data(saved.text.utf8)]]; return value.changeCount
    }
    func restore(_ saved: PlainClipboardSnapshot, ifUnchanged count: Int) async -> Bool {
        guard value.changeCount == count else { return false }; value = saved; return true
    }
    func userCopies() { value = PlainClipboardSnapshot(changeCount: value.changeCount + 1, text: "new user copy", items: [["public.utf8-plain-text": Data("new user copy".utf8)]]) }
}
@MainActor private final class TestPasteTarget: PlainPasteTargeting {
    var allowed = true, successful = true
    var onPaste: (() -> Void)?
    func canPaste(to pid: Int32) -> Bool { allowed }
    func activate(_ pid: Int32) -> Bool { allowed }
    func paste(to pid: Int32) -> Bool { onPaste?(); return successful }
}
@MainActor private final class TestClipboard: ClipboardAccess {
    var writes: [ClipboardPayload] = []
    func read(after changeCount: Int?, includeMedia: Bool) async -> ClipboardRead? { nil }
    func write(_ payload: ClipboardPayload) async -> Int? { writes.append(payload); return writes.count }
}
private actor TestCaptureBackend: CaptureProviding {
    var allowed = true
    var selections = 0, requests = 0
    func deny() { allowed = false }
    func counters() -> (Int, Int) { (selections, requests) }
    func accessState() -> CaptureAccessState { allowed ? .allowed : .needsAccess }
    func requestAccess() -> Bool { requests += 1; return false }
    func selectRegion() async throws -> CapturedImage { selections += 1; try await Task.sleep(for: .seconds(20)); throw CaptureToolError.cancelled }
    func readImage(_ data: Data) async throws -> CapturedImage { try await MacCaptureBackend().readImage(data) }
    func recognize(_ image: CapturedImage) -> CaptureReading { CaptureReading(text: "offline fixture", qrPayloads: ["https://example.com"]) }
    func annotate(_ image: CapturedImage, annotations: [CaptureAnnotation]) async throws -> Data { try await MacCaptureBackend().annotate(image, annotations: annotations) }
}
@MainActor private final class TestSampler: ColorSampling {
    func sample() async -> SampledColor? { SampledColor(red: 1, green: 0.5, blue: 0) }
}

@main struct FileCaptureChecks {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sieg-s5-check-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "sieg.s5.check.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0, forKey: "calendar.quietStart"); defaults.set(0, forKey: "calendar.quietEnd")
        let native = LocalFileAccess(), operations = LocalFileOperations(access: native)
        let source = folder.appendingPathComponent("literal $() ação.txt"), destination = folder.appendingPathComponent("destination", isDirectory: true)
        try Data("original bytes".utf8).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceRef = try await native.reference(for: source), folderRef = try await native.reference(for: folder), destRef = try await native.reference(for: destination)
        let scope = try await native.resolve(sourceRef); precondition(scope.url.resolvingSymlinksInPath() == source.resolvingSymlinksInPath() && scope.details.resourceID == sourceRef.resourceID); scope.close()
        var review = try await operations.review(.rename, sources: [sourceRef], destination: folderRef, rename: "renamed.txt", conflict: .cancel)
        precondition(FileManager.default.fileExists(atPath: source.path), "Review does not execute")
        let renamed = try await operations.perform(review)[0]
        precondition(renamed.id == sourceRef.id && renamed.name == "renamed.txt")
        let renamedData = try Data(contentsOf: URL(fileURLWithPath: renamed.pathHint)); precondition(renamedData == Data("original bytes".utf8))
        for invalid in ["../escape", "a/b", "", ".", "..", "bad\nname"] { precondition(!LocalFileOperations.validName(invalid)) }
        try Data("existing".utf8).write(to: destination.appendingPathComponent("renamed.txt"))
        do { _ = try await operations.review(.move, sources: [renamed], destination: destRef, rename: nil, conflict: .cancel); preconditionFailure("Collision must stop") }
        catch FileToolError.conflict {}
        review = try await operations.review(.move, sources: [renamed], destination: destRef, rename: nil, conflict: .keepBoth)
        precondition(review.targetNames == ["renamed 2.txt"])
        let moved = try await operations.perform(review)[0]
        let existingData = try Data(contentsOf: destination.appendingPathComponent("renamed.txt")); precondition(existingData == Data("existing".utf8))
        let movedData = try Data(contentsOf: URL(fileURLWithPath: moved.pathHint)); precondition(movedData == Data("original bytes".utf8))
        review = try await operations.review(.rename, sources: [moved], destination: destRef, rename: "stale.txt", conflict: .cancel)
        try Data("changed after review".utf8).write(to: URL(fileURLWithPath: moved.pathHint))
        do { _ = try await operations.perform(review); preconditionFailure("Stale review must stop") } catch FileToolError.changed {}
        let a = folder.appendingPathComponent("rollback-a.txt"), b = folder.appendingPathComponent("rollback-b.txt")
        try Data("A".utf8).write(to: a); try Data("B".utf8).write(to: b)
        let rollback = RollbackAccess(), rops = LocalFileOperations(access: rollback)
        let refs = [try await rollback.reference(for: a), try await rollback.reference(for: b)]
        review = try await rops.review(.move, sources: refs, destination: destRef, rename: nil, conflict: .cancel)
        await rollback.arm()
        do { _ = try await rops.perform(review); preconditionFailure("Missing second file must stop the batch") } catch {}
        precondition(FileManager.default.fileExists(atPath: a.path) && !FileManager.default.fileExists(atPath: destination.appendingPathComponent(a.lastPathComponent).path), "First move is rolled back")
        do { _ = try await operations.review(.move, sources: [folderRef], destination: destRef, rename: nil, conflict: .cancel); preconditionFailure("Cannot move a parent into its child") }
        catch FileToolError.invalidDestination {}
        print("PASS: bookmark identity, literal names, reviewed moves/rename, conflicts, stale review and rollback")

        let notifier = TestTaskNotifier(), events = CompanionEventCenter(defaults: defaults, notifier: notifier)
        events.setNotifications(true, for: .downloads)
        let observer = RecordingObserver(), store = MemoryFilesStore(), model = FilesViewModel(defaults: defaults, events: events, access: native, store: store, observer: observer, observesSystem: false)
        await model.add([URL(fileURLWithPath: moved.pathHint)])
        await model.flush()
        let reopening = FilesViewModel(defaults: defaults, events: events, access: native, store: store, observer: observer, observesSystem: false)
        await reopening.restore(); precondition(reopening.shelf.count == 1)
        let diskFolder = folder.appendingPathComponent("saved-state", isDirectory: true)
        try FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let diskURL = diskFolder.appendingPathComponent("files.json"), disk = LocalFilesStore(url: diskURL)
        try await disk.save(FilesSnapshot(shelf: model.shelf), revision: 2)
        try await disk.save(FilesSnapshot(), revision: 1)
        let diskState = try await disk.load()
        precondition(diskState.shelf == model.shelf, "Native disk roundtrip keeps the newest revision")
        let directoryMode = (try FileManager.default.attributesOfItem(atPath: diskFolder.path)[.posixPermissions] as! NSNumber).intValue
        let fileMode = (try FileManager.default.attributesOfItem(atPath: diskURL.path)[.posixPermissions] as! NSNumber).intValue
        precondition(directoryMode == 0o700 && fileMode == 0o600)
        let surface = UUID(), shelfID = model.shelf[0].id
        await model.beginSurface(surface)
        let replacement = folder.appendingPathComponent("reconnected.txt")
        try Data("new reference".utf8).write(to: replacement)
        await model.relink(shelfID, to: replacement)
        precondition(model.resolvedURLs[shelfID]?.resolvingSymlinksInPath() == replacement.resolvingSymlinksInPath(), "Dragging after reconnect uses the new file")
        model.endSurface(surface)
        precondition(model.resolvedURLs.isEmpty)
        model.remove(model.shelf[0].id); await model.flush()
        precondition(FileManager.default.fileExists(atPath: moved.pathHint), "Removing a shelf entry preserves the original")
        await model.addFolder(folder); model.startLifecycle()
        for _ in 0..<50 { if await observer.ids() == [model.folders[0].id] { break }; await Task.yield() }
        let activeWatches = await observer.ids(); precondition(activeWatches == [model.folders[0].id])
        model.observationEnabled = false
        for _ in 0..<50 { if await observer.ids().isEmpty { break }; await Task.yield() }
        let stoppedWatches = await observer.ids(); precondition(stoppedWatches.isEmpty)
        let id = model.folders[0].id, time = Date()
        func item(_ name: String, partial: Bool, bytes: Int64 = 10, stamp: Double = 0) -> DownloadFile {
            DownloadFile(folderID: id, name: name, bytes: bytes, modifiedAt: time.addingTimeInterval(stamp), partial: partial, available: true, resourceID: name)
        }
        events.clearCards()
        model.acceptFolderScan(id, files: [item("report.pdf", partial: false), item("report.pdf.crdownload", partial: true)])
        model.acceptFolderScan(id, files: [item("report.pdf", partial: false)])
        precondition(!model.recent.contains(where: \.readyAfterPartial) && events.recent.isEmpty, "Cancelling a partial must not announce the old final file")
        model.acceptFolderScan(id, files: [item("new.pdf.crdownload", partial: true)])
        model.acceptFolderScan(id, files: [item("new.pdf", partial: false, bytes: 40, stamp: 1)])
        precondition(model.recent.first(where: { $0.name == "new.pdf" })?.readyAfterPartial == true)
        let announced = events.recent.count
        model.acceptFolderScan(id, files: [item("new.pdf", partial: false, bytes: 40, stamp: 1)])
        precondition(events.recent.count == announced && events.latest?.owner == .toni)
        model.acceptFolderScan(id, files: [])
        precondition(model.recent.first(where: { $0.name == "new.pdf" })?.available == false)
        await model.shutdownAndFlush()
        let live = LocalFolderObserver(access: native), counter = WatchCounter()
        try await live.start(folderRef) { _, _ in Task { await counter.bump() } }
        try Data("event".utf8).write(to: folder.appendingPathComponent("observed.txt"))
        try await Task.sleep(for: .seconds(1))
        let changedCount = await counter.value(); precondition(changedCount > 0)
        await live.stopAll(); let stoppedCount = await counter.value()
        try Data("after stop".utf8).write(to: folder.appendingPathComponent("after-stop.txt"))
        try await Task.sleep(for: .seconds(1))
        let afterStopCount = await counter.value(); precondition(afterStopCount == stoppedCount, "Disabled watches release observation")
        print("PASS: persisted shelf, original preservation, selected-folder lifecycle, truthful completion, duplicate suppression and event-driven directory teardown")

        let cleaned = try URLTrackingCleanup.review("https://example.com/a%2Fb?utm_source=mail&q=a%2Bb&ref=keep&q=two&fbclid=abc#section")
        precondition(cleaned.cleaned == "https://example.com/a%2Fb?q=a%2Bb&ref=keep&q=two#section")
        let signedURL = try URLTrackingCleanup.review("https://example.com/?X-Amz-Signature=abc&utm_source=keep"); precondition(signedURL.isSigned)
        do { _ = try URLTrackingCleanup.review("javascript:alert(1)"); preconditionFailure("Not a web URL") } catch {}
        let plainBoard = TestPlainBoard(), target = TestPasteTarget(), original = plainBoard.value
        let plain = PlainTextPasteService(board: plainBoard, target: target, pause: { _ in })
        _ = try await plain.paste(to: 2, dismiss: {})
        precondition(plainBoard.value.items == original.items && plainBoard.value.text == original.text)
        target.successful = false
        do { _ = try await plain.paste(to: 2, dismiss: {}); preconditionFailure("Paste failed") } catch {}
        precondition(plainBoard.value.items == original.items)
        target.successful = true; target.onPaste = { plainBoard.userCopies() }
        _ = try await plain.paste(to: 2, dismiss: {})
        precondition(plainBoard.value.text == "new user copy", "Restore cannot clobber a newer copy")
        target.allowed = false; let beforeReads = plainBoard.reads
        do { _ = try await plain.paste(to: 2, dismiss: {}); preconditionFailure("Access denied") } catch {}
        precondition(plainBoard.reads == beforeReads)
        print("PASS: reviewed URL cleanup preserves encoded functional data and signed links; plain paste restores rich clipboard and preserves newer copies")

        let dmg = folder.appendingPathComponent("Fixture.dmg"); try Data("image stays intact".utf8).write(to: dmg)
        let imageRef = try await native.reference(for: dmg), process = FixtureImageProcess(), installer = LocalDiskImageInstaller(access: native, process: process)
        var contents = try await installer.inspect(imageRef)
        var plan = try await installer.review(session: contents.id, app: contents.apps[0].id, destination: destRef, conflict: .cancel)
        let installed = try await installer.install(plan)
        let retainedImageData = try Data(contentsOf: dmg); precondition(FileManager.default.fileExists(atPath: installed.pathHint) && retainedImageData == Data("image stays intact".utf8))
        var state = await process.state(); precondition(state.1 == 1 && state.0.allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) })
        contents = try await installer.inspect(imageRef)
        do { _ = try await installer.review(session: contents.id, app: contents.apps[0].id, destination: destRef, conflict: .cancel); preconditionFailure("Existing app must not be replaced") } catch FileToolError.conflict {}
        plan = try await installer.review(session: contents.id, app: contents.apps[0].id, destination: destRef, conflict: .keepBoth)
        precondition(plan.targetName == "Fixture 2.app")
        try FileManager.default.createDirectory(at: destination.appendingPathComponent(plan.targetName), withIntermediateDirectories: false)
        do { _ = try await installer.install(plan); preconditionFailure("Late destination collision") } catch FileToolError.conflict {}
        await installer.close(); await process.shouldCancel()
        do { _ = try await installer.inspect(imageRef); preconditionFailure("Interrupted mount") } catch is CancellationError {}
        state = await process.state(); precondition(state.1 == 3 && state.0.allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) })
        print("PASS: reviewed disk-image install, conflicts and interrupted-mount cleanup with a mock process; no app or image executed")

        let png = makeImage(), captureBackend = MacCaptureBackend()
        let captured = try await captureBackend.readImage(png)
        let reading = try await captureBackend.recognize(captured)
        precondition(reading.text.localizedCaseInsensitiveContains("HELLO SIEG"), "Real Vision OCR on a generated local image")
        precondition(reading.qrPayloads.contains("https://example.com/offline"), "Real Vision QR on a generated local image")
        let annotation = CaptureAnnotation(kind: .box, points: [CGPoint(x: 0.06, y: 0.1), CGPoint(x: 0.7, y: 0.33)], ink: .coral)
        let annotated = try await captureBackend.annotate(captured, annotations: [annotation])
        let decoded = try await captureBackend.readImage(annotated)
        precondition(decoded.width == captured.width && decoded.height == captured.height && annotated != captured.png)
        do { _ = try await captureBackend.readImage(Data("bad image".utf8)); preconditionFailure("Invalid image") } catch CaptureToolError.invalidImage {}
        let testBackend = TestCaptureBackend(), clipboard = TestClipboard()
        let capture = CaptureViewModel(events: events, backend: testBackend, sampler: TestSampler(), clipboard: clipboard, fileAccess: native)
        try await capture.accept(captured)
        capture.addAnnotation(annotation); capture.undoAnnotation(); precondition(capture.annotations.isEmpty)
        capture.extract(); await capture.waitForAction(); precondition(capture.reading?.text == "offline fixture")
        capture.copyImage(); await capture.waitForAction(); precondition(clipboard.writes.last?.kind == .image)
        capture.copyText("literal $() ação"); await capture.waitForAction(); precondition(clipboard.writes.last?.text == "literal $() ação")
        capture.sampleColor(); await capture.waitForAction(); precondition(capture.sampledColor?.hex == "#FF8000")
        capture.discard(); var before = 0, after = 0
        capture.beforeSelection = { before += 1 }; capture.afterSelection = { after += 1 }
        capture.selectRegion(); for _ in 0..<50 where !capture.isSelecting { await Task.yield() }
        precondition(capture.isSelecting); capture.cancel(); await capture.waitForAction()
        precondition(before == 1 && after == 1 && capture.image == nil && !capture.isBusy && !capture.isSelecting)
        await testBackend.deny(); capture.requestAccess(); await capture.waitForAction()
        capture.selectRegion(); await capture.waitForAction()
        let counts = await testBackend.counters(); precondition(counts.0 == 1 && counts.1 == 1)
        await capture.shutdown()
        print("PASS: native offline OCR/QR, annotation export, invalid input, capture/permission cancellation, mock clipboard and color sampler")

        let runner = NativeToolProcess(), printed = try await runner.run(URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "literal $(nothing) `nothing` ação"])
        precondition(String(data: printed.output, encoding: .utf8) == "literal $(nothing) `nothing` ação")
        let sleeping = Task { try await runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"]) }
        try await Task.sleep(for: .milliseconds(100)); sleeping.cancel()
        do { _ = try await sleeping.value; preconditionFailure("Child process must cancel") } catch is CancellationError {}
        events.post(.reminderAdded, key: "calendar-test", title: "Reminder", detail: "Local")
        precondition(events.latest?.owner == .gantt)
        precondition(!events.post(.reminderAdded, key: "calendar-test", title: "Duplicate", detail: "Local"))
        let persistentEvents = CompanionEventCenter(defaults: defaults, notifier: notifier)
        precondition(!persistentEvents.post(.reminderAdded, key: "calendar-test", title: "Replayed", detail: "Local"))
        let notificationCount = notifier.events.count
        events.post(.downloadReady, key: "disabled-before-delivery", title: "Ready", detail: "Fixture")
        events.setNotifications(false, for: .downloads)
        for _ in 0..<8 { await Task.yield() }
        precondition(notifier.events.count == notificationCount, "Disabling a module cancels queued notifications")
        defaults.set(0, forKey: "calendar.quietStart"); defaults.set(23, forKey: "calendar.quietEnd")
        let quietDate = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let quietEvents = CompanionEventCenter(defaults: defaults, notifier: notifier, now: { quietDate })
        quietEvents.post(.fileReady, key: "quiet-event", title: "Ready", detail: "Fixture")
        precondition(quietEvents.latest?.quiet == true)
        defaults.set(0, forKey: "calendar.quietStart"); defaults.set(0, forKey: "calendar.quietEnd")
        let prefs = CompanionPreferences(defaults: defaults), assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let dragFile = folder.appendingPathComponent("drop.txt"), slowFile = folder.appendingPathComponent("slow-drop.txt")
        try Data("keep original".utf8).write(to: dragFile); try Data("slow original".utf8).write(to: slowFile)
        let dropFiles = FilesViewModel(defaults: defaults, events: events, access: DelayedDropAccess(), store: MemoryFilesStore(), observer: InactiveFolderObserver(), observesSystem: false)
        let receiver = FileReceptionViewModel(files: dropFiles, reader: TestDropReader([dragFile]), pause: { _ in })
        precondition(receiver.owner == .toni, "Toni owns file reception; Sig stays the orchestrator")
        let dragNotch = NotchWidgetViewModel(assistant: assistant, preferences: prefs, calendar: IsolatedCalendarFixture.make(defaults: defaults), events: events, files: dropFiles, fileReception: receiver, managesWindows: false)
        let nativeTarget = FileDropTargetView()
        precondition(nativeTarget.registeredDraggedTypes == [.fileURL] && nativeTarget.hitTest(.zero) == nil)
        precondition(HoverZoneView().registeredDraggedTypes == [.fileURL], "Collapsed camera zone accepts native file drags")
        precondition(dragNotch.enterFileDrag(sequence: 7, point: .zero) && dragNotch.isVisible && dragNotch.presentation == .home)
        dragNotch.collapseAfterPointerExit(); precondition(dragNotch.isVisible, "Dragging pins the expanded receiver")
        receiver.move(sequence: 7, position: CGPoint(x: 2, y: -1)); precondition(receiver.position == CGPoint(x: 1, y: 0))
        receiver.move(sequence: 7, position: CGPoint(x: 0.5, y: 0.08))
        let above = receiver.position
        receiver.move(sequence: 7, position: CGPoint(x: 0.5, y: 0.92))
        precondition(receiver.position.x == above.x && receiver.position.y > above.y, "Vertical drag updates are retained without inventing horizontal movement")
        func near(_ first: CGPoint, _ second: CGPoint) -> Bool { abs(first.x - second.x) < 0.000001 && abs(first.y - second.y) < 0.000001 }
        let measuredReceiver = CGRect(x: -1400, y: -400, width: 532 * 0.85, height: FileReceiverGeometry.stageHeight * 0.85)
        dragNotch.setFileReceiverBounds(measuredReceiver)
        dragNotch.moveFileDrag(sequence: 7, point: CGPoint(x: measuredReceiver.minX + measuredReceiver.width * 0.31, y: measuredReceiver.maxY - measuredReceiver.height * 0.72))
        precondition(near(receiver.position, CGPoint(x: 0.31, y: 0.72)), "Native screen movement uses measured receiver bounds through the widget controller")
        let relativePoints = [CGPoint.zero, CGPoint(x: 1, y: 1), CGPoint(x: 0.31, y: 0.72), CGPoint(x: 0.5, y: 0.5)]
        for scale in [CGFloat(0.85), 1, 1.2] {
            for origin in [CGPoint(x: -1900, y: -400), .zero, CGPoint(x: 1440, y: 200)] {
                let rect = CGRect(origin: origin, size: CGSize(width: 532 * scale, height: FileReceiverGeometry.stageHeight * scale))
                for relative in relativePoints {
                    let global = CGPoint(x: rect.minX + relative.x * rect.width, y: rect.maxY - relative.y * rect.height)
                    precondition(near(FileReceiverGeometry.normalizedPoint(global, in: rect), relative), "Screen points map to receiver-local coordinates at every scale and monitor origin")
                }
                let midpoint = CGPoint(x: rect.midX, y: rect.midY)
                precondition(near(FileReceiverGeometry.normalizedPoint(midpoint, in: rect), CGPoint(x: 0.5, y: 0.5)), "Retina screen points are not multiplied into pixels")
            }
        }
        for size in [CGSize(width: 280, height: FileReceiverGeometry.stageHeight), CGSize(width: 532, height: 240), CGSize(width: 704, height: 320)] {
            let half = FileReceiverGeometry.characterSize / 2
            for point in [CGPoint(x: -1, y: -1), .zero, CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)] {
                let center = FileReceiverGeometry.characterCenter(for: point, in: size, following: true)
                precondition(center.x - half >= 4 && center.x + half <= size.width - 4 && center.y - half >= 10 && center.y + half <= size.height - 10, "The entire character remains inside the outlined receiver")
            }
            let upper = FileReceiverGeometry.characterCenter(for: CGPoint(x: 0.5, y: 0.08), in: size, following: true)
            let lower = FileReceiverGeometry.characterCenter(for: CGPoint(x: 0.5, y: 0.92), in: size, following: true)
            precondition(upper.x == lower.x && upper.y < lower.y, "The rendered character position follows vertical-only movement")
            let still = FileReceiverGeometry.characterCenter(for: .zero, in: size, following: false)
            let alsoStill = FileReceiverGeometry.characterCenter(for: CGPoint(x: 1, y: 1), in: size, following: false)
            precondition(still == alsoStill && still.x == size.width / 2 && still.y == 78, "Reduced Motion preserves the neutral pose regardless of pointer coordinates")
        }
        receiver.exit(sequence: 7)
        receiver.enter(sequence: 7, position: CGPoint(x: 0.2, y: 0.6))
        try await Task.sleep(for: .milliseconds(260)); precondition(receiver.phase == .hovering, "Crossing from the strip to the expanded target keeps one drag alive")
        receiver.exit(sequence: 7)
        try await Task.sleep(for: .milliseconds(260)); precondition(receiver.phase == .idle && !dragNotch.isVisible, "Abandoning drag restores a previously closed island")
        dragNotch.showTimer(); _ = dragNotch.enterFileDrag(sequence: 8, point: .zero)
        receiver.exit(sequence: 8); try await Task.sleep(for: .milliseconds(260))
        precondition(dragNotch.presentation == .timer && dragNotch.isVisible, "Cancel restores the previous page")
        _ = dragNotch.enterFileDrag(sequence: 9, point: .zero)
        let lastHoverPosition = receiver.position
        precondition(receiver.receive(sequence: 9, pasteboard: "fixture", changeCount: 1))
        receiver.move(sequence: 9, position: .zero)
        precondition(receiver.position == lastHoverPosition, "Receipt keeps the last drag position instead of chasing new pointer events")
        await receiver.waitForAction()
        precondition(receiver.phase == .ready && receiver.attached.count == 1 && dropFiles.shelf.count == 1)
        precondition(receiver.position == CGPoint(x: 0.5, y: 0.5), "A completed receipt recenters its context")
        precondition(events.latest?.kind == .fileReceived && events.latest?.owner == receiver.owner, "The receiver and its confirmation use the same specialist")
        precondition(FileManager.default.fileExists(atPath: dragFile.path), "Receiving is a bookmark, not an automatic file open/move/upload")
        let beforeRepeat = events.recent.count
        receiver.receive([dragFile, dragFile]); await receiver.waitForAction()
        precondition(dropFiles.shelf.count == 1 && receiver.attached.count == 1 && events.recent.count == beforeRepeat + 1)
        precondition(!receiver.status.contains("limit"), "Duplicate input is one attachment, not a full-shelf warning")
        dragNotch.showTimer(); _ = dragNotch.enterFileDrag(sequence: 11, point: .zero)
        receiver.exit(sequence: 11); try await Task.sleep(for: .milliseconds(260))
        precondition(dragNotch.presentation == .timer && receiver.attached.count == 1, "Abandoning another drag preserves the previous attachment and page")
        receiver.receive([slowFile]); try await Task.sleep(for: .milliseconds(25))
        receiver.receive([dragFile]); await receiver.waitForAction()
        try await Task.sleep(for: .milliseconds(280))
        precondition(receiver.attached.first?.name == "drop.txt" && !dropFiles.shelf.contains(where: { $0.name == "slow-drop.txt" }), "A late old reader never replaces newer context")
        receiver.receive([slowFile]); try await Task.sleep(for: .milliseconds(25)); receiver.cancel()
        await receiver.waitForAction(); precondition(!dropFiles.shelf.contains(where: { $0.name == "slow-drop.txt" }))
        receiver.receive([URL(string: "https://example.com/file")!]); await receiver.waitForAction()
        precondition(receiver.phase == .failed && dropFiles.shelf.count == 1)
        receiver.clear(); precondition(receiver.phase == .idle && receiver.attached.isEmpty && dropFiles.shelf.count == 1)
        let stillReceiver = FileReceptionViewModel(files: dropFiles, pause: { _ in preconditionFailure("Reduced motion skips animation waiting") }, shouldAnimate: { false })
        stillReceiver.receive([dragFile]); await stillReceiver.waitForAction(); precondition(stillReceiver.phase == .ready)
        _ = dragNotch.enterFileDrag(sequence: 10, point: .zero)
        dragNotch.showCapture(); dragNotch.fileReceiverPageDidChange(); try await Task.sleep(for: .milliseconds(250))
        precondition(dragNotch.presentation == .capture && receiver.phase == .idle, "Cancel cannot restore a stale page over a newer action")
        await dropFiles.shutdownAndFlush()
        print("PASS: native collapsed drop registration, immediate reveal/pinning, two-axis bounded pointer follow, scale/monitor coordinates, reduced-motion positioning, strip handoff, abandon/page recovery, attachments, duplicate files, replacement and cancellation")
        let notch = NotchWidgetViewModel(assistant: assistant, preferences: prefs, calendar: IsolatedCalendarFixture.make(defaults: defaults), events: events, files: reopening, capture: capture, managesWindows: false)
        notch.showFiles(downloads: true); precondition(notch.presentation == .files && notch.files === reopening && notch.files.page == .downloads)
        notch.showCapture(); precondition(notch.presentation == .capture && notch.capture === capture)
        notch.showCalendar(); precondition(notch.calendar.accessState == .notDetermined)
        let shortcutFile = folder.appendingPathComponent("shortcut file.txt")
        try Data("unchanged until confirmation".utf8).write(to: shortcutFile)
        let finder = TestFinder(source: shortcutFile, destination: destination)
        let shortcutFiles = FilesViewModel(defaults: defaults, events: events, store: MemoryFilesStore(), observer: InactiveFolderObserver(), finder: finder, observesSystem: false)
        let shortcutNotch = NotchWidgetViewModel(assistant: assistant, preferences: prefs, calendar: IsolatedCalendarFixture.make(defaults: defaults), events: events, files: shortcutFiles, managesWindows: false)
        var front = "com.apple.TextEdit"
        let shortcuts = ActivationController(assistant: assistant, notch: shortcutNotch, defaults: defaults, registersShortcuts: false, activeBundleID: { front })
        precondition(ShortcutAction.finderActions.allSatisfy { shortcuts.shortcut(for: $0) == nil })
        let f2 = ShortcutChord(keyCode: 120, modifiers: 0, keyLabel: "F2")
        shortcuts.setShortcut(f2, for: .finderRename)
        shortcuts.setShortcut(.companion, for: .finderCut)
        precondition(shortcuts.shortcut(for: .finderCut) == nil, "Finder chords participate in global collision checks")
        shortcuts.setShortcut(.legacyVoice, for: .finderCut)
        precondition(shortcuts.shortcut(for: .finderCut) == nil, "Finder requires an actual key")
        shortcuts.setShortcut(ShortcutChord(keyCode: 7, modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "X"), for: .finderCut)
        shortcuts.setShortcut(ShortcutChord(keyCode: 9, modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "V"), for: .finderPaste)
        let restoredKeys = ActivationController(assistant: assistant, notch: shortcutNotch, defaults: defaults, registersShortcuts: false, activeBundleID: { front })
        precondition(restoredKeys.shortcut(for: .finderRename) == f2)
        shortcuts.performShortcut(.finderRename)
        let outsideReads = await finder.count(); precondition(outsideReads == 0 && !shortcutFiles.isBusy)
        front = "com.apple.finder"
        precondition(shortcuts.shortcutAvailable(.finderRename))
        shortcuts.receiveShortcutEvent(keyCode: 120, flags: [], eventTime: 123)
        let monitorReads = await finder.count(); precondition(monitorReads == 0, "A passive monitor never duplicates Finder's native command")
        shortcuts.receiveHotkey(.finderRename, eventTime: 124)
        for _ in 0..<200 where shortcutFiles.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        precondition(shortcutFiles.renameTarget?.name == "shortcut file.txt" && shortcutNotch.presentation == .files)
        shortcuts.receiveHotkey(.finderCut, eventTime: 125)
        for _ in 0..<200 where shortcutFiles.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        precondition(shortcutFiles.cutFiles.count == 1)
        shortcuts.receiveHotkey(.finderPaste, eventTime: 126)
        for _ in 0..<200 where shortcutFiles.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        precondition(shortcutFiles.pendingReview?.kind == .move && FileManager.default.fileExists(atPath: shortcutFile.path), "Finder shortcut opens review, never executes the move")
        shortcuts.setShortcut(nil, for: .finderRename)
        precondition(ActivationController(assistant: assistant, notch: shortcutNotch, defaults: defaults, registersShortcuts: false).shortcut(for: .finderRename) == nil)
        await shortcutFiles.shutdownAndFlush()
        print("PASS: optional Finder shortcut persistence/conflicts, foreground restriction, no passive-monitor duplication, selected-file rename and reviewed move routing")
        print("PASS: child-process cancellation, persistent task deduplication, specialist ownership and shared app/menu/island feature state")
        print("Sprint 5 files/capture checks passed. No Sieghart, Finder automation, native screen/audio capture, real clipboard or permission prompt used.")
    }
    static func makeImage() -> Data {
        let context = CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "HELLO SIEG", attributes: [.font: CTFontCreateWithName("Helvetica-Bold" as CFString, 38, nil), .foregroundColor: CGColor(gray: 0, alpha: 1)]))
        context.textPosition = CGPoint(x: 45, y: 275); CTLineDraw(line, context)
        let filter = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://example.com/offline".utf8), "inputCorrectionLevel": "M"])!
        let code = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 6, y: 6)), cg = CIContext().createCGImage(code, from: code.extent)!
        context.interpolationQuality = .none; context.draw(cg, in: CGRect(x: 410, y: 30, width: 180, height: 180))
        return MacCaptureBackend.png(context.makeImage()!)!
    }
}
