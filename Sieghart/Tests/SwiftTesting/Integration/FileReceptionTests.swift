import AppKit
import Foundation
import Testing

extension MacContractsTests {
    @Suite(.tags(.filesCapture)) @MainActor struct FileReceptionTests {
        @Test("G16.11 — Toni recebe, revela/fixa ilha, segue dois eixos e mede bounds", .tags(.localIntegration))
        func dragAndPosition() async throws {
            try await IntegrationFileFixture.withFixture { fixture in
            let files = fixture.model(), receiver = FileReceptionViewModel(files: files, pause: { _ in })
            let surface = try PresentationFixture(defaultsFixture: fixture.isolated, events: fixture.events, files: files, fileReception: receiver, createActivation: false)
            let notch = surface.notch
            defer { surface.cleanup() }
            fixture.onCleanup { receiver.cancel(); await receiver.waitForAction() }
            #expect(receiver.owner == .toni)
            #expect(notch.enterFileDrag(sequence: 7, point: .zero) && notch.isVisible && notch.presentation == .home)
            notch.collapseAfterPointerExit(); #expect(notch.isVisible)
            receiver.move(sequence: 7, position: CGPoint(x: 2, y: -1)); #expect(receiver.position == CGPoint(x: 1, y: 0))
            receiver.move(sequence: 7, position: CGPoint(x: 0.5, y: 0.08)); let above = receiver.position
            receiver.move(sequence: 7, position: CGPoint(x: 0.5, y: 0.92))
            #expect(receiver.position.x == above.x && receiver.position.y > above.y)
            let rect = CGRect(x: -1400, y: -400, width: 532 * 0.85, height: FileReceiverGeometry.stageHeight * 0.85)
            notch.setFileReceiverBounds(rect)
            notch.moveFileDrag(sequence: 7, point: CGPoint(x: rect.minX + rect.width * 0.31, y: rect.maxY - rect.height * 0.72))
            #expect(abs(receiver.position.x - 0.31) < 0.000001 && abs(receiver.position.y - 0.72) < 0.000001)
            await files.shutdownAndFlush()
            }
        }
        @Test("G16.11 — views nativas registram somente arquivos locais e não capturam hitTest", .tags(.nativeView))
        func nativeDropRegistration() {
            let view = FileDropTargetView()
            #expect(view.registeredDraggedTypes == [.fileURL] && view.hitTest(.zero) == nil)
            #expect(HoverZoneView().registeredDraggedTypes == [.fileURL])
        }
        @Test("G16.12 — handoff conserva drag e abandono restaura fechamento/página", .tags(.localIntegration))
        func handoffAndAbandonment() async throws {
            try await IntegrationFileFixture.withFixture { fixture in
            let files = fixture.model(), receiver = FileReceptionViewModel(files: files, pause: { _ in })
            let surface = try PresentationFixture(defaultsFixture: fixture.isolated, events: fixture.events, files: files, fileReception: receiver, createActivation: false)
            let notch = surface.notch
            defer { surface.cleanup() }
            fixture.onCleanup { receiver.cancel(); await receiver.waitForAction() }
            _ = notch.enterFileDrag(sequence: 7, point: .zero)
            receiver.exit(sequence: 7); receiver.enter(sequence: 7, position: CGPoint(x: 0.2, y: 0.6))
            // The 220 ms grace period is the contract under test, so this one
            // temporal assertion intentionally crosses it on the native clock.
            try await Task.sleep(for: .milliseconds(260))
            #expect(receiver.phase == .hovering)
            receiver.exit(sequence: 7); try await IntegrationWait.until { receiver.phase == .idle }
            #expect(!notch.isVisible)
            notch.showTimer(); _ = notch.enterFileDrag(sequence: 8, point: .zero)
            receiver.exit(sequence: 8); try await IntegrationWait.until { receiver.phase == .idle }
            #expect(notch.presentation == .timer && notch.isVisible)
            _ = notch.enterFileDrag(sequence: 10, point: .zero)
            notch.showCapture(); notch.fileReceiverPageDidChange()
            try await IntegrationWait.until { receiver.phase == .idle }
            #expect(notch.presentation == .capture)
            await files.shutdownAndFlush()
            }
        }
        @Test("G16.12 — recebimento, recenter, dedup, original, abandono e Reduce Motion", .tags(.localIntegration))
        func receivedFiles() async throws {
            try await IntegrationFileFixture.withFixture { fixture in
            let url = try fixture.directory.file("drop.txt", contents: "keep original"), files = fixture.model()
            let receiver = FileReceptionViewModel(files: files, reader: TestDropReader([url]), pause: { _ in })
            fixture.onCleanup { receiver.cancel(); await receiver.waitForAction() }
            receiver.enter(sequence: 9, position: CGPoint(x: 0.3, y: 0.7)); let last = receiver.position
            #expect(receiver.receive(sequence: 9, pasteboard: "fixture", changeCount: 1))
            receiver.move(sequence: 9, position: .zero); #expect(receiver.position == last)
            await receiver.waitForAction()
            #expect(receiver.phase == .ready && receiver.attached.count == 1 && files.shelf.count == 1)
            #expect(receiver.position == CGPoint(x: 0.5, y: 0.5))
            #expect(fixture.events.latest?.kind == .fileReceived && fixture.events.latest?.owner == receiver.owner)
            #expect(FileManager.default.fileExists(atPath: url.path))
            let before = fixture.events.recent.count
            receiver.receive([url, url]); await receiver.waitForAction()
            #expect(files.shelf.count == 1 && receiver.attached.count == 1 && fixture.events.recent.count == before + 1)
            #expect(!receiver.status.contains("limit"))
            receiver.enter(sequence: 11, position: .zero); receiver.exit(sequence: 11)
            try await IntegrationWait.until { receiver.phase == .ready }
            #expect(receiver.attached.count == 1)
            let still = FileReceptionViewModel(files: files, pause: { _ in Issue.record("Reduce Motion must not await an animation") }, shouldAnimate: { false })
            fixture.onCleanup { still.cancel(); await still.waitForAction() }
            still.receive([url]); await still.waitForAction(); #expect(still.phase == .ready)
            await files.shutdownAndFlush()
            }
        }
        @Test("G16.12 — leitor tardio e cancelado não substituem contexto; remoto falha e clear mantém shelf", .tags(.localIntegration))
        func lateAndCancelledReaders() async throws {
            try await IntegrationFileFixture.withFixture { fixture in
            let slow = try fixture.directory.file("slow-drop.txt"), fast = try fixture.directory.file("drop.txt"), access = DelayedDropAccess()
            let files = FilesViewModel(defaults: fixture.defaults, events: fixture.events, access: access, store: MemoryFilesStore(), observer: InactiveFolderObserver(), observesSystem: false)
            let receiver = FileReceptionViewModel(files: files, pause: { _ in })
            fixture.own(files)
            fixture.onCleanup {
                receiver.cancel(); await access.release(); await receiver.waitForAction()
                try? await IntegrationWait.untilAsync { await access.finished == access.entered }
            }
            receiver.receive([slow]); try await IntegrationWait.untilAsync { await access.entered == 1 }
            receiver.receive([fast]); await receiver.waitForAction(); await access.release()
            try await IntegrationWait.untilAsync { await access.finished == 1 }
            #expect(receiver.attached.first?.name == "drop.txt" && !files.shelf.contains { $0.name == "slow-drop.txt" })
            await access.hold()
            receiver.receive([slow]); try await IntegrationWait.untilAsync { await access.entered == 2 }
            receiver.cancel(); await access.release(); await receiver.waitForAction()
            #expect(!files.shelf.contains { $0.name == "slow-drop.txt" })
            receiver.receive([try #require(URL(string: "https://example.com/file"))]); await receiver.waitForAction()
            #expect(receiver.phase == .failed && files.shelf.count == 1)
            receiver.clear(); #expect(receiver.phase == .idle && receiver.attached.isEmpty && files.shelf.count == 1)
            await files.shutdownAndFlush()
            }
        }
        @Test("G16.10 — argumentos literais sem shell e cancelamento após filho iniciar", .tags(.localIntegration))
        func processArgumentsAndCancellation() async throws {
            let runner = NativeToolProcess()
            let result = try await runner.run(URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "literal $(nothing) `nothing` ação"])
            #expect(String(data: result.output, encoding: .utf8) == "literal $(nothing) `nothing` ação")
            let directory = try IntegrationDirectory("tool-process"); defer { directory.cleanup() }
            let script = try directory.python("import pathlib,time\npathlib.Path(__file__).with_suffix('.started').touch()\ntime.sleep(10)\n")
            let task = Task { try await runner.run(script, arguments: []) }
            defer { task.cancel() }
            try await IntegrationWait.until { FileManager.default.fileExists(atPath: script.deletingPathExtension().appendingPathExtension("started").path) }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }
}
