import SwiftUI

struct GeneratedCanvasView: View {
    let document: GeneratedCanvas
    let progress: CGFloat
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(x: proxy.size.width * 0.14, y: proxy.size.height * 0.15,
                                width: proxy.size.width * 0.72, height: proxy.size.height * 0.68)
            if let diagram = document.diagram {
                CanvasDiagramView(document: document, diagram: diagram, progress: progress)
            } else if document.isCode {
                codeCard(in: proxy.size)
            } else {
                ForEach(Array(document.elements.enumerated()), id: \.offset) { _, element in
                    if element.kind == .text, let point = element.points.first {
                        Text(element.text).font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(color(element.ink)).padding(5)
                            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                            .frame(maxWidth: bounds.width * 0.42).fixedSize(horizontal: false, vertical: true)
                            .position(mapped(point, in: bounds))
                    } else {
                        let path = Self.path(for: element, in: bounds)
                        if element.filled { path.fill(color(element.ink).opacity(0.20)) }
                        path.trimmedPath(from: 0, to: progress)
                            .stroke(color(element.ink), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                            .shadow(color: color(element.ink).opacity(0.6), radius: 5)
                    }
                }
                Text(document.title).font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.78), in: Capsule())
                    .position(x: bounds.midX, y: max(32, bounds.minY - 26))
            }
        }.opacity(opacity).allowsHitTesting(false)
    }

    private func codeCard(in size: CGSize) -> some View {
        let lines = max(1, document.code.components(separatedBy: "\n").count)
        let fontSize = min(15.0, max(9.0, (size.height * 0.78 - 80) / Double(lines) / 1.4))
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(document.title, systemImage: "chevron.left.forwardslash.chevron.right").font(.headline)
                Spacer()
                Text(document.codeLanguage).font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Text(document.code).font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(Color(red: 0.83, green: 0.91, blue: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white).padding(24)
        .frame(width: min(920, size.width - 100), alignment: .leading)
        .background(Color(red: 0.07, green: 0.085, blue: 0.12).opacity(0.97), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.cyan.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .position(x: size.width / 2, y: size.height / 2)
    }

    @MainActor static func path(for element: CanvasElement, in rect: CGRect) -> Path {
        let points = element.points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        guard let first = points.first else { return Path() }
        return Path { path in
            switch element.kind {
            case .ellipse, .rectangle:
                guard points.count >= 2 else { return }
                let box = CGRect(x: min(first.x, points[1].x), y: min(first.y, points[1].y),
                                 width: abs(points[1].x - first.x), height: abs(points[1].y - first.y))
                if element.kind == .ellipse { path.addEllipse(in: box) } else { path.addRect(box) }
            case .bezier:
                guard points.count >= 4 else { return }
                path.move(to: first); path.addCurve(to: points[3], control1: points[1], control2: points[2])
            case .polyline, .polygon:
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                if element.kind == .polygon { path.closeSubpath() }
            case .text: break
            }
        }
    }
    private func mapped(_ point: CanvasPoint, in rect: CGRect) -> CGPoint {
        .init(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
    private func color(_ ink: CanvasInk) -> Color {
        switch ink {
        case .cyan: .cyan
        case .purple: Color(red: 0.77, green: 0.60, blue: 1)
        case .gold: Color(red: 1, green: 0.79, blue: 0.34)
        case .white: .white
        case .green: .mint
        case .red: Color(red: 1, green: 0.40, blue: 0.42)
        }
    }
}
