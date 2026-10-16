import AppKit
import Combine
import SwiftUI

// Report the actual selected area, including window moves and SwiftUI scaling.
// No timer or global mouse tracking is needed: native drag events drive movement.
private struct FileReceiverBoundsReporter: NSViewRepresentable {
    var onChange: (CGRect?) -> Void
    func makeNSView(context: Context) -> BoundsView { let view = BoundsView(); view.onChange = onChange; return view }
    func updateNSView(_ view: BoundsView, context: Context) { view.onChange = onChange; view.report() }
    static func dismantleNSView(_ view: BoundsView, coordinator: ()) { view.onChange?(nil); view.onChange = nil; view.observation = nil }

    final class BoundsView: NSView {
        var onChange: ((CGRect?) -> Void)?
        var observation: AnyCancellable?
        private var lastBounds: CGRect?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = nil
            if let window {
                observation = Publishers.Merge(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: window),
                                               NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window))
                    .receive(on: RunLoop.main).sink { [weak self] _ in self?.report() }
            }
            report()
        }
        override func layout() { super.layout(); report() }
        override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); report() }
        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); report() }
        func report() {
            let rect = window.map { $0.convertToScreen(convert(bounds, to: nil)) }
            guard rect != lastBounds else { return }
            lastBounds = rect; onChange?(rect)
        }
    }
}

struct IslandFileDropOverlay: NSViewRepresentable {
    var notch: NotchWidgetViewModel
    func makeNSView(context: Context) -> FileDropTargetView { let view = FileDropTargetView(); connect(view); return view }
    func updateNSView(_ view: FileDropTargetView, context: Context) { connect(view) }
    private func connect(_ view: FileDropTargetView) {
        view.onFileEnter = { [weak notch] id, point in notch?.enterFileDrag(sequence: id, point: point) == true }
        view.onFileMove = { [weak notch] id, point in notch?.moveFileDrag(sequence: id, point: point) }
        view.onFileExit = { [weak notch] id in notch?.fileReception.exit(sequence: id) }
        view.onFileDrop = { [weak notch] id, board, count in notch?.fileReception.receive(sequence: id, pasteboard: board, changeCount: count) == true }
    }
}

struct CompanionFileReceiver: View {
    @ObservedObject var model: FileReceptionViewModel
    var animates: Bool
    @EnvironmentObject private var notch: NotchWidgetViewModel
    @Environment(\.islandReduceMotion) private var reduceMotion
    @Environment(\.islandPreview) private var preview
    var body: some View {
        let reportBounds: (CGRect?) -> Void = { [weak notch] bounds in notch?.setFileReceiverBounds(bounds) }
        VStack(spacing: 0) {
            GeometryReader { size in
                let follow = animates && !reduceMotion && model.receiving
                let center = FileReceiverGeometry.characterCenter(for: model.position, in: size.size, following: follow)
                ZStack {
                    Circle().fill(RadialGradient(colors: [model.owner.processingTint.opacity(0.23), .clear],
                                                 center: .center, startRadius: 10, endRadius: 128))
                        .frame(width: 256, height: 256).position(center)
                        .allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 24).strokeBorder(CompanionStyle.accentInk.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 7]))
                        .padding(.horizontal, 4).padding(.vertical, 10)
                    CompanionCharacter(size: FileReceiverGeometry.characterSize, avatar: model.owner, animates: animates, animation: model.animation, replay: model.replay)
                        .position(center)
                }
                .background { if !preview { FileReceiverBoundsReporter(onChange: reportBounds) } }
                .animation(animates && !reduceMotion && !preview ? .interactiveSpring(response: 0.24, dampingFraction: 1) : nil, value: model.position)
            }.frame(height: FileReceiverGeometry.stageHeight)
            VStack(spacing: 5) {
                Text(model.phase == .hovering ? "Drop it here." : model.phase == .processing ? "Keeping your file nearby…" : model.phase == .ready ? "What should we do with it?" : model.phase == .failed ? "Let’s try that again." : "Got it.").font(.callout.weight(.semibold))
                Text(model.phase == .hovering ? "\(model.owner.name) is ready. Your original stays in place." : "Your file stays on this Mac.").font(.caption).foregroundStyle(CompanionStyle.muted)
            }.frame(height: FileReceiverGeometry.footerHeight)
        }.frame(height: FileReceiverGeometry.contentHeight)
        .accessibilityElement(children: .combine).accessibilityLabel(model.status)
    }
}

struct CompanionFileAttachment: View {
    @ObservedObject var model: FileReceptionViewModel
    var onFiles: () -> Void
    var onPreview: (FileReference) -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.phase == .failed ? "exclamationmark.triangle" : "doc").foregroundStyle(CompanionStyle.accentInk)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.phase == .failed ? "File could not be received" : model.attached.prefix(2).map(\.name).joined(separator: ", ")).font(.caption.weight(.semibold)).lineLimit(1)
                Text(model.status).font(.system(size: 10)).foregroundStyle(CompanionStyle.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let file = model.attached.first { Button("Preview") { onPreview(file) }.buttonStyle(.plain).font(.caption) }
            if !model.attached.isEmpty { Button("Files") { onFiles() }.buttonStyle(.plain).font(.caption) }
            Button { model.clear() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Clear attached context")
        }.padding(12).background(CompanionStyle.edge.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }
}
