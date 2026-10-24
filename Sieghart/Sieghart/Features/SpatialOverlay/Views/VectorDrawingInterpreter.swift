import Foundation
import SwiftUI

/// Supported procedural vector shapes for the Spatial Canvas overlay.
enum SpatialVectorShape: String, CaseIterable, Codable, Sendable, Equatable {
    case rocket
    case star
    case arrow
    case circle
    case heart
    case checkmark
    case triangle
    case rightTriangle

    var displayTitle: String {
        switch self {
        case .rocket: "Foguete Espacial"
        case .star: "Estrela"
        case .arrow: "Seta Direcional"
        case .circle: "Círculo"
        case .heart: "Coração"
        case .checkmark: "Confirmação"
        case .triangle: "Triângulo"
        case .rightTriangle: "Triângulo Retângulo"
        }
    }

    func acknowledgement(language: String) -> String {
        language.hasPrefix("en") ? "Done. I've drawn it on your screen." : spokenAcknowledgement
    }

    var spokenAcknowledgement: String {
        switch self {
        case .rocket: "Desenhando um foguete na sua tela agora!"
        case .star: "Desenhando uma estrela brilhante na sua tela!"
        case .arrow: "Traçando uma seta na sua tela!"
        case .circle: "Desenhando um círculo na sua tela!"
        case .heart: "Desenhando um coração na sua tela!"
        case .checkmark: "Marcando um check na sua tela!"
        case .triangle: "Desenhando um triângulo na sua tela!"
        case .rightTriangle: "Desenhando um triângulo retângulo na sua tela!"
        }
    }
}

/// A text annotation placed in canvas coordinates alongside its vector segment.
struct SpatialVectorLabel: Equatable, Sendable {
    let text: String
    let position: CGPoint
    let rotationDegrees: Double
}

/// Describes a vector drawing rendered on `SpatialCanvasOverlay`.
struct SpatialVectorDrawing: Identifiable, Equatable, Sendable {
    let id: UUID
    let shape: SpatialVectorShape
    let prompt: String
    let canvasRect: CGRect
    let holdDuration: TimeInterval

    init(
        id: UUID = UUID(),
        shape: SpatialVectorShape,
        prompt: String,
        canvasRect: CGRect = CGRect(x: 0, y: 0, width: 320, height: 320),
        holdDuration: TimeInterval = 3.2
    ) {
        self.id = id
        self.shape = shape
        self.prompt = prompt
        self.canvasRect = canvasRect
        self.holdDuration = holdDuration
    }

    func labels(in rect: CGRect) -> [SpatialVectorLabel] {
        VectorDrawingInterpreter.labels(for: shape, prompt: prompt, in: rect)
    }
}

/// Procedural vector path generator and natural-language interpreter for spatial screen drawing.
enum VectorDrawingInterpreter {
    /// Parses natural-language commands such as "Desenhe um foguete na minha tela" or "Draw a rocket on my screen".
    static func parseShape(from transcript: String) -> SpatialVectorShape? {
        let request = SearchVoiceParser.requestText(transcript)
        guard !SearchVoiceParser.hasSearchIntent(request), !SearchVoiceParser.hasQuestionIntent(request) else { return nil }
        let normalized = normalize(transcript)

        let drawTriggers = [
            "desenh", "trace", "tracar", "rabisc", "draw", "sketch", "pinte", "pintar", "ilustr"
        ]
        guard drawTriggers.contains(where: { normalized.contains($0) }) else {
            return nil
        }
        let negations = ["nao desenh", "don't draw", "don’t draw", "do not draw", "nunca desenh"]
        guard !negations.contains(where: { normalized.contains($0) }) else {
            return nil
        }

        if normalized.contains("triangulo") || normalized.contains("triangle") ||
            normalized.contains("hipotenusa") || normalized.contains("hypotenuse") || normalized.contains("cateto") {
            let isRightTriangle = ["retangulo", "right", "hipotenusa", "hypotenuse", "cateto"]
                .contains(where: { normalized.contains($0) })
            return isRightTriangle ? .rightTriangle : .triangle
        }
        if normalized.contains("foguete") || normalized.contains("rocket") || normalized.contains("nave") {
            return .rocket
        }
        if normalized.contains("estrela") || normalized.contains("star") {
            return .star
        }
        if normalized.contains("seta") || normalized.contains("flecha") || normalized.contains("arrow") {
            return .arrow
        }
        if normalized.contains("circulo") || normalized.contains("circle") || normalized.contains("anel") ||
            normalized.contains("circunferencia") || normalized.contains("circumference") {
            return .circle
        }
        if normalized.contains("coracao") || normalized.contains("heart") {
            return .heart
        }
        if normalized.contains("check") || normalized.contains("confirma") || normalized.contains("visto") {
            return .checkmark
        }
        return nil
    }

