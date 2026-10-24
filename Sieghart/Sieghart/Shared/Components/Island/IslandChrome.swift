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
    @Environment(\.surfaceGlassEnabled) private var glass
    func body(content: Content) -> some View {
        content.background(!glass || opaque ? CompanionStyle.surface : CompanionStyle.edge.opacity(selected ? 0.13 : 0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CompanionStyle.edge.opacity(contrast == .increased ? 0.5 : selected ? 0.2 : 0.09), lineWidth: 0.75).allowsHitTesting(false) }
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
            .scaleEffect(reduceMotion || preferenceReduceMotion ? 1 : configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? configuration.isPressed ? 0.8 : 1 : 0.4)
            .animation(reduceMotion || preferenceReduceMotion ? nil : InterfaceMotion.feedback, value: configuration.isPressed)
            .animation(InterfaceMotion.feedback, value: hovering)
            .onHover { hovering = $0 }
    }
}

struct IslandBackdrop: View {
    var compact: Bool
    var stripHeight: CGFloat
    var glassEnabled = false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.islandPreview) private var preview
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if compact { Color.black }
                else if !glassEnabled || opaque {
                    (scheme == .dark ? Color.black : CompanionStyle.background)
                    VStack(spacing: 0) { Color.black.frame(height: stripHeight); Spacer(minLength: 0) }
                }
                else {
                    if preview { Color(white: scheme == .dark ? 0.34 : 0.85) }
                    else { IslandGlassLens() }
                    LinearGradient(stops: Self.stops(height: geometry.size.height, strip: stripHeight, light: scheme == .light), startPoint: .top, endPoint: .bottom)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
    static func stops(height: CGFloat, strip: CGFloat, light: Bool = false) -> [Gradient.Stop] {
        let camera = min(1, max(0, strip / max(1, height)))
        let tint = light ? Color.white : .black
        return [.init(color: .black, location: 0), .init(color: .black, location: camera), .init(color: tint.opacity(0.88), location: min(1, camera + 0.12)), .init(color: tint.opacity(0.52), location: 1)]
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
    @Environment(\.colorScheme) private var scheme
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) }
}

// The native window reserves the whole transition. Only the silhouette moves:
// the content is laid out once at its destination, then fades into the shell.
struct IslandCanvasGeometry: Equatable {
    let size: CGSize
    let cutoutWidth: CGFloat
    let cutoutHeight: CGFloat
    let compact: Bool
    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
}

struct IslandTransitionTiming {
    let duration: Double
    let contentDelay: Double
    let contentDuration: Double
    let arriving: Bool
    let closing: Bool
    init(from: CGSize, to: CGSize, closing: Bool, welcome: Bool = false) {
        self.closing = closing
        arriving = from.height <= 70 && to.height > 70 && !closing
        duration = closing ? 0.24 : arriving ? (welcome ? 0.52 : 0.38) : 0.26
        contentDelay = arriving ? duration * 0.32 : 0
        contentDuration = closing ? 0.12 : arriving ? duration * 0.55 : 0.16
    }
    func progress(at fraction: Double) -> Double {
        let t = min(1, max(0, fraction))
        // No overshoot: text and camera edges keep a stable spatial reference.
        return closing ? t * t * (3 - 2 * t) : 1 - pow(1 - t, 4)
    }
}

// The island is a nonactivating overlay. Its first click must run the action
// even when another application owns keyboard focus.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var focusRingMaskBounds: NSRect { .zero }
    override func drawFocusRingMask() {}
}

