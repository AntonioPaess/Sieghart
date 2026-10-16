import Foundation

// Offscreen previews and isolated fixtures can process supplied images without
// any route to native screen selection or permission prompts.
actor OfflineCaptureBackend: CaptureProviding {
    private let images = MacCaptureBackend()
    func accessState() -> CaptureAccessState { .needsAccess }
    func requestAccess() -> Bool { false }
    func selectRegion() throws -> CapturedImage { throw CaptureToolError.access }
    func readImage(_ data: Data) async throws -> CapturedImage { try await images.readImage(data) }
    func recognize(_ image: CapturedImage) async throws -> CaptureReading { try await images.recognize(image) }
    func annotate(_ image: CapturedImage, annotations: [CaptureAnnotation]) async throws -> Data { try await images.annotate(image, annotations: annotations) }
}
@MainActor final class InactiveColorSampler: ColorSampling { func sample() async -> SampledColor? { nil } }
