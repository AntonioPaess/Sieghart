import SwiftUI

struct CanvasDiagramView: View {
    let document: GeneratedCanvas
    let diagram: CanvasDiagram
    let progress: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let outer = CGRect(x: max(28, proxy.size.width * 0.10), y: max(48, proxy.size.height * 0.08),
                width: proxy.size.width * 0.80, height: proxy.size.height * 0.78)
            let layout = CanvasDiagramLayout.make(diagram, in: outer.insetBy(dx: 48, dy: 72))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(red: 0.045, green: 0.055, blue: 0.085).opacity(0.96))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
                    .frame(width: outer.width, height: outer.height).position(x: outer.midX, y: outer.midY)
                HStack(spacing: 9) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(.cyan)
                    Text(document.title).font(.system(size: 20, weight: .semibold, design: .rounded))
                }.foregroundStyle(.white).frame(width: outer.width - 60, alignment: .leading)
                    .position(x: outer.midX, y: outer.minY + 35)
                ForEach(Array(layout.connections.enumerated()), id: \.offset) { _, connection in
                    connectionPath(connection).trimmedPath(from: 0, to: reduceMotion ? 1 : progress)
                        .stroke(Color(red: 0.48, green: 0.70, blue: 0.95), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    arrow(connection).fill(.cyan).opacity(reduceMotion || progress > 0.85 ? 1 : 0)
                    if !connection.link.label.isEmpty {
                        Text(connection.link.label).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.90)).padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color(red: 0.08, green: 0.10, blue: 0.16), in: Capsule())
                            .position(connection.label)
                    }
                }
                ForEach(layout.boxes, id: \.node.id) { box in
                    nodeCard(box.node).frame(width: box.frame.width, height: box.frame.height)
                        .position(x: box.frame.midX, y: box.frame.midY)
                }
                Text("SIEG").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(3)
                    .foregroundStyle(.white.opacity(0.30)).position(x: outer.midX, y: outer.maxY - 22)
            }
        }.allowsHitTesting(false)
    }

    private func nodeCard(_ node: CanvasDiagram.Node) -> some View {
        let accent: Color = node.emphasized == true ? .yellow : node.kind == .decision ? .orange : node.kind == .terminal ? .mint : .cyan
        return VStack(spacing: 6) {
            HStack(spacing: 7) {
                if node.kind == .decision { Image(systemName: "arrow.triangle.branch").font(.caption) }
                Text(node.title).font(.system(size: 16, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.78)
            }.foregroundStyle(.white)
            if !node.detail.isEmpty {
                Text(node.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
            }
        }.padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [accent.opacity(0.17), Color(red: 0.075, green: 0.095, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: node.kind == .terminal ? 28 : 15))
            .overlay(RoundedRectangle(cornerRadius: node.kind == .terminal ? 28 : 15).stroke(accent.opacity(0.65), lineWidth: node.emphasized == true ? 3 : 1.2))
    }

    private func connectionPath(_ c: CanvasDiagramLayout.Connection) -> Path {
        Path { p in
            p.move(to:c.start)
            if c.waypoints.isEmpty { p.addCurve(to:c.end,control1:c.control1,control2:c.control2) }
            else { for point in c.waypoints.dropFirst() { p.addLine(to:point) } }
        }
    }
    private func arrow(_ c: CanvasDiagramLayout.Connection) -> Path {
        let angle = atan2(c.end.y - c.control2.y, c.end.x - c.control2.x)
        return Path { p in
            p.move(to: c.end)
            p.addLine(to: CGPoint(x: c.end.x - 10*cos(angle - 0.45), y: c.end.y - 10*sin(angle - 0.45)))
            p.addLine(to: CGPoint(x: c.end.x - 10*cos(angle + 0.45), y: c.end.y - 10*sin(angle + 0.45)))
            p.closeSubpath()
        }
    }
}

struct SpatialCanvasControls: View {
    @ObservedObject var model: SpatialOverlayViewModel
    var body: some View {
        VStack(spacing: 8) {
        if let status = model.guidanceStatus {
            Text(status).font(.system(size: 12, weight: .medium)).lineLimit(3).multilineTextAlignment(.center)
        }
        HStack(spacing: 16) {
            Text(model.uiLanguage.hasPrefix("en") ? "On your screen" : "Na sua tela").font(.system(size: 12, weight: .semibold))
            Divider().frame(height: 18)
            if let confirm = model.confirmGuidance {
                Button(action: confirm) { Image(systemName: "checkmark.circle") }
                    .help(model.uiLanguage.hasPrefix("en") ? "I completed this step" : "Já fiz esta etapa")
                Button { model.refreshGuidance?() } label: { Image(systemName: "arrow.clockwise") }
                    .help(model.uiLanguage.hasPrefix("en") ? "Refresh target" : "Atualizar alvo")
            }
            Button { model.togglePinned() } label: { Image(systemName: model.isPinned ? "pin.fill" : "pin") }
                .help(model.uiLanguage.hasPrefix("en") ? "Keep visible" : "Manter visível")
                .accessibilityLabel(model.uiLanguage.hasPrefix("en") ? "Keep canvas visible" : "Manter desenho visível")
            if model.generatedCanvas != nil {
                Button { model.exportContent() } label: { Image(systemName: "square.and.arrow.up") }.help(model.uiLanguage.hasPrefix("en") ? "Export drawing or code" : "Exportar desenho ou código")
                Button { model.copyContent() } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel(model.uiLanguage.hasPrefix("en") ? "Copy content" : "Copiar conteúdo")
            }
            Button { model.dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel(model.uiLanguage.hasPrefix("en") ? "Close canvas" : "Fechar desenho")
        }
        }.help(model.guidanceStatus ?? "").buttonStyle(.plain).foregroundStyle(.white.opacity(0.9)).padding(.horizontal, 18).padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
    }
}