    /// Preserve the explanation in a compound request instead of consuming the
    /// entire transcript as a drawing acknowledgement.
    static func explanationRequest(in transcript: String) -> String? {
        let pattern = #"\b(?:e|and|then)\s+(?:(?:me|tamb[eé]m|depois|please)\s+)*((?:expli(?:ca|car|que)|explain|fal[ae]|falar|conte|tell|ensine|teach|o que|como|what|why|how)\b.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)),
              let range = Range(match.range(at: 1), in: transcript) else { return nil }
        return String(transcript[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generates a continuous procedural `Path` inside `rect` suitable for `trim(from: 0, to: progress)` animation.
    static func path(for shape: SpatialVectorShape, in rect: CGRect) -> Path {
        switch shape {
        case .rocket:
            return rocketPath(in: rect)
        case .star:
            return starPath(in: rect)
        case .arrow:
            return arrowPath(in: rect)
        case .circle:
            return circlePath(in: rect)
        case .heart:
            return heartPath(in: rect)
        case .checkmark:
            return checkmarkPath(in: rect)
        case .triangle:
            return trianglePath(in: rect, rightAngled: false)
        case .rightTriangle:
            return trianglePath(in: rect, rightAngled: true)
        }
    }

    static func labels(for shape: SpatialVectorShape, prompt: String, in rect: CGRect) -> [SpatialVectorLabel] {
        let normalized = normalize(prompt)
        guard shape == .rightTriangle,
              normalized.contains("hipotenusa") || normalized.contains("hypotenuse") else { return [] }
        // The hypotenuse joins the top-left and bottom-right vertices. Offset
        // its label along the outward normal, including on non-square canvases.
        let start = point(0.16, 0.16, in: rect)
        let end = point(0.84, 0.84, in: rect)
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return [] }
        return [SpatialVectorLabel(
            text: "Hipotenusa",
            position: CGPoint(x: (start.x + end.x) / 2 + dy / length * 24,
                              y: (start.y + end.y) / 2 - dx / length * 24),
            rotationDegrees: atan2(dy, dx) * 180 / .pi
        )]
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func point(_ nx: CGFloat, _ ny: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + nx * rect.width, y: rect.minY + ny * rect.height)
    }

    private static func trianglePath(in rect: CGRect, rightAngled: Bool) -> Path {
        var path = Path()
        path.move(to: point(rightAngled ? 0.16 : 0.50, 0.16, in: rect))
        path.addLine(to: point(0.16, 0.84, in: rect))
        path.addLine(to: point(0.84, 0.84, in: rect))
        path.closeSubpath()
        if rightAngled {
            path.move(to: point(0.16, 0.76, in: rect))
            path.addLine(to: point(0.24, 0.76, in: rect))
            path.addLine(to: point(0.24, 0.84, in: rect))
        }
        return path
    }

    private static func rocketPath(in rect: CGRect) -> Path {
        var path = Path()
        // 1. Nose cone & fuselage outer contour
        path.move(to: point(0.50, 0.08, in: rect))
        path.addQuadCurve(
            to: point(0.66, 0.34, in: rect),
            control: point(0.65, 0.16, in: rect)
        )
        path.addLine(to: point(0.66, 0.66, in: rect))
        // Right fin
        path.addLine(to: point(0.82, 0.78, in: rect))
        path.addLine(to: point(0.78, 0.84, in: rect))
        path.addLine(to: point(0.64, 0.74, in: rect))
        // Nozzle base
        path.addLine(to: point(0.60, 0.78, in: rect))
        path.addLine(to: point(0.40, 0.78, in: rect))
        path.addLine(to: point(0.36, 0.74, in: rect))
        // Left fin
        path.addLine(to: point(0.22, 0.84, in: rect))
        path.addLine(to: point(0.18, 0.78, in: rect))
        path.addLine(to: point(0.34, 0.66, in: rect))
        // Left fuselage up to nose tip
        path.addLine(to: point(0.34, 0.34, in: rect))
        path.addQuadCurve(
            to: point(0.50, 0.08, in: rect),
            control: point(0.35, 0.16, in: rect)
        )
        path.closeSubpath()

        // 2. Nose collar line
        path.move(to: point(0.35, 0.30, in: rect))
        path.addLine(to: point(0.65, 0.30, in: rect))

        // 3. Porthole window
        let windowRadius = min(rect.width, rect.height) * 0.085
        let windowCenter = point(0.50, 0.46, in: rect)
        path.addEllipse(
            in: CGRect(
                x: windowCenter.x - windowRadius,
                y: windowCenter.y - windowRadius,
                width: windowRadius * 2,
                height: windowRadius * 2
            )
        )

        // 4. Exhaust flame plume
        path.move(to: point(0.42, 0.78, in: rect))
        path.addQuadCurve(
            to: point(0.50, 0.95, in: rect),
            control: point(0.38, 0.89, in: rect)
        )
        path.addQuadCurve(
            to: point(0.58, 0.78, in: rect),
            control: point(0.62, 0.89, in: rect)
        )
        return path
    }

    private static func starPath(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) * 0.42
        let innerRadius = outerRadius * 0.42
        for i in 0..<10 {
            let angle = (Double(i) * .pi / 5.0) - (.pi / 2.0)
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let pt = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        path.closeSubpath()
        return path
    }

    private static func arrowPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.15, 0.75, in: rect))
        path.addQuadCurve(
            to: point(0.82, 0.22, in: rect),
            control: point(0.45, 0.65, in: rect)
        )
        path.move(to: point(0.62, 0.20, in: rect))
        path.addLine(to: point(0.82, 0.22, in: rect))
        path.addLine(to: point(0.78, 0.42, in: rect))
        return path
    }

    private static func circlePath(in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.14
        var path = Path()
        path.addEllipse(in: rect.insetBy(dx: inset, dy: inset))
        return path
    }

    private static func heartPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.50, 0.84, in: rect))
        path.addCurve(
            to: point(0.14, 0.36, in: rect),
            control1: point(0.20, 0.68, in: rect),
            control2: point(0.14, 0.48, in: rect)
        )
        path.addArc(
            center: point(0.32, 0.32, in: rect),
            radius: rect.width * 0.18,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addArc(
            center: point(0.68, 0.32, in: rect),
            radius: rect.width * 0.18,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addCurve(
            to: point(0.50, 0.84, in: rect),
            control1: point(0.86, 0.48, in: rect),
            control2: point(0.80, 0.68, in: rect)
        )
        path.closeSubpath()
        return path
    }

    private static func checkmarkPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.20, 0.54, in: rect))
        path.addLine(to: point(0.42, 0.76, in: rect))
        path.addLine(to: point(0.82, 0.26, in: rect))
        return path
    }
}
