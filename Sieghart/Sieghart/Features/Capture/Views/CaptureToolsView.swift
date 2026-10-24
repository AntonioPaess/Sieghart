import AppKit
import SwiftUI

struct CaptureToolsView: View {
    @ObservedObject var model: CaptureViewModel
    var compact = false
    @Environment(\.islandPreview) private var preview
    @Environment(\.islandReduceMotion) private var reduceMotion
    @State private var tool = CaptureAnnotationKind.pen
    @State private var ink = CaptureInk.lavender
    @State private var annotationText = ""
    @State private var stroke: [CGPoint] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                CompanionTaskCharacter(events: model.events, avatar: .toni, size: compact ? 64 : 78,
                                       animates: !reduceMotion, working: model.isBusy && !model.isSelecting)
                VStack(alignment: .leading, spacing: 5) {
                    Text("TONI · CAPTURE & SHARE").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(CompanionStyle.accentInk)
                    Text("Keep what matters.").font(.system(size: compact ? 20 : 24, weight: .semibold))
                    Text("An area, a thought, a color.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button("Select an area") { model.selectRegion() }.buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
                    .disabled(model.accessState != .allowed || model.isBusy || model.isSamplingColor)
                Button("Bring an image") { model.chooseImage() }.buttonStyle(CompanionButtonStyle(compact: compact)).disabled(model.isBusy || model.isSamplingColor)
                if !compact { Button("Pick a color") { model.sampleColor() }.buttonStyle(CompanionButtonStyle(compact: compact)).disabled(model.isBusy || model.isSamplingColor) }
            }
            if model.accessState != .allowed {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A screen selection needs your permission.").font(.callout.weight(.medium))
                    Text("You can still bring an image and read its text or QR without screen access.").font(.caption).foregroundStyle(CompanionStyle.muted)
                    HStack(spacing: 12) {
                        Button("Allow screen access") { model.requestAccess() }
                        Button("Open System Settings") { model.openAccessSettings() }
                    }.font(.caption).buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk).disabled(model.isBusy)
                }.padding(14).background(CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            if let image = model.image, let photo = model.previewImage {
                HStack {
                    Text("\(image.width) × \(image.height)").font(.caption).monospacedDigit().foregroundStyle(CompanionStyle.muted)
                    Spacer()
                    Button("Clear capture") { model.discard() }.font(.caption).buttonStyle(.plain).disabled(model.isBusy)
                }
                annotationControls
                GeometryReader { container in
                    let ratio = CGFloat(image.width) / CGFloat(image.height)
                    let width = min(container.size.width, container.size.height * ratio)
                    let height = width / ratio
                    ZStack {
                        Image(nsImage: photo).resizable().frame(width: width, height: height)
                        annotationCanvas(size: CGSize(width: width, height: height))
                    }
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard !model.isBusy else { return }
                        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: min(1, max(0, p.x / width)), y: min(1, max(0, p.y / height))) }
                        if stroke.isEmpty { stroke = [point(value.startLocation)] }
                        if tool == .pen { if stroke.count < 2000 { stroke.append(point(value.location)) } }
                        else if tool != .text { stroke = [stroke[0], point(value.location)] }
                    }.onEnded { _ in
                        model.addAnnotation(CaptureAnnotation(kind: tool, points: stroke, ink: ink, text: annotationText)); stroke = []
                    })
                    .position(x: container.size.width / 2, y: container.size.height / 2)
                }
                .frame(height: compact ? 190 : 310)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .clipped()
                HStack(spacing: 12) {
                    Button("Copy image") { model.copyImage() }
                    Button("Save PNG") { model.saveImage() }
                    Button("Read text & QR") { model.extract() }
                }.buttonStyle(CompanionButtonStyle(compact: compact)).disabled(model.isBusy)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "viewfinder").font(.system(size: 30)).foregroundStyle(CompanionStyle.accentInk)
                    Text("One useful piece of your screen.").font(.callout.weight(.medium))
                    Text("Select a region. Esc cancels without keeping a capture.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            if let reading = model.reading {
                if !reading.text.isEmpty {
                    HStack { Text("EXTRACTED TEXT").font(.system(size: 9, weight: .semibold)).tracking(1); Spacer(); Button("Copy text") { model.copyText(reading.text) }.font(.caption).buttonStyle(.plain) }
                    if preview { Text(reading.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                    else { ScrollView { Text(reading.text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 130) }
                }
                ForEach(Array(reading.qrPayloads.prefix(10)), id: \.self) { value in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(value, systemImage: "qrcode").font(.caption).textSelection(.enabled)
                        HStack {
                            Button("Copy value") { model.copyText(value) }
                            if let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Button("Open link") { model.openQR(value) } }
                        }.font(.caption).buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk)
                    }
                }
            }
            HStack(spacing: 10) {
                if compact { Button("Pick a color") { model.sampleColor() }.buttonStyle(CompanionButtonStyle(compact: true)).disabled(model.isBusy || model.isSamplingColor) }
                if let color = model.sampledColor {
                    RoundedRectangle(cornerRadius: 6).fill(Color(red: color.red, green: color.green, blue: color.blue)).frame(width: 26, height: 26)
                    Text(color.hex).font(.caption.monospaced())
                    Button("Copy hex") { model.copyText(color.hex) }.font(.caption).buttonStyle(.plain)
                }
                if model.isSamplingColor { Text("Click a color. Esc cancels.").font(.caption).foregroundStyle(CompanionStyle.muted) }
            }
            HStack {
                Text(LocalizedStringKey(model.status)).font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if model.isBusy { ProgressView().controlSize(.small); Button("Cancel") { model.cancel() }.font(.caption).buttonStyle(.plain) }
            }
            TaskNotificationPreferences(events: model.events, module: .capture)
            TaskCardsView(events: model.events, module: .capture)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if !preview { model.prepare() } }
    }
    private var annotationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if preview {
                    Text(tool.rawValue).font(.caption).padding(7).background(CompanionStyle.edge.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    Text(ink.rawValue).font(.caption).padding(7).background(CompanionStyle.edge.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                } else {
                    Picker("Annotation", selection: $tool) { ForEach(CaptureAnnotationKind.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }.labelsHidden()
                    Picker("Ink", selection: $ink) { ForEach(CaptureInk.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }.labelsHidden()
                }
                Button { model.undoAnnotation() } label: { Image(systemName: "arrow.uturn.backward") }.help("Undo annotation").accessibilityLabel("Undo annotation")
                Button("Clear marks") { model.clearAnnotations() }.font(.caption)
            }.disabled(model.isBusy)
            if tool == .text { TextField("Text, then click where it belongs", text: $annotationText).textFieldStyle(.roundedBorder) }
        }
    }
    private func annotationCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let pending = stroke.isEmpty ? [] : [CaptureAnnotation(kind: tool, points: stroke, ink: ink, text: annotationText)]
            for annotation in model.annotations + pending {
                guard let p = annotation.points.first else { continue }
                func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * canvasSize.width, y: p.y * canvasSize.height) }
                let start = point(p), end = point(annotation.points.last ?? p), color = Color(cgColor: annotation.ink.cgColor)
                var path = Path()
                switch annotation.kind {
                case .pen: path.move(to: start); for p in annotation.points.dropFirst() { path.addLine(to: point(p)) }
                case .box: path.addRect(CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
                case .arrow:
                    let angle = atan2(end.y - start.y, end.x - start.x), length = max(9, min(canvasSize.width, canvasSize.height) * 0.025)
                    path.move(to: start); path.addLine(to: end)
                    path.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
                    path.addLine(to: end); path.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
                case .text:
                    let fontSize = max(12, min(canvasSize.width, canvasSize.height) * 0.035)
                    context.draw(Text(annotation.text).font(.custom("Helvetica-Bold", size: fontSize)).foregroundStyle(color), at: start, anchor: .topLeading)
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(2, min(canvasSize.width, canvasSize.height) * 0.004), lineCap: .round, lineJoin: .round))
            }
        }.frame(width: size.width, height: size.height).allowsHitTesting(false)
    }
}
