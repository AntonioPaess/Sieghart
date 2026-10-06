import AppKit
import SwiftUI

private struct IslandGlassKey: EnvironmentKey { static let defaultValue = false }
private struct IslandCanvasKey: EnvironmentKey { static let defaultValue = false }
private struct IslandPreviewKey: EnvironmentKey { static let defaultValue = false }
private struct IslandMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var islandGlass: Bool { get { self[IslandGlassKey.self] } set { self[IslandGlassKey.self] = newValue } }
    var nativeIslandCanvas: Bool { get { self[IslandCanvasKey.self] } set { self[IslandCanvasKey.self] = newValue } }
    var islandPreview: Bool { get { self[IslandPreviewKey.self] } set { self[IslandPreviewKey.self] = newValue } }
    var islandReduceMotion: Bool { get { self[IslandMotionKey.self] } set { self[IslandMotionKey.self] = newValue } }
}

// A shoulder meets the screen edge; the lower corners grow with the island.
struct NotchPanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder = min(16, rect.height / 5)
        let lower = max(0, min(28, rect.height * 0.34, (rect.width - shoulder * 2) / 2))
        let left = rect.minX + shoulder, right = rect.maxX - shoulder
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + shoulder), control: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - lower))
        path.addQuadCurve(to: CGPoint(x: right - lower, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + lower, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - lower), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct IslandControlSurface: ViewModifier {
    var selected = false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(opaque ? Color(white: 0.13) : .white.opacity(selected ? 0.13 : 0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(contrast == .increased ? 0.5 : selected ? 0.2 : 0.09), lineWidth: 0.75).allowsHitTesting(false) }
    }
}

struct IslandButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandReduceMotion) private var preferenceReduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(hovering && enabled ? 0.06 : 0)
            .scaleEffect(reduceMotion || preferenceReduceMotion ? 1 : configuration.isPressed ? 0.94 : hovering && enabled ? 1.045 : 1)
            .opacity(enabled ? configuration.isPressed ? 0.8 : 1 : 0.4)
            .animation(reduceMotion || preferenceReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: configuration.isPressed)
            .animation(reduceMotion || preferenceReduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.8), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct IslandBackdrop: View {
    var compact: Bool
    var stripHeight: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.islandPreview) private var preview
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if compact || opaque { Color.black }
                else {
                    if preview { Color(white: 0.34) }
                    else { IslandGlassLens() }
                    LinearGradient(stops: Self.stops(height: geometry.size.height, strip: stripHeight), startPoint: .top, endPoint: .bottom)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
    static func stops(height: CGFloat, strip: CGFloat) -> [Gradient.Stop] {
        let camera = min(1, max(0, strip / max(1, height)))
        return [.init(color: .black, location: 0), .init(color: .black, location: camera), .init(color: .black.opacity(0.88), location: min(1, camera + 0.12)), .init(color: .black.opacity(0.52), location: 1)]
    }
}

private struct IslandGlassLens: View {
    var body: some View {
        Group {
            if #available(macOS 26, *) { Color.clear.glassEffect(.clear, in: Rectangle()) }
            else { IslandBlur() }
        }
    }
}

private struct IslandBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { }
}

// The native window reserves the whole transition. Only the silhouette moves:
// the content is laid out once at its destination, then fades into the shell.
struct IslandCanvasGeometry {
    let size: CGSize
    let cutoutWidth: CGFloat
    let cutoutHeight: CGFloat
    let compact: Bool
    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
}

// The island is a nonactivating overlay. Its first click must run the action
// even when another application owns keyboard focus.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class IslandWindowCanvas<Content: View>: NSView {
    private let host: NSHostingView<Content>
    private let backdrop = NSHostingView(rootView: IslandBackdrop(compact: true, stripHeight: 0))
    private let outline = CAShapeLayer()
    private let maskLayer = CAShapeLayer()
    private var surface: CGSize = .zero
    private(set) var isDeparting = false
    private var completion: Task<Void, Never>?
    override var isFlipped: Bool { true }
    init(rootView: Content) {
        host = IslandHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        backdrop.wantsLayer = true; host.wantsLayer = true
        backdrop.layer?.mask = maskLayer
        addSubview(backdrop); addSubview(host)
        host.focusRingType = .none; host.sizingOptions = []
        outline.fillColor = nil; outline.strokeColor = NSColor.white.withAlphaComponent(0.055).cgColor; outline.lineWidth = 0.5
        layer?.addSublayer(outline)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var currentSurface: CGSize { surface }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func prepare(target: IslandCanvasGeometry, reserved: CGSize, animated: Bool, closing: Bool, settled: @escaping @MainActor () -> Void) {
        completion?.cancel()
        isDeparting = closing
        let previous = surface == .zero ? CGSize(width: max(180, target.cutoutWidth), height: max(1, target.cutoutHeight)) : surface
        surface = target.size
        outline.isHidden = target.compact || closing
        let gutter: CGFloat = target.compact ? 0 : 72
        let extra: CGFloat = target.compact ? 0 : 64
        let previousCanvasWidth = bounds.width
        setFrameSize(reserved)
        backdrop.frame = bounds
        host.frame = CGRect(x: (reserved.width - target.width - gutter * 2) / 2, y: 0, width: target.width + gutter * 2, height: target.height + extra)
        backdrop.rootView = IslandBackdrop(compact: target.compact || closing, stripHeight: target.cutoutHeight)
        let endPath = Self.path(size: target.size, canvasWidth: reserved.width)
        var translation = CGAffineTransform(translationX: (reserved.width - previousCanvasWidth) / 2, y: 0)
        let visiblePath = maskLayer.presentation()?.path?.copy(using: &translation)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        maskLayer.frame = bounds; outline.frame = bounds
        maskLayer.path = endPath; outline.path = endPath
        CATransaction.commit()
        guard animated, previous != target.size else {
            maskLayer.removeAllAnimations(); outline.removeAllAnimations(); host.layer?.removeAllAnimations()
            host.alphaValue = closing ? 0 : 1; settled(); return
        }
        let duration = target.height > previous.height ? 0.46 : 0.28
        let animation = CAKeyframeAnimation(keyPath: "path")
        // Sample the contour itself so corner radii stay circular while resizing.
        animation.values = (0...60).map { index -> CGPath in
            if index == 0, let visiblePath { return visiblePath }
            let t = Double(index) / 60, eased = t * t * (3 - 2 * t)
            let size = CGSize(width: previous.width + (target.width - previous.width) * eased, height: previous.height + (target.height - previous.height) * eased)
            return Self.path(size: size, canvasWidth: reserved.width)
        }
        animation.duration = duration; animation.calculationMode = .linear
        maskLayer.add(animation, forKey: "island.contour"); outline.add(animation, forKey: "island.contour")
        host.alphaValue = closing ? 0 : 1
        if !closing {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1; fade.beginTime = CACurrentMediaTime() + duration * 0.55
            fade.fillMode = .backwards; fade.duration = duration * 0.45
            host.layer?.add(fade, forKey: "island.content")
        }
        completion = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self != nil else { return }
            settled()
        }
    }
    static func path(size: CGSize, canvasWidth: CGFloat) -> CGPath {
        NotchPanelShape().path(in: CGRect(x: (canvasWidth - size.width) / 2, y: 0, width: size.width, height: size.height)).cgPath
    }
}
