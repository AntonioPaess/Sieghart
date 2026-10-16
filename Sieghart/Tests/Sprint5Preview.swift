import AppKit
import CoreText
import Foundation
import ImageIO
import SwiftUI

private actor PreviewImageReader: CaptureProviding {
    private let local = OfflineCaptureBackend()
    func accessState() -> CaptureAccessState { .allowed }
    func requestAccess() -> Bool { false }
    func selectRegion() throws -> CapturedImage { throw CaptureToolError.cancelled }
    func readImage(_ data: Data) async throws -> CapturedImage { try await local.readImage(data) }
    func recognize(_ image: CapturedImage) async throws -> CaptureReading { try await local.recognize(image) }
    func annotate(_ image: CapturedImage, annotations: [CaptureAnnotation]) async throws -> Data { try await local.annotate(image, annotations: annotations) }
}
@MainActor private final class PreviewColorReader: ColorSampling { func sample() async -> SampledColor? { SampledColor(red: 0.77, green: 0.72, blue: 1) } }
@MainActor private final class PreviewClip: ClipboardAccess {
    func read(after changeCount: Int?, includeMedia: Bool) async -> ClipboardRead? { nil }
    func write(_ payload: ClipboardPayload) async -> Int? { 1 }
}
private final class PreviewSensor: AccelerometerProviding {
    var onSample: ((AccelerationSample) -> Void)?
    let isRunning = false
    func start() throws {}
    func stop() {}
}
@main struct Sprint5Preview {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: "Sieghart/Design/Validation/sprint-5", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("sieg-s5-preview-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let suite = "sieg.s5.preview.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0, forKey: "calendar.quietStart"); defaults.set(0, forKey: "calendar.quietEnd")
        AIProviderResources.bundle = Bundle(path: CommandLine.arguments.dropFirst().first ?? "/private/tmp/sieghart-s5-final/Build/Products/Debug/Sieghart.app")!
        let events = CompanionEventCenter(defaults: defaults, notifier: SilentCompanionTaskNotifier())
        let files = FilesViewModel(defaults: defaults, events: events, store: MemoryFilesStore(), observer: InactiveFolderObserver(), observesSystem: false)
        let brief = scratch.appendingPathComponent("One useful next step.md")
        try Data("# Today\n\nStart with one useful thing.\n".utf8).write(to: brief)
        let png = makeImage(), imageFile = scratch.appendingPathComponent("A thought to keep.png")
        try png.write(to: imageFile); await files.add([brief, imageFile], announce: false)
        let downloads = scratch.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let partial = downloads.appendingPathComponent("Design notes.pdf.crdownload")
        try Data(repeating: 0, count: 312000).write(to: partial)
        await files.addFolder(downloads)
        let id = files.folders[0].id
        for _ in 0..<200 where files.recent.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        precondition(files.recent.count == 1 && files.recent[0].partial)
        try FileManager.default.removeItem(at: partial)
        try Data(repeating: 0, count: 842000).write(to: downloads.appendingPathComponent("Design notes.pdf"))
        try Data(repeating: 0, count: 6400000).write(to: downloads.appendingPathComponent("Lecture.mp4.part"))
        files.acceptFolderScan(id, files: try await files.access.list(files.folders[0].reference))
        let capture = CaptureViewModel(events: events, backend: PreviewImageReader(), sampler: PreviewColorReader(), clipboard: PreviewClip())
        capture.prepare()
        for _ in 0..<50 where capture.accessState != .allowed { await Task.yield() }
        try await capture.accept(try await PreviewImageReader().readImage(png))
        capture.addAnnotation(CaptureAnnotation(kind: .box, points: [CGPoint(x: 0.05, y: 0.12), CGPoint(x: 0.83, y: 0.32)], ink: .coral))
        capture.extract(); await capture.waitForAction(); capture.sampleColor(); await capture.waitForAction()
        let preferences = CompanionPreferences(defaults: defaults); preferences.onboardingComplete = true
        let assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let calendar = IsolatedCalendarFixture.make(defaults: defaults)
        let notch = NotchWidgetViewModel(assistant: assistant, preferences: preferences, calendar: calendar, events: events, files: files, capture: capture, managesWindows: false)
        let activation = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false)
        let codex = CodexUsageViewModel(defaults: defaults, load: { throw CocoaError(.fileReadNoSuchFile) })
        let usage = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
        notch.activation = activation; notch.codexUsage = codex; notch.aiUsage = usage
        let sensor = SensorViewModel(reader: PreviewSensor()), gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        func render<V: View>(_ view: V, _ name: String) throws {
            let renderer = ImageRenderer(content: view.environment(\.islandPreview, true).environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: output.appendingPathComponent(name + ".png"))
        }
        func island(usageOverride: AIUsageViewModel? = nil) -> some View {
            NotchWidgetView(scrollable: false).environmentObject(notch).environmentObject(assistant).environmentObject(activation)
                .environmentObject(preferences).environmentObject(codex).environmentObject(usageOverride ?? usage).padding(36).background(Color(white: 0.2))
        }
        notch.showFiles(); try render(island(), "shelf-island")
        notch.showFiles(downloads: true); try render(island(), "downloads-island")
        try render(FilesView(model: files).frame(width: 672).padding(28).background(Color.black), "downloads-full")
        files.page = .helpers
        try render(FilesView(model: files).frame(width: 672).padding(28).background(Color.black), "helpers-full")
        notch.showCapture(); try render(island(), "capture-island")
        try render(CaptureToolsView(model: capture).frame(width: 672).padding(28).background(Color.black), "capture-full")
        let denied = CaptureViewModel(events: events, backend: OfflineCaptureBackend(), sampler: InactiveColorSampler(), clipboard: PreviewClip())
        try render(CaptureToolsView(model: denied).frame(width: 672).padding(28).background(Color.black), "capture-permission")
        files.page = .shelf
        try render(ContentView(initialSection: .files, scrollable: false).frame(width: 1050, height: 1060)
            .environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(preferences)
            .environmentObject(codex).environmentObject(usage).environmentObject(sensor).environmentObject(gestures), "files-app")
        let annotated = try await capture.renderedPNG(); try annotated.write(to: output.appendingPathComponent("annotation-export.png"))
        _ = notch.enterFileDrag(sequence: 1, point: .zero)
        notch.fileReception.move(sequence: 1, position: CGPoint(x: 0.2, y: 0.5)); try render(island(), "file-drag-left")
        notch.fileReception.move(sequence: 1, position: CGPoint(x: 0.8, y: 0.5)); try render(island(), "file-drag-right")
        notch.fileReception.move(sequence: 1, position: CGPoint(x: 0.5, y: 0.08)); try render(island(), "file-drag-top")
        notch.fileReception.move(sequence: 1, position: CGPoint(x: 0.5, y: 0.92)); try render(island(), "file-drag-bottom")
        notch.fileReception.move(sequence: 1, position: CGPoint(x: 0.08, y: 0.08)); try render(island(), "file-drag-top-left")
        notch.fileReception.move(sequence: 1, position: CGPoint(x: 0.92, y: 0.92)); try render(island(), "file-drag-bottom-right")
        preferences.reduceMotion = true
        try render(island(), "file-drag-reduced-motion")
        preferences.reduceMotion = false
        notch.fileReception.receive([imageFile]); await notch.fileReception.waitForAction()
        try render(island(), "file-attached")
        func aiPage(_ model: AIUsageViewModel) -> some View {
            AIUsageView().environmentObject(preferences).environmentObject(codex).environmentObject(model)
                .environment(\.islandGlass, true).frame(width: 800).padding(24).background(Color.black)
        }
        try render(aiPage(usage), "ada-ai-idle")
        let now = Date()
        let activeUsage = AIUsageViewModel(defaults: defaults, readClaude: { nil },
            initialAnalytics: AIAnalytics(work: [AIWork(id: "owned-preview", provider: .codex, model: "Preview model", project: "Local fixture", startedAt: now.addingTimeInterval(-72), lastSeen: now, output: 645)]), read: { _ in nil })
        try render(aiPage(activeUsage), "ada-ai-active")
        notch.fileReception.clear(); notch.aiUsage = activeUsage; notch.showIsland()
        try render(island(usageOverride: activeUsage), "ada-ai-compact")
        activeUsage.stopMonitoring()
        await files.shutdownAndFlush(); await capture.shutdown()
        print("Rendered twenty Sprint 5 views/exports with local fixtures. No app windows, screen selection, clipboard, Finder or permission requests.")
    }
    static func makeImage() -> Data {
        let context = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.96, green: 0.94, blue: 0.90, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
        for (text, y, font) in [("One useful next step.", 550.0, 64.0), ("Open your notes. Write the first sentence.", 435, 32), ("You can come back to the rest.", 360, 32)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: CTFontCreateWithName("Helvetica-Bold" as CFString, font, nil), .foregroundColor: CGColor(srgbRed: 0.15, green: 0.17, blue: 0.16, alpha: 1)]))
            context.textPosition = CGPoint(x: 80, y: y); CTLineDraw(line, context)
        }
        return MacCaptureBackend.png(context.makeImage()!)!
    }
}
