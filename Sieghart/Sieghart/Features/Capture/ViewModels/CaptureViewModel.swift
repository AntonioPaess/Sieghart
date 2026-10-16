import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

@MainActor final class CaptureViewModel: ObservableObject {
    @Published private(set) var accessState = CaptureAccessState.needsAccess
    @Published private(set) var image: CapturedImage?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var reading: CaptureReading?
    @Published private(set) var sampledColor: SampledColor?
    @Published private(set) var annotations: [CaptureAnnotation] = []
    @Published private(set) var status = "Capture an area, or bring an image you already have."
    @Published private(set) var isBusy = false
    @Published private(set) var isSelecting = false
    @Published private(set) var isSamplingColor = false
    var beforeSelection: (() -> Void)?
    var afterSelection: (() -> Void)?
    var onSavedImage: ((URL) -> Void)?
    let events: CompanionEventCenter
    private let backend: any CaptureProviding
    private let sampler: any ColorSampling
    private let clipboard: any ClipboardAccess
    private let fileAccess: any FileAccessing
    private var action: Task<Void, Never>?
    init(events: CompanionEventCenter = CompanionEventCenter(), backend: any CaptureProviding = MacCaptureBackend(),
         sampler: any ColorSampling = MacColorSampler(), clipboard: any ClipboardAccess = SystemClipboardAccess(), fileAccess: any FileAccessing = LocalFileAccess()) {
        self.events = events; self.backend = backend; self.sampler = sampler; self.clipboard = clipboard; self.fileAccess = fileAccess
    }
    func prepare() { Task { accessState = await backend.accessState() } }
    func requestAccess() { run {
        let allowed = await self.backend.requestAccess()
        try Task.checkCancellation()
        self.accessState = allowed ? .allowed : .needsAccess
        self.status = allowed ? "Screen selection is ready." : CaptureToolError.access.localizedDescription
    } }
    func openAccessSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
    func selectRegion() { run {
        guard await self.backend.accessState() == .allowed else { self.accessState = .needsAccess; throw CaptureToolError.access }
        self.isSelecting = true; self.beforeSelection?()
        defer { self.isSelecting = false; self.afterSelection?() }
        self.status = "Select an area. Press Esc to cancel."
        let captured = try await self.backend.selectRegion()
        try Task.checkCancellation()
        try await self.accept(captured)
    } }
    func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.run { guard let self else { return }; try await self.importImage(url) }
        }
    }
    func importImage(_ url: URL) async throws {
        let ref = try await fileAccess.reference(for: url), file = try await fileAccess.resolve(ref)
        defer { file.close() }
        let data = try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: file.url); defer { try? handle.close() }
            return try handle.read(upToCount: 20 * 1024 * 1024 + 1) ?? Data()
        }.value
        try Task.checkCancellation()
        let captured = try await backend.readImage(data)
        try await accept(captured)
    }
    func accept(_ captured: CapturedImage) async throws {
        let data = captured.png
        let cg = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1280] as CFDictionary)
        }.value
        try Task.checkCancellation()
        guard let cg else { throw CaptureToolError.invalidImage }
        image = captured; previewImage = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
        annotations = []; reading = nil; status = "Capture ready. Annotate, extract text or keep a copy."
        events.post(.captureReady, key: "capture:\(captured.id)", title: "Capture ready", detail: "\(captured.width) × \(captured.height) pixels")
    }
    func addAnnotation(_ annotation: CaptureAnnotation) {
        guard image != nil, !isBusy, annotations.count < 100, !annotation.points.isEmpty else { return }
        var clean = annotation
        clean.points = Array(annotation.points.prefix(2000)).map { CGPoint(x: min(1, max(0, $0.x)), y: min(1, max(0, $0.y))) }
        clean.text = String(annotation.text.prefix(100))
        guard clean.kind != .text || !clean.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        annotations.append(clean)
    }
    func undoAnnotation() { guard !isBusy, !annotations.isEmpty else { return }; annotations.removeLast() }
    func clearAnnotations() { guard !isBusy else { return }; annotations = [] }
    func extract() { guard let image else { return }; run {
        self.status = "Reading text and QR locally…"
        let result = try await self.backend.recognize(image)
        try Task.checkCancellation()
        self.reading = result
        self.status = result.text.isEmpty && result.qrPayloads.isEmpty ? "No readable text or QR found." : "Text and QR stay on this Mac."
        if !result.text.isEmpty || !result.qrPayloads.isEmpty {
            self.events.post(.captureRead, key: "capture-read:\(image.id)", title: "Text & QR ready", detail: "\(result.text.count) characters · \(result.qrPayloads.count) QR values")
        }
    } }
    func renderedPNG() async throws -> Data {
        guard let image else { throw CaptureToolError.invalidImage }
        return annotations.isEmpty ? image.png : try await backend.annotate(image, annotations: annotations)
    }
    func copyImage() { run {
        let data = try await self.renderedPNG(); try Task.checkCancellation()
        let payload = ClipboardPayload(kind: .image, image: data)
        guard payload.valid else { throw FileToolError.message("This image is too large for the clipboard. Save it as PNG instead.") }
        self.status = await self.clipboard.write(payload) != nil ? "Image copied." : "Could not copy this image."
    } }
    func copyText(_ text: String) { run {
        guard !text.isEmpty else { return }
        self.status = await self.clipboard.write(ClipboardPayload(kind: .text, text: text)) != nil ? "Copied." : "Could not copy."
    } }
    func saveImage() {
        guard image != nil, !isBusy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Sieghart Capture.png"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.run {
                guard let self else { return }
                let data = try await self.renderedPNG(); try Task.checkCancellation()
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try await Task.detached(priority: .utility) { try data.write(to: url, options: .atomic) }.value
                self.status = "PNG saved."; self.onSavedImage?(url)
                self.events.post(.fileReady, key: "saved-capture:\(UUID())", title: "Capture saved", detail: url.lastPathComponent)
            }
        }
    }
    func sampleColor() { guard !isBusy, !isSamplingColor else { return }; isSamplingColor = true
        action = Task { [weak self] in
            guard let self else { return }; defer { self.isSamplingColor = false }
            let value = await self.sampler.sample()
            guard !Task.isCancelled else { return }
            self.sampledColor = value; self.status = value == nil ? "Color selection cancelled." : "Color picked."
        }
    }
    func openQR(_ value: String) {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { status = "Copy this QR value to use it in its own app."; return }
        status = NSWorkspace.shared.open(url) ? "Link opened." : "This link could not be opened."
    }
    func discard() { guard !isBusy else { return }; image = nil; previewImage = nil; reading = nil; annotations = []; status = "Capture cleared." }
    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !isSamplingColor else { return }; isBusy = true
        action = Task { [weak self] in
            guard let self else { return }; defer { self.isBusy = false }
            do { try await body() }
            catch is CancellationError { self.status = "Action cancelled." }
            catch CaptureToolError.cancelled { self.status = "Capture cancelled." }
            catch { self.status = error.localizedDescription }
        }
    }
    func cancel() { action?.cancel() }
    func waitForAction() async { await action?.value }
    func shutdown() async { cancel(); await waitForAction(); image = nil; previewImage = nil; annotations = [] }
}
