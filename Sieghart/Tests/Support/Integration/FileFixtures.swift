import AppKit
import CoreImage
import CoreText
import Foundation
import Testing

actor RecordingObserver: FolderObserving {
    var watched: Set<UUID> = []
    var stopped = 0
    func start(_ folder: FileReference, changed: @escaping @Sendable (UUID, Bool) -> Void) { watched.insert(folder.id) }
    func stop(_ id: UUID) { watched.remove(id) }
    func stopAll() { watched = []; stopped += 1 }
    func ids() -> Set<UUID> { watched }
}
actor WatchCounter { var count = 0; func bump() { count += 1 }; func value() -> Int { count } }
actor TestDropReader: FileDropReading {
    let urls: [URL]
    init(_ urls: [URL]) { self.urls = urls }
    func read(pasteboard: String, changeCount: Int) -> [URL] { urls }
}
actor DelayedDropAccess: FileAccessing {
    let native = LocalFileAccess()
    var waiting: [CheckedContinuation<Void, Never>] = []
    var entered = 0
    var finished = 0
    private var held = true
    func hold() { held = true }
    func release() { held = false; let pending = waiting; waiting = []; pending.forEach { $0.resume() } }
    func reference(for url: URL) async throws -> FileReference {
        if url.lastPathComponent == "slow-drop.txt" {
            entered += 1
            if held { await withCheckedContinuation { waiting.append($0) } }
            defer { finished += 1 }
            return try await native.reference(for: url)
        }
        return try await native.reference(for: url)
    }
    func resolve(_ reference: FileReference) async throws -> ScopedFile { try await native.resolve(reference) }
    func list(_ folder: FileReference) async throws -> [DownloadFile] { try await native.list(folder) }
}
actor TestFinder: FinderSelecting {
    let source: URL, destination: URL
    var reads = 0
    init(source: URL, destination: URL) { self.source = source; self.destination = destination }
    func selection() -> [URL] { reads += 1; return [source] }
    func insertionFolder() -> URL { reads += 1; return destination }
    func count() -> Int { reads }
}
actor RollbackAccess: FileAccessing {
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
actor FixtureImageProcess: ToolProcessRunning {
    var mounts: [URL] = []
    var detachCount = 0
    var cancelAttach = false
    func shouldCancel() { cancelAttach = true }
    func state() -> ([URL], Int) { (mounts, detachCount) }
    func run(_ executable: URL, arguments: [String]) throws -> ToolProcessResult {
        guard executable.lastPathComponent == "hdiutil" else { throw FileToolError.unsupported }
        if arguments.first == "attach" {
            let index = try #require(arguments.firstIndex(of: "-mountpoint")), mount = URL(fileURLWithPath: arguments[index + 1])
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
@MainActor final class TestTaskNotifier: CompanionTaskNotifying {
    var events: [CompanionTaskEvent] = []
    func post(_ event: CompanionTaskEvent) async { events.append(event) }
    func requestAccess() async -> Bool { true }
}
@MainActor final class TestPlainBoard: PlainClipboardAccess {
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
@MainActor final class TestPasteTarget: PlainPasteTargeting {
    var allowed = true, successful = true
    var onPaste: (() -> Void)?
    func canPaste(to pid: Int32) -> Bool { allowed }
    func activate(_ pid: Int32) -> Bool { allowed }
    func paste(to pid: Int32) -> Bool { onPaste?(); return successful }
}
@MainActor final class TestClipboard: ClipboardAccess {
    var writes: [ClipboardPayload] = []
    func read(after changeCount: Int?, includeMedia: Bool) async -> ClipboardRead? { nil }
    func write(_ payload: ClipboardPayload) async -> Int? { writes.append(payload); return writes.count }
}
actor TestCaptureBackend: CaptureProviding {
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
@MainActor final class TestSampler: ColorSampling {
    func sample() async -> SampledColor? { SampledColor(red: 1, green: 0.5, blue: 0) }
}


@MainActor final class IntegrationFileFixture {
    let directory: IntegrationDirectory
    let isolated: TestDefaults
    var folder: URL { directory.url }
    var defaults: UserDefaults { isolated.value }
    let native = LocalFileAccess()
    let notifier = TestTaskNotifier()
    let events: CompanionEventCenter
    private var ownedModels: [FilesViewModel] = []
    private var teardown: [@MainActor () async -> Void] = []
    init() throws {
        directory = try IntegrationDirectory("files")
        isolated = try TestDefaults()
        isolated.value.set(0, forKey: "calendar.quietStart")
        isolated.value.set(0, forKey: "calendar.quietEnd")
        events = CompanionEventCenter(defaults: isolated.value, notifier: notifier)
    }
    func cleanup() { isolated.cleanup(); directory.cleanup() }
    static func withFixture(_ operation: (IntegrationFileFixture) async throws -> Void) async throws {
        let fixture = try IntegrationFileFixture()
        do { try await operation(fixture) }
        catch { await fixture.shutdown(); fixture.cleanup(); throw error }
        await fixture.shutdown(); fixture.cleanup()
    }
    func onCleanup(_ operation: @escaping @MainActor () async -> Void) { teardown.append(operation) }
    func own(_ model: FilesViewModel) { ownedModels.append(model) }
    private func shutdown() async {
        for operation in teardown.reversed() { await operation() }
        for model in ownedModels.reversed() { await model.shutdownAndFlush() }
        await events.waitForNotificationDelivery()
        teardown = []; ownedModels = []
    }
    func model(store: any FilesStoring = MemoryFilesStore(), observer: any FolderObserving = InactiveFolderObserver()) -> FilesViewModel {
        let model = FilesViewModel(defaults: defaults, events: events, access: native, store: store, observer: observer, observesSystem: false)
        own(model)
        return model
    }
}

enum IntegrationCaptureImage {
    static func make() throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "HELLO SIEG", attributes: [.font: CTFontCreateWithName("Helvetica-Bold" as CFString, 38, nil), .foregroundColor: CGColor(gray: 0, alpha: 1)]))
        context.textPosition = CGPoint(x: 45, y: 275); CTLineDraw(line, context)
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://example.com/offline".utf8), "inputCorrectionLevel": "M"]))
        let code = try #require(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let cg = try #require(CIContext().createCGImage(code, from: code.extent))
        context.interpolationQuality = .none; context.draw(cg, in: CGRect(x: 410, y: 30, width: 180, height: 180))
        let image = try #require(context.makeImage())
        return try #require(MacCaptureBackend.png(image))
    }
}
