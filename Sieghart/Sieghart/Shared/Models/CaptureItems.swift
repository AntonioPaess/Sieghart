import Foundation
import CoreGraphics

enum CaptureAccessState: Equatable, Sendable { case allowed, needsAccess }
struct CapturedImage: Identifiable, Sendable {
    var id = UUID()
    var png: Data
    var width: Int
    var height: Int
    var capturedAt = Date()
}
struct CaptureReading: Equatable, Sendable { var text: String; var qrPayloads: [String] }
enum CaptureAnnotationKind: String, CaseIterable, Sendable { case pen = "Pen", box = "Box", arrow = "Arrow", text = "Text" }
enum CaptureInk: String, CaseIterable, Sendable { case lavender = "Lavender", coral = "Coral", yellow = "Yellow" }
struct CaptureAnnotation: Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: CaptureAnnotationKind
    var points: [CGPoint]
    var ink: CaptureInk
    var text = ""
}
struct SampledColor: Equatable, Sendable { var red: Double; var green: Double; var blue: Double
    var hex: String { String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
}
enum CaptureToolError: Error, LocalizedError, Equatable {
    case access, cancelled, invalidImage, tooLarge, failed
    var errorDescription: String? {
        switch self {
        case .access: "Allow Sieghart in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
        case .cancelled: "Capture cancelled."
        case .invalidImage: "This image could not be read."
        case .tooLarge: "Choose a smaller region or image (up to 24 megapixels and 20 MB)."
        case .failed: "The screen selection could not be captured. Try again."
        }
    }
}
