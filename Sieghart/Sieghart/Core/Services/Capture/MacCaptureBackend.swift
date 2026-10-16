import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision

protocol CaptureProviding: Sendable {
    func accessState() async -> CaptureAccessState
    func requestAccess() async -> Bool
    func selectRegion() async throws -> CapturedImage
    func readImage(_ data: Data) async throws -> CapturedImage
    func recognize(_ image: CapturedImage) async throws -> CaptureReading
    func annotate(_ image: CapturedImage, annotations: [CaptureAnnotation]) async throws -> Data
}

actor MacCaptureBackend: CaptureProviding {
    private let process: any ToolProcessRunning
    init(process: any ToolProcessRunning = NativeToolProcess()) { self.process = process }
    func accessState() -> CaptureAccessState { CGPreflightScreenCaptureAccess() ? .allowed : .needsAccess }
    func requestAccess() async -> Bool { await MainActor.run { CGRequestScreenCaptureAccess() } }
    func selectRegion() async throws -> CapturedImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureToolError.access }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sieghart-capture-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("selection.png")
        let result = try await process.run(URL(fileURLWithPath: "/usr/sbin/screencapture"), arguments: ["-i", "-x", "-t", "png", image.path])
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: image.path) else { throw CaptureToolError.cancelled }
        guard result.status == 0 else { throw CaptureToolError.failed }
        return try readImage(Data(contentsOf: image))
    }
    func readImage(_ data: Data) throws -> CapturedImage {
        guard data.count <= 20 * 1024 * 1024 else { throw CaptureToolError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 24_000_000 else { throw CaptureToolError.invalidImage }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)] as CFDictionary),
              let png = Self.png(image) else { throw CaptureToolError.invalidImage }
        guard png.count <= 20 * 1024 * 1024 else { throw CaptureToolError.tooLarge }
        return CapturedImage(png: png, width: image.width, height: image.height)
    }
    func recognize(_ image: CapturedImage) throws -> CaptureReading {
        try Task.checkCancellation()
        let text = VNRecognizeTextRequest(); text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true; text.automaticallyDetectsLanguage = true
        let codes = VNDetectBarcodesRequest(); codes.symbologies = [.qr]
        try VNImageRequestHandler(data: image.png).perform([text, codes])
        try Task.checkCancellation()
        let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let payloads = (codes.results ?? []).compactMap(\.payloadStringValue)
        return CaptureReading(text: String(lines.joined(separator: "\n").prefix(500_000)), qrPayloads: Array(Set(payloads)).sorted())
    }
    func annotate(_ image: CapturedImage, annotations: [CaptureAnnotation]) throws -> Data {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(image.png as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CaptureToolError.invalidImage }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        CaptureAnnotationRenderer.draw(annotations, in: context, size: CGSize(width: cg.width, height: cg.height))
        guard let output = context.makeImage(), let data = Self.png(output) else { throw CaptureToolError.invalidImage }
        return data
    }
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

@MainActor protocol ColorSampling { func sample() async -> SampledColor? }
@MainActor final class MacColorSampler: ColorSampling {
    func sample() async -> SampledColor? {
        let delivery = ColorSampleDelivery()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard delivery.register(continuation) else { return }
                NSColorSampler().show { color in
                    guard let color = color?.usingColorSpace(.sRGB) else { delivery.finish(nil); return }
                    delivery.finish(SampledColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent))
                }
            }
        } onCancel: { delivery.finish(nil) }
    }
}
private final class ColorSampleDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var continuation: CheckedContinuation<SampledColor?, Never>?
    func register(_ continuation: CheckedContinuation<SampledColor?, Never>) -> Bool {
        lock.withLock {
            guard !completed else { continuation.resume(returning: nil); return false }
            self.continuation = continuation; return true
        }
    }
    func finish(_ value: SampledColor?) {
        let pending = lock.withLock { let pending = continuation; continuation = nil; completed = true; return pending }
        pending?.resume(returning: value)
    }
}