@MainActor final class IslandWindowCanvas<Content: View>: NSView {
    private let host: NSHostingView<Content>
    private let backdrop = NSHostingView(rootView: AnyView(IslandBackdrop(compact: true, stripHeight: 0)))
    private let outline = CAShapeLayer()
    private let maskLayer = CAShapeLayer()
    private var surface: CGSize = .zero
    private(set) var backdropIsCompact = true
    private(set) var targetGeometry: IslandCanvasGeometry?
    private(set) var transitionGeneration = 0
    var isAnimating: Bool { completion != nil }
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
        outline.fillColor = nil; outline.strokeColor = nil; outline.lineWidth = 0
        layer?.addSublayer(outline)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var currentSurface: CGSize { Self.visibleSize(path: maskLayer.presentation()?.path, fallback: surface) }
    static func visibleSize(path: CGPath?, fallback: CGSize) -> CGSize {
        guard let path, !path.isEmpty else { return fallback }
        let size = path.boundingBoxOfPath.size
        return size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0 ? size : fallback
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func updateAppearance(compact: Bool, stripHeight: CGFloat, appearance: AppAppearance, glassEnabled: Bool) {
        backdropIsCompact = compact
        backdrop.rootView = AnyView(IslandBackdrop(compact: compact, stripHeight: stripHeight, glassEnabled: glassEnabled).preferredColorScheme(appearance.colorScheme))
    }

    func prepare(target: IslandCanvasGeometry, reserved: CGSize, animated: Bool, closing: Bool, appearance: AppAppearance = .system, glassEnabled: Bool = false, welcome: Bool = false, settled: @escaping @MainActor () -> Void) {
        let compactAppearance = closing ? backdropIsCompact : target.compact
        // A second delivery of the same target keeps the existing presentation
        // layer and completion. It cannot lengthen an animation indefinitely.
        if animated, targetGeometry == target, isDeparting == closing, frame.size == reserved {
            updateAppearance(compact: compactAppearance, stripHeight: target.cutoutHeight, appearance: appearance, glassEnabled: glassEnabled)
            return
        }
        completion?.cancel(); completion = nil
        transitionGeneration += 1
        let generation = transitionGeneration
        let previous = surface == .zero ? CGSize(width: max(180, target.cutoutWidth), height: max(1, target.cutoutHeight)) : currentSurface
        let contentOpacity = host.layer?.presentation()?.opacity ?? Float(host.alphaValue)
        let previousCanvasWidth = bounds.width
        var translation = CGAffineTransform(translationX: (reserved.width - previousCanvasWidth) / 2, y: 0)
        let visiblePath = maskLayer.presentation()?.path?.copy(using: &translation)
        isDeparting = closing; targetGeometry = target; surface = target.size
        let timing = IslandTransitionTiming(from: previous, to: target.size, closing: closing, welcome: welcome)
        let gutter: CGFloat = target.compact ? 0 : 72
        let extra: CGFloat = target.compact ? 0 : 64
        let endPath = Self.path(size: target.size, canvasWidth: reserved.width)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        setFrameSize(reserved)
        backdrop.frame = bounds
        host.frame = CGRect(x: (reserved.width - target.width - gutter * 2) / 2, y: 0, width: target.width + gutter * 2, height: target.height + extra)
        maskLayer.frame = bounds; outline.frame = bounds
        maskLayer.path = endPath; outline.path = endPath
        outline.isHidden = target.compact || closing
        maskLayer.removeAllAnimations(); outline.removeAllAnimations(); host.layer?.removeAllAnimations()
        host.alphaValue = closing ? 0 : 1
        CATransaction.commit()
        updateAppearance(compact: compactAppearance, stripHeight: target.cutoutHeight, appearance: appearance, glassEnabled: glassEnabled)
        guard animated, previous != target.size else { settled(); return }
        let animation = CAKeyframeAnimation(keyPath: "path")
        // Sample the contour itself so corner radii stay circular while resizing.
        animation.values = (0...60).map { index -> CGPath in
            if index == 0, let visiblePath { return visiblePath }
            let eased = timing.progress(at: Double(index) / 60)
            let size = CGSize(width: previous.width + (target.width - previous.width) * eased, height: previous.height + (target.height - previous.height) * eased)
            return Self.path(size: size, canvasWidth: reserved.width)
        }
        animation.duration = timing.duration; animation.calculationMode = .linear
        maskLayer.add(animation, forKey: "island.contour"); outline.add(animation, forKey: "island.contour")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = timing.arriving ? 0 : contentOpacity; fade.toValue = closing ? 0 : 1
        fade.beginTime = CACurrentMediaTime() + timing.contentDelay
        fade.fillMode = .backwards; fade.duration = timing.contentDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        host.layer?.add(fade, forKey: "island.content")
        if timing.arriving {
            let arrival = CABasicAnimation(keyPath: "transform.translation.y")
            arrival.fromValue = -6; arrival.toValue = 0
            arrival.beginTime = fade.beginTime; arrival.duration = timing.contentDuration
            arrival.fillMode = .backwards; arrival.timingFunction = CAMediaTimingFunction(name: .easeOut)
            host.layer?.add(arrival, forKey: "island.arrival")
        }
        completion = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timing.duration))
            guard !Task.isCancelled, let self, self.transitionGeneration == generation else { return }
            self.completion = nil
            settled()
        }
    }

    static func path(size: CGSize, canvasWidth: CGFloat) -> CGPath {
        NotchPanelShape().path(in: CGRect(x: (canvasWidth - size.width) / 2, y: 0, width: size.width, height: size.height)).cgPath
    }
}
