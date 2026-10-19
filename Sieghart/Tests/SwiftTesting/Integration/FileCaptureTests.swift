import AppKit
import CoreImage
import CoreText
import Foundation
import Testing

extension MacContractsTests {
@Suite(.tags(.filesCapture)) struct FileCaptureContracts {
    @Test("G16.01 — operações identidade, revisão, rename/move, conflitos, stale review e rollback", .tags(.localIntegration))
    @MainActor func reviewedFileOperations() async throws {
        try await IntegrationFileFixture.withFixture { fixture in
        let folder = fixture.folder, native = fixture.native
        let operations = LocalFileOperations(access: native)
        let source = try fixture.directory.file("literal $() ação.txt", contents: "original bytes")
        let destination = folder.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceRef = try await native.reference(for: source), folderRef = try await native.reference(for: folder), destRef = try await native.reference(for: destination)
        let scope = try await native.resolve(sourceRef); #expect(scope.url.resolvingSymlinksInPath() == source.resolvingSymlinksInPath() && scope.details.resourceID == sourceRef.resourceID); scope.close()
        var review = try await operations.review(.rename, sources: [sourceRef], destination: folderRef, rename: "renamed.txt", conflict: .cancel)
        #expect(FileManager.default.fileExists(atPath: source.path), "Review does not execute")
        let renamedResults = try await operations.perform(review)
        let renamed = try #require(renamedResults.first)
        #expect(renamed.id == sourceRef.id && renamed.name == "renamed.txt")
        let renamedData = try Data(contentsOf: URL(fileURLWithPath: renamed.pathHint)); #expect(renamedData == Data("original bytes".utf8))
        for invalid in ["../escape", "a/b", "", ".", "..", "bad\nname"] { #expect(!LocalFileOperations.validName(invalid)) }
        try Data("existing".utf8).write(to: destination.appendingPathComponent("renamed.txt"))
        do { _ = try await operations.review(.move, sources: [renamed], destination: destRef, rename: nil, conflict: .cancel); Issue.record("Collision must stop") }
        catch FileToolError.conflict {}
        review = try await operations.review(.move, sources: [renamed], destination: destRef, rename: nil, conflict: .keepBoth)
        #expect(review.targetNames == ["renamed 2.txt"])
        let movedResults = try await operations.perform(review)
        let moved = try #require(movedResults.first)
        let existingData = try Data(contentsOf: destination.appendingPathComponent("renamed.txt")); #expect(existingData == Data("existing".utf8))
        let movedData = try Data(contentsOf: URL(fileURLWithPath: moved.pathHint)); #expect(movedData == Data("original bytes".utf8))
        review = try await operations.review(.rename, sources: [moved], destination: destRef, rename: "stale.txt", conflict: .cancel)
        try Data("changed after review".utf8).write(to: URL(fileURLWithPath: moved.pathHint))
        do { _ = try await operations.perform(review); Issue.record("Stale review must stop") } catch FileToolError.changed {}
        let a = folder.appendingPathComponent("rollback-a.txt"), b = folder.appendingPathComponent("rollback-b.txt")
        try Data("A".utf8).write(to: a); try Data("B".utf8).write(to: b)
        let rollback = RollbackAccess(), rops = LocalFileOperations(access: rollback)
        let refs = [try await rollback.reference(for: a), try await rollback.reference(for: b)]
        review = try await rops.review(.move, sources: refs, destination: destRef, rename: nil, conflict: .cancel)
        await rollback.arm()
        do { _ = try await rops.perform(review); Issue.record("Missing second file must stop the batch") } catch {}
        #expect(FileManager.default.fileExists(atPath: a.path) && !FileManager.default.fileExists(atPath: destination.appendingPathComponent(a.lastPathComponent).path), "First move is rolled back")
        do { _ = try await operations.review(.move, sources: [folderRef], destination: destRef, rename: nil, conflict: .cancel); Issue.record("Cannot move a parent into its child") }
        catch FileToolError.invalidDestination {}
        }
    }
    @Test("G16.02 — shelf memória/disco, revisão monotônica, permissões, relink e remoção preservam original", .tags(.localIntegration))
    @MainActor func shelfPersistenceAndRelinking() async throws {
        try await IntegrationFileFixture.withFixture { fixture in
        let folder = fixture.folder, defaults = fixture.defaults, native = fixture.native, events = fixture.events
        let movedURL = try fixture.directory.file("kept.txt", contents: "original bytes")
        let moved = try await native.reference(for: movedURL)
        events.setNotifications(true, for: .downloads)
        let observer = RecordingObserver(), store = MemoryFilesStore(), model = FilesViewModel(defaults: defaults, events: events, access: native, store: store, observer: observer, observesSystem: false)
        fixture.own(model)
        await model.add([URL(fileURLWithPath: moved.pathHint)])
        await model.flush()
        let reopening = FilesViewModel(defaults: defaults, events: events, access: native, store: store, observer: observer, observesSystem: false)
        fixture.own(reopening)
        await reopening.restore(); #expect(reopening.shelf.count == 1)
        let diskFolder = folder.appendingPathComponent("saved-state", isDirectory: true)
        try FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let diskURL = diskFolder.appendingPathComponent("files.json"), disk = LocalFilesStore(url: diskURL)
        try await disk.save(FilesSnapshot(shelf: model.shelf), revision: 2)
        try await disk.save(FilesSnapshot(), revision: 1)
        let diskState = try await disk.load()
        #expect(diskState.shelf == model.shelf, "Native disk roundtrip keeps the newest revision")
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: diskFolder.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: diskURL.path)
        let directoryMode = try #require(directoryAttributes[.posixPermissions] as? NSNumber).intValue
        let fileMode = try #require(fileAttributes[.posixPermissions] as? NSNumber).intValue
        #expect(directoryMode == 0o700 && fileMode == 0o600)
        let surface = UUID(), shelfID = try #require(model.shelf.first?.id)
        await model.beginSurface(surface)
        let replacement = folder.appendingPathComponent("reconnected.txt")
        try Data("new reference".utf8).write(to: replacement)
        await model.relink(shelfID, to: replacement)
        #expect(model.resolvedURLs[shelfID]?.resolvingSymlinksInPath() == replacement.resolvingSymlinksInPath(), "Dragging after reconnect uses the new file")
        model.endSurface(surface)
        #expect(model.resolvedURLs.isEmpty)
        model.remove(shelfID); await model.flush()
        #expect(FileManager.default.fileExists(atPath: moved.pathHint), "Removing a shelf entry preserves the original")
        await model.shutdownAndFlush(); await reopening.shutdownAndFlush()
        }
    }
    @Test("G16.03 — downloads lifecycle, partial cancelado, conclusão real, dedup e indisponibilidade", .tags(.localIntegration))
    @MainActor func downloadObservationAndCompletion() async throws {
        try await IntegrationFileFixture.withFixture { fixture in
        let folder = fixture.folder, events = fixture.events
        events.setNotifications(true, for: .downloads)
        let observer = RecordingObserver(), model = fixture.model(observer: observer)
        await model.addFolder(folder); model.startLifecycle()
        let id = try #require(model.folders.first?.id)
        try await IntegrationWait.untilAsync { await observer.ids() == [id] }
        let activeWatches = await observer.ids(); #expect(activeWatches == [id])
        model.observationEnabled = false
        try await IntegrationWait.untilAsync { await observer.ids().isEmpty }
        let stoppedWatches = await observer.ids(); #expect(stoppedWatches.isEmpty)
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        func item(_ name: String, partial: Bool, bytes: Int64 = 10, stamp: Double = 0) -> DownloadFile {
            DownloadFile(folderID: id, name: name, bytes: bytes, modifiedAt: time.addingTimeInterval(stamp), partial: partial, available: true, resourceID: name)
        }
        events.clearCards()
        model.acceptFolderScan(id, files: [item("report.pdf", partial: false), item("report.pdf.crdownload", partial: true)])
        model.acceptFolderScan(id, files: [item("report.pdf", partial: false)])
        #expect(!model.recent.contains(where: \.readyAfterPartial) && events.recent.isEmpty, "Cancelling a partial must not announce the old final file")
        model.acceptFolderScan(id, files: [item("new.pdf.crdownload", partial: true)])
        model.acceptFolderScan(id, files: [item("new.pdf", partial: false, bytes: 40, stamp: 1)])
        #expect(model.recent.first(where: { $0.name == "new.pdf" })?.readyAfterPartial == true)
        let announced = events.recent.count
        model.acceptFolderScan(id, files: [item("new.pdf", partial: false, bytes: 40, stamp: 1)])
        #expect(events.recent.count == announced && events.latest?.owner == .toni)
        model.acceptFolderScan(id, files: [])
        #expect(model.recent.first(where: { $0.name == "new.pdf" })?.available == false)
        await model.shutdownAndFlush()
        }
    }
    @Test("G16.04 — watcher pasta exclusiva e stopAll impedem eventos posteriores", .tags(.localIntegration))
    @MainActor func nativeWatcherTeardown() async throws {
        try await IntegrationFileFixture.withFixture { fixture in
        let folder = fixture.folder, native = fixture.native
        let folderRef = try await native.reference(for: folder)
        let live = LocalFolderObserver(access: native), counter = WatchCounter()
        do {
        try await live.start(folderRef) { _, _ in Task { await counter.bump() } }
        try Data("event".utf8).write(to: folder.appendingPathComponent("observed.txt"))
        try await IntegrationWait.untilAsync { await counter.value() > 0 }
        let changedCount = await counter.value(); #expect(changedCount > 0)
        await live.stopAll(); let stoppedCount = await counter.value()
        try Data("after stop".utf8).write(to: folder.appendingPathComponent("after-stop.txt"))
        try await Task.sleep(for: .seconds(1))
        let afterStopCount = await counter.value(); #expect(afterStopCount == stoppedCount, "Disabled watches release observation")
        } catch {
            await live.stopAll()
            throw error
        }
        await live.stopAll()
        }
    }
    @Test("G16.06 — plainPaste restaura rich clipboard, preserva cópia nova e checa acesso antes da leitura", .tags(.isolated))
    @MainActor func plainPastePreservesClipboard() async throws {
        let plainBoard = TestPlainBoard(), target = TestPasteTarget(), original = plainBoard.value
        let plain = PlainTextPasteService(board: plainBoard, target: target, pause: { _ in })
        _ = try await plain.paste(to: 2, dismiss: {})
        #expect(plainBoard.value.items == original.items && plainBoard.value.text == original.text)
        target.successful = false
        do { _ = try await plain.paste(to: 2, dismiss: {}); Issue.record("Paste failed") } catch {}
        #expect(plainBoard.value.items == original.items)
        target.successful = true; target.onPaste = { plainBoard.userCopies() }
        _ = try await plain.paste(to: 2, dismiss: {})
        #expect(plainBoard.value.text == "new user copy", "Restore cannot clobber a newer copy")
        target.allowed = false; let beforeReads = plainBoard.reads
        do { _ = try await plain.paste(to: 2, dismiss: {}); Issue.record("Access denied") } catch {}
        #expect(plainBoard.reads == beforeReads)
    }
    @Test("G16.07 — diskImage review, conflito, revalidação e cancelamento limpam mount simulado", .tags(.localIntegration))
    @MainActor func reviewedDiskImageInstall() async throws {
        try await IntegrationFileFixture.withFixture { fixture in
        let folder = fixture.folder, native = fixture.native
        let destination = folder.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let destRef = try await native.reference(for: destination)
        let dmg = folder.appendingPathComponent("Fixture.dmg"); try Data("image stays intact".utf8).write(to: dmg)
        let imageRef = try await native.reference(for: dmg), process = FixtureImageProcess(), installer = LocalDiskImageInstaller(access: native, process: process)
        fixture.onCleanup { await installer.close() }
        var contents = try await installer.inspect(imageRef)
        var plan = try await installer.review(session: contents.id, app: try #require(contents.apps.first?.id), destination: destRef, conflict: .cancel)
        let installed = try await installer.install(plan)
        let retainedImageData = try Data(contentsOf: dmg); #expect(FileManager.default.fileExists(atPath: installed.pathHint) && retainedImageData == Data("image stays intact".utf8))
        var state = await process.state(); #expect(state.1 == 1 && state.0.allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) })
        contents = try await installer.inspect(imageRef)
        do { _ = try await installer.review(session: contents.id, app: try #require(contents.apps.first?.id), destination: destRef, conflict: .cancel); Issue.record("Existing app must not be replaced") } catch FileToolError.conflict {}
        plan = try await installer.review(session: contents.id, app: try #require(contents.apps.first?.id), destination: destRef, conflict: .keepBoth)
        #expect(plan.targetName == "Fixture 2.app")
        try FileManager.default.createDirectory(at: destination.appendingPathComponent(plan.targetName), withIntermediateDirectories: false)
        do { _ = try await installer.install(plan); Issue.record("Late destination collision") } catch FileToolError.conflict {}
        await installer.close(); await process.shouldCancel()
        do { _ = try await installer.inspect(imageRef); Issue.record("Interrupted mount") } catch is CancellationError {}
        state = await process.state(); #expect(state.1 == 3 && state.0.allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) })
        }
    }
    @Test("G16.08 — offlineCapture OCR e QR reais, anotação preserva dimensões e rejeita bytes inválidos", .tags(.localIntegration))
    @MainActor func offlineOCRAndQR() async throws {
        let png = try IntegrationCaptureImage.make(), captureBackend = MacCaptureBackend()
        let captured = try await captureBackend.readImage(png)
        let reading = try await captureBackend.recognize(captured)
        #expect(reading.text.localizedCaseInsensitiveContains("HELLO SIEG"), "Real Vision OCR on a generated local image")
        #expect(reading.qrPayloads.contains("https://example.com/offline"), "Real Vision QR on a generated local image")
        let annotation = CaptureAnnotation(kind: .box, points: [CGPoint(x: 0.06, y: 0.1), CGPoint(x: 0.7, y: 0.33)], ink: .coral)
        let annotated = try await captureBackend.annotate(captured, annotations: [annotation])
        let decoded = try await captureBackend.readImage(annotated)
        #expect(decoded.width == captured.width && decoded.height == captured.height && annotated != captured.png)
        do { _ = try await captureBackend.readImage(Data("bad image".utf8)); Issue.record("Invalid image") } catch CaptureToolError.invalidImage {}
    }
    @Test("G16.09 — captureState undo, OCR fake, copy, cor e cancelamento com acesso negado", .tags(.isolated))
    @MainActor func captureActionsAndCancellation() async throws {
        let isolated = try TestDefaults(); defer { isolated.cleanup() }
        let defaults = isolated.value, native = LocalFileAccess(), notifier = TestTaskNotifier()
        defaults.set(0, forKey: "calendar.quietStart"); defaults.set(0, forKey: "calendar.quietEnd")
        let events = CompanionEventCenter(defaults: defaults, notifier: notifier)
        let captured = CapturedImage(png: try IntegrationCaptureImage.make(), width: 640, height: 360)
        let annotation = CaptureAnnotation(kind: .box, points: [CGPoint(x: 0.06, y: 0.1), CGPoint(x: 0.7, y: 0.33)], ink: .coral)
        let testBackend = TestCaptureBackend(), clipboard = TestClipboard()
        let capture = CaptureViewModel(events: events, backend: testBackend, sampler: TestSampler(), clipboard: clipboard, fileAccess: native)
        do {
        try await capture.accept(captured)
        capture.addAnnotation(annotation); capture.undoAnnotation(); #expect(capture.annotations.isEmpty)
        capture.extract(); await capture.waitForAction(); #expect(capture.reading?.text == "offline fixture")
        capture.copyImage(); await capture.waitForAction(); #expect(clipboard.writes.last?.kind == .image)
        capture.copyText("literal $() ação"); await capture.waitForAction(); #expect(clipboard.writes.last?.text == "literal $() ação")
        capture.sampleColor(); await capture.waitForAction(); #expect(capture.sampledColor?.hex == "#FF8000")
        capture.discard(); var before = 0, after = 0
        capture.beforeSelection = { before += 1 }; capture.afterSelection = { after += 1 }
        capture.selectRegion(); try await IntegrationWait.until { capture.isSelecting }
        #expect(capture.isSelecting); capture.cancel(); await capture.waitForAction()
        #expect(before == 1 && after == 1 && capture.image == nil && !capture.isBusy && !capture.isSelecting)
        await testBackend.deny(); capture.requestAccess(); await capture.waitForAction()
        capture.selectRegion(); await capture.waitForAction()
        let counts = await testBackend.counters(); #expect(counts.0 == 1 && counts.1 == 1)
        } catch { await capture.shutdown(); throw error }
        await capture.shutdown()
    }
    @Test("G16.10 — events dedup persistido, dono Gantt, opt-out antes de entrega e quiet hours", .tags(.isolated))
    @MainActor func companionEventDelivery() async throws {
        let isolated = try TestDefaults(); defer { isolated.cleanup() }
        let defaults = isolated.value, notifier = TestTaskNotifier()
        defaults.set(0, forKey: "calendar.quietStart"); defaults.set(0, forKey: "calendar.quietEnd")
        let events = CompanionEventCenter(defaults: defaults, notifier: notifier)
        do {
        events.post(.reminderAdded, key: "calendar-test", title: "Reminder", detail: "Local")
        #expect(events.latest?.owner == .gantt)
        #expect(!events.post(.reminderAdded, key: "calendar-test", title: "Duplicate", detail: "Local"))
        let persistentEvents = CompanionEventCenter(defaults: defaults, notifier: notifier)
        #expect(!persistentEvents.post(.reminderAdded, key: "calendar-test", title: "Replayed", detail: "Local"))
        let notificationCount = notifier.events.count
        events.setNotifications(true, for: .downloads)
        #expect(events.notificationsEnabled(.downloads))
        events.post(.downloadReady, key: "disabled-before-delivery", title: "Ready", detail: "Fixture")
        try #require(events.pendingNotificationCount == 1)
        // No suspension occurs between enqueue and opt-out on the main actor.
        events.setNotifications(false, for: .downloads)
        await events.waitForNotificationDelivery()
        #expect(events.pendingNotificationCount == 0)
        #expect(notifier.events.count == notificationCount, "Disabling a module cancels queued notifications")
        defaults.set(0, forKey: "calendar.quietStart"); defaults.set(23, forKey: "calendar.quietEnd")
        let quietDate = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_700_000_000)))
        let quietEvents = CompanionEventCenter(defaults: defaults, notifier: notifier, now: { quietDate })
        quietEvents.post(.fileReady, key: "quiet-event", title: "Ready", detail: "Fixture")
        #expect(quietEvents.latest?.quiet == true)
        } catch { await events.waitForNotificationDelivery(); throw error }
        await events.waitForNotificationDelivery()
    }
    @Test("G16.13 — finderShortcuts persistência, colisões, foreground, monitor sem duplicação e review sem mover", .tags(.localIntegration))
    @MainActor func finderRoutingAndReview() async throws {
        try await IntegrationFileFixture.withFixture { fixture in
        let folder = fixture.folder, defaults = fixture.defaults, native = fixture.native, events = fixture.events
        let reopening = fixture.model()
        let capture = CaptureViewModel(events: events, backend: TestCaptureBackend(), sampler: TestSampler(), clipboard: TestClipboard(), fileAccess: native)
        fixture.onCleanup { await capture.shutdown() }
        let surface = try PresentationFixture(defaultsFixture: fixture.isolated, events: events, files: reopening, capture: capture, createActivation: false)
        let assistant = surface.assistant, notch = surface.notch
        defer { surface.cleanup() }
        notch.showFiles(downloads: true); #expect(notch.presentation == .files && notch.files === reopening && notch.files.page == .downloads)
        notch.showCapture(); #expect(notch.presentation == .capture && notch.capture === capture)
        notch.showCalendar(); #expect(notch.calendar.accessState == .notDetermined)
        let shortcutFile = folder.appendingPathComponent("shortcut file.txt")
        try Data("unchanged until confirmation".utf8).write(to: shortcutFile)
        let destination = folder.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let finder = TestFinder(source: shortcutFile, destination: destination)
        let shortcutFiles = FilesViewModel(defaults: defaults, events: events, store: MemoryFilesStore(), observer: InactiveFolderObserver(), finder: finder, observesSystem: false)
        fixture.own(shortcutFiles)
        let shortcutSurface = try PresentationFixture(defaultsFixture: fixture.isolated, events: events, files: shortcutFiles, createActivation: false)
        let shortcutNotch = shortcutSurface.notch
        defer { shortcutSurface.cleanup() }
        var front = "com.apple.TextEdit"
        let shortcuts = ActivationController(assistant: assistant, notch: shortcutNotch, defaults: defaults, registersShortcuts: false, lifecycleNotifications: nil, activeBundleID: { front })
        defer { shortcuts.shutdown() }
        #expect(ShortcutAction.finderActions.allSatisfy { shortcuts.shortcut(for: $0) == nil })
        let f2 = ShortcutChord(keyCode: 120, modifiers: 0, keyLabel: "F2")
        shortcuts.setShortcut(f2, for: .finderRename)
        shortcuts.setShortcut(.companion, for: .finderCut)
        #expect(shortcuts.shortcut(for: .finderCut) == nil, "Finder chords participate in global collision checks")
        shortcuts.setShortcut(.legacyVoice, for: .finderCut)
        #expect(shortcuts.shortcut(for: .finderCut) == nil, "Finder requires an actual key")
        shortcuts.setShortcut(ShortcutChord(keyCode: 7, modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "X"), for: .finderCut)
        shortcuts.setShortcut(ShortcutChord(keyCode: 9, modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "V"), for: .finderPaste)
        let restoredKeys = ActivationController(assistant: assistant, notch: shortcutNotch, defaults: defaults, registersShortcuts: false, lifecycleNotifications: nil, activeBundleID: { front })
        defer { restoredKeys.shutdown() }
        #expect(restoredKeys.shortcut(for: .finderRename) == f2)
        shortcuts.performShortcut(.finderRename)
        let outsideReads = await finder.count(); #expect(outsideReads == 0 && !shortcutFiles.isBusy)
        front = "com.apple.finder"
        #expect(shortcuts.shortcutAvailable(.finderRename))
        shortcuts.receiveShortcutEvent(keyCode: 120, flags: [], eventTime: 123)
        let monitorReads = await finder.count(); #expect(monitorReads == 0, "A passive monitor never duplicates Finder's native command")
        shortcuts.receiveHotkey(.finderRename, eventTime: 124)
        try await IntegrationWait.until { !shortcutFiles.isBusy }
        #expect(shortcutFiles.renameTarget?.name == "shortcut file.txt" && shortcutNotch.presentation == .files)
        shortcuts.receiveHotkey(.finderCut, eventTime: 125)
        try await IntegrationWait.until { !shortcutFiles.isBusy }
        #expect(shortcutFiles.cutFiles.count == 1)
        shortcuts.receiveHotkey(.finderPaste, eventTime: 126)
        try await IntegrationWait.until { !shortcutFiles.isBusy }
        #expect(shortcutFiles.pendingReview?.kind == .move && FileManager.default.fileExists(atPath: shortcutFile.path), "Finder shortcut opens review, never executes the move")
        shortcuts.setShortcut(nil, for: .finderRename)
        let clearedKeys = ActivationController(assistant: assistant, notch: shortcutNotch, defaults: defaults, registersShortcuts: false, lifecycleNotifications: nil)
        defer { clearedKeys.shutdown() }
        #expect(clearedKeys.shortcut(for: .finderRename) == nil)
        await shortcutFiles.shutdownAndFlush(); await reopening.shutdownAndFlush(); await capture.shutdown(); notch.stopUtilities(); shortcutNotch.stopUtilities()
        }
    }
}
}
