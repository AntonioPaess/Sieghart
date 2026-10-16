import AppKit
import CoreText

extension CaptureInk {
    var cgColor: CGColor {
        switch self {
        case .lavender: CGColor(srgbRed: 0.77, green: 0.72, blue: 1, alpha: 1)
        case .coral: CGColor(srgbRed: 1, green: 0.40, blue: 0.37, alpha: 1)
        case .yellow: CGColor(srgbRed: 1, green: 0.82, blue: 0.25, alpha: 1)
        }
    }
}
enum CaptureAnnotationRenderer {
    static func draw(_ annotations: [CaptureAnnotation], in context: CGContext, size: CGSize) {
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: min(1, max(0, p.x)) * size.width, y: (1 - min(1, max(0, p.y))) * size.height) }
        for annotation in annotations.prefix(100) {
            guard let first = annotation.points.first else { continue }
            let start = point(first), end = point(annotation.points.last ?? first)
            context.saveGState(); defer { context.restoreGState() }
            context.setStrokeColor(annotation.ink.cgColor); context.setFillColor(annotation.ink.cgColor)
            context.setLineWidth(max(2, min(size.width, size.height) * 0.004)); context.setLineCap(.round); context.setLineJoin(.round)
            switch annotation.kind {
            case .pen:
                context.beginPath(); context.move(to: start)
                for p in annotation.points.dropFirst().prefix(2000) { context.addLine(to: point(p)) }
                context.strokePath()
            case .box:
                context.stroke(CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
            case .arrow:
                let angle = atan2(end.y - start.y, end.x - start.x), length = max(9, min(size.width, size.height) * 0.025)
                context.beginPath(); context.move(to: start); context.addLine(to: end)
                context.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
                context.addLine(to: end); context.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
                context.strokePath()
            case .text:
                let fontSize = max(12, min(size.width, size.height) * 0.035)
                let attributes: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil), .foregroundColor: annotation.ink.cgColor]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(annotation.text.prefix(100)), attributes: attributes))
                context.textMatrix = .identity; context.textPosition = CGPoint(x: start.x, y: start.y - fontSize)
                CTLineDraw(line, context)
            }
        }
    }
}
