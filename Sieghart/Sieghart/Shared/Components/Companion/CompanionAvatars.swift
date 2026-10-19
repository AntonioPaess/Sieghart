import AppKit
import SwiftUI

// Sig coordinates the fixed team. These identities are never principal choices.
enum CompanionAvatar: String, CaseIterable, Identifiable, Sendable {
    case sig, rita, ada, gantt, elinor, toni
    var id: String { rawValue }
    static var specialists: [Self] { allCases.filter { $0 != .sig } }
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var subtitle: String {
        switch self {
        case .sig: "Your main companion"
        case .rita: "Health & breaks"
        case .ada: "Code & GitHub"
        case .gantt: "Calendar & routine"
        case .elinor: "Finances & resources"
        case .toni: "Communication & files"
        }
    }
    var detail: String {
        switch self {
        case .sig: "I keep your tools and your team together."
        case .rita: "A gentler rhythm, with time to rest and breathe."
        case .ada: "A curious mind for code and the next step."
        case .gantt: "One commitment at a time, with room for your day."
        case .elinor: "A clearer view of spending and resources."
        case .toni: "From a thought to a message, with care."
        }
    }
    var tint: Color {
        switch self {
        case .sig: Color(red: 0.60, green: 0.82, blue: 0.62)
        case .rita: Color(red: 0.63, green: 0.77, blue: 0.57)
        case .ada: Color(red: 1, green: 0.76, blue: 0.34)
        case .gantt: Color(red: 0.69, green: 0.64, blue: 0.87)
        case .elinor: Color(red: 0.98, green: 0.83, blue: 0.71)
        case .toni: Color(red: 1, green: 0.94, blue: 0.83)
        }
    }
}

// The approved minimal family is drawn natively. Expressions interpolate on
// the same paths instead of swapping static reaction frames.
enum CompanionMood: Equatable {
    case idle, happy, annoyed, asleep, waking, startled, understood, celebrating
}

struct CompanionMotion: Equatable {
    var eyeOpen: CGFloat = 1
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation: Double = 0
    var offset = CGSize.zero

    static func sample(time: Double, size: CGFloat, avatar: CompanionAvatar, mood: CompanionMood, listening: Bool, strolling: Bool, animates: Bool) -> Self {
        guard animates else {
            return Self(eyeOpen: mood == .asleep ? 0.07 : 1, rotation: mood == .asleep ? 4 : 0)
        }
        let index = Double(CompanionAvatar.allCases.firstIndex(of: avatar) ?? 0)
        let t = time * (avatar == .rita ? 0.8 : 1) + index * 0.61
        var result = Self()
        let blinkPhase = t.truncatingRemainder(dividingBy: 4.7)
        // Cosine starts and lands with zero velocity at both ends of a blink.
        if blinkPhase >= 0 && blinkPhase < 0.28 {
            result.eyeOpen = 1 - (1 - cos(blinkPhase / 0.28 * .pi * 2)) * 0.48
        }
        let breath = sin(t * (mood == .asleep ? 1.3 : 1.8)) * 0.012
        result.scaleX = 1 + breath
        result.scaleY = 1 + breath
        result.rotation = sin(t * 0.9) * 0.7
        result.offset.height = sin(t * 1.8) * size * (avatar == .elinor ? 0.009 : 0.018)
        if listening {
            let pulse = sin(t * 3) * 0.025
            result.scaleX += pulse; result.scaleY -= pulse * 0.5
        }
        switch mood {
        case .happy, .celebrating:
            let lift = (1 - cos(t * 5)) * 0.5
            result.offset.height = -lift * size * (mood == .celebrating ? 0.06 : 0.04)
            result.scaleX += lift * 0.02; result.scaleY -= lift * 0.025
            result.rotation = sin(t * 5) * 2
        case .annoyed:
            result.offset.width = sin(t * 13) * size * 0.012
            result.rotation = sin(t * 8) * 1.5
        case .asleep:
            let inhale = (1 - cos(t * 1.45)) * 0.5
            result.eyeOpen = 0.07
            result.scaleX = 1 + inhale * 0.025
            result.scaleY = 0.94 + inhale * 0.055
            result.rotation = 4 + sin(t * 0.72) * 1.2
            result.offset.height = size * (0.025 - inhale * 0.014)
        case .waking:
            result.scaleY += 0.04
        case .understood:
            result.offset.height += (1 - cos(t * 4)) * size * 0.012
        case .startled:
            result.scaleY += 0.025
        case .idle:
            if strolling {
                result.offset.height -= (1 - cos(t * 5)) * size * 0.012
                result.rotation = sin(t * 5) * 1.5
            }
        }
        return result
    }
}

// Voice and other verified task lifecycles use the same expressive language.
enum CompanionVoicePhase: Equatable { case inactive, preparing, listening, thinking, working, success, failure }

enum CompanionActivity {
    static func phase(voice: CompanionVoicePhase, isLoading: Bool = false, hasActiveTask: Bool = false) -> CompanionVoicePhase {
        if voice != .inactive { return voice }
        if hasActiveTask { return .working }
        return isLoading ? .thinking : .inactive
    }
}

extension CompanionAvatar {
    var processingTint: Color {
        switch self {
        case .gantt: Color(red: 0.76, green: 0.65, blue: 0.97)
        case .ada: Color(red: 1, green: 0.78, blue: 0.35)
        case .elinor: Color(red: 0.75, green: 0.72, blue: 0.90)
        case .rita: Color(red: 0.46, green: 0.72, blue: 0.61)
        case .toni: Color(red: 1, green: 0.63, blue: 0.52)
        case .sig: Color(red: 0.55, green: 0.62, blue: 0.61)
        }
    }
}

struct CompanionVoicePose: Equatable {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation = 0.0
    var offset = CGSize.zero
    var gaze = CGSize.zero
    var loading: CGFloat = 0
    var eyeMultiplier: CGFloat = 1
    var joy: CGFloat = 0
    var wink: CGFloat = 0

    func blended(to target: Self, progress: Double) -> Self {
        let p = CGFloat(min(1, max(0, progress)))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        return Self(scaleX: mix(scaleX, target.scaleX), scaleY: mix(scaleY, target.scaleY),
                    rotation: rotation + (target.rotation - rotation) * Double(p),
                    offset: CGSize(width: mix(offset.width, target.offset.width), height: mix(offset.height, target.offset.height)),
                    gaze: CGSize(width: mix(gaze.width, target.gaze.width), height: mix(gaze.height, target.gaze.height)),
                    loading: mix(loading, target.loading), eyeMultiplier: mix(eyeMultiplier, target.eyeMultiplier),
                    joy: mix(joy, target.joy), wink: mix(wink, target.wink))
    }
}

enum CompanionVoiceMotion {
    static func sample(phase: CompanionVoicePhase, elapsed: Double, size: CGFloat, avatar: CompanionAvatar = .sig, animates: Bool) -> CompanionVoicePose {
        let t = max(0, elapsed)
        var pose = CompanionVoicePose()
        pose.loading = phase == .preparing || phase == .thinking || phase == .working ? 1 : 0
        if !animates {
            pose.joy = phase == .success ? 0.8 : 0
            return pose
        }
        let w = Double.pi * 2 / 4
        let breath = sin(t * w) * 0.014
        if phase != .inactive {
            pose.scaleX = 1 + breath * 0.5; pose.scaleY = 1 + breath
            pose.offset.height = -sin(t * w) * size * (0.8 / 112)
        }
        switch phase {
        case .inactive: break
        case .preparing:
            pose.rotation = avatar == .ada ? 0 : -2
            pose.eyeMultiplier = 1.03
        case .listening:
            pose.rotation = avatar == .ada ? 0 : -2.5 + sin(t * w) * 1.6
            pose.gaze = CGSize(width: sin(t * w) * 0.9, height: -0.4)
            pose.eyeMultiplier = avatar == .rita ? 1 : 1.06
            if avatar == .rita { pose.joy = 0.12 }
        case .thinking, .working:
            pose.rotation = avatar == .ada ? 0 : sin(t * w) * (avatar == .rita ? 1.6 : 2.4)
            pose.gaze = CGSize(width: sin(t * w) * 2.8, height: -1.7)
            pose.eyeMultiplier = 0.90; pose.offset.height *= 1.8
            if avatar == .rita { pose.joy = 0.18 }
        case .success:
            // Play once per successful lifecycle transition, then hold a calm
            // face until the result is dismissed. No full turn or looping jump.
            pose.scaleX = 1; pose.scaleY = 1; pose.offset = .zero
            let p = min(1, t / 1.05), bump = sin(p * .pi), nod = sin(p * .pi * 2) * (1 - p)
            pose.joy = min(1, max(0, sin(p * .pi * 0.7)))
            switch avatar {
            case .gantt:
                pose.scaleX = 1 + bump * 0.035; pose.scaleY = 1 - bump * 0.025
                pose.rotation = nod * 4; pose.offset.height = -bump * size * (2 / 112.0)
            case .ada:
                pose.offset.height = -bump * size * (4 / 112.0)
                pose.scaleX = 1 + bump * 0.025; pose.scaleY = 1 - bump * 0.025
            case .elinor:
                pose.rotation = nod * 4; pose.offset.height = -bump * size * (1.5 / 112.0)
            case .rita:
                pose.rotation = nod * 5; pose.offset.height = bump * size * (2 / 112.0)
                pose.gaze.width = bump * 0.7; pose.joy = bump * 0.35; pose.wink = bump * 0.92
            case .toni:
                pose.rotation = sin(p * .pi * 3) * (1 - p) * 5
                pose.scaleX = 1 + bump * 0.018; pose.offset.height = -bump * size * (2.5 / 112.0)
            case .sig:
                pose.scaleX = 1 + bump * 0.045; pose.scaleY = 1 - bump * 0.05
                pose.rotation = nod * 3; pose.wink = bump * 0.92; pose.joy = bump * 0.45
            }
        case .failure:
            pose.rotation = sin(t * 18) * 4 * max(0, 1 - t)
            pose.eyeMultiplier = 0.88
        }
        return pose
    }
}

// Phase interruptions blend from every visible parameter, including the
// loading badge, relaxed eyes and wink. Repeated refresh events in the same
// phase do not restart the gesture.
struct CompanionVoiceAnimator {
    private(set) var phase: CompanionVoicePhase = .inactive
    private var started = 0.0
    private var source = CompanionVoicePose()
    func sample(at time: Double, size: CGFloat, avatar: CompanionAvatar = .sig, animates: Bool) -> CompanionVoicePose {
        let elapsed = max(0, time - started)
        let target = CompanionVoiceMotion.sample(phase: phase, elapsed: elapsed, size: size, avatar: avatar, animates: animates)
        guard animates else { return target }
        let p = min(1, elapsed / 0.22)
        return source.blended(to: target, progress: p * p * (3 - 2 * p))
    }
    mutating func transition(to next: CompanionVoicePhase, at time: Double, size: CGFloat, avatar: CompanionAvatar = .sig, animates: Bool) {
        guard phase != next else { return }
        source = sample(at: time, size: size, avatar: avatar, animates: animates)
        started = time; phase = next
    }
}

struct CompanionLoadingShape: Shape {
    var avatar: CompanionAvatar
    func path(in rect: CGRect) -> Path {
        switch avatar {
        case .gantt: return Path(roundedRect: rect, cornerRadius: rect.width * 0.24)
        case .ada:
            let points: [(CGFloat,CGFloat)] = [(0.25,0),(0.75,0),(0.75,0.125),(0.875,0.125),(0.875,0.25),(1,0.25),(1,0.75),(0.875,0.75),(0.875,0.875),(0.75,0.875),(0.75,1),(0.25,1),(0.25,0.875),(0.125,0.875),(0.125,0.75),(0,0.75),(0,0.25),(0.125,0.25),(0.125,0.125),(0.25,0.125)]
            var p = Path()
            for (n, point) in points.enumerated() {
                let v = CGPoint(x: rect.minX + rect.width * point.0, y: rect.minY + rect.height * point.1)
                if n == 0 { p.move(to: v) } else { p.addLine(to: v) }
            }
            p.closeSubpath(); return p
        case .toni:
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath(); return p
        case .sig: return Path(roundedRect: rect.insetBy(dx: 0, dy: rect.height * 0.12), cornerRadius: rect.width * 0.38)
        case .rita: return Path(roundedRect: rect, cornerRadius: rect.width * 0.32)
        case .elinor: return Path(ellipseIn: rect)
        }
    }
}

struct CompanionFace: View {
    var renderSize: CGFloat = 42
    var avatar: CompanionAvatar = .sig
    var blinking = false, focusing = false, joyful = false
    var gaze = CGSize.zero
    var eyeOpen: CGFloat? = nil
    var listening = false, motionTime: Double = 0
    var mood: CompanionMood = .idle
    var animates = false
    var joyAmount: CGFloat? = nil
    var wink: CGFloat = 0
    var body: some View {
        CompanionCharacter(size: renderSize, avatar: avatar, animates: animates, focusing: focusing,
                           joyful: joyful, listening: listening, gaze: gaze, mood: mood)
    }
}

@MainActor enum CompanionArtwork {
    private static var portraits: [String: NSImage] = [:]
    private static var displayRasters = makeDisplayRasterCache()
    private static func makeDisplayRasterCache() -> NSCache<NSString, DisplayRaster> {
        let cache = NSCache<NSString, DisplayRaster>()
        cache.countLimit = 48; cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }
    private final class DisplayRaster {
        let source: CGImage, image: CGImage
        init(source: CGImage, image: CGImage) { self.source = source; self.image = image }
    }
    static func portrait(for avatar: CompanionAvatar, animation: CompanionAnimation = .idle) -> NSImage {
        let key = "\(avatar.rawValue)-\(animation.rawValue)"
        if let image = portraits[key] { return image }
        let image: NSImage
        if animation == .idle, let bundled = NSImage(named: "Companion-\(avatar.rawValue)") { image = bundled }
        else {
            image = CompanionScene.snapshot(avatar: avatar, animation: animation, time: animation == .sleeping ? 1 : 0, size: CGSize(width: 1024, height: 1024))
            image.size = CGSize(width: 512, height: 512)
        }
        portraits[key] = image
        return image
    }
    static func fullResolutionPixels(in image: NSImage) -> CGImage? {
        // NSImage's logical point size must not rasterize a Retina portrait
        // into a smaller bitmap before Core Animation displays it.
        let width = max(image.size.width * 2, CGFloat(image.representations.map(\.pixelsWide).max() ?? 0))
        let height = max(image.size.height * 2, CGFloat(image.representations.map(\.pixelsHigh).max() ?? 0))
        var pixels = CGRect(x: 0, y: 0, width: width, height: height)
        // Catalog-backed NSImages load representations lazily. Request pixels
        // explicitly, with an identity CTM, so a nil drawing context cannot
        // select the 1× version before the image reaches its Retina layer.
        return image.cgImage(forProposedRect: &pixels, context: nil,
                             hints: [.ctm: NSAffineTransform(), .interpolation: NSImageInterpolation.high.rawValue])
    }
    static func displayPixels(from source: CGImage, width: Int, height: Int) -> CGImage {
        let w = max(1, width), h = max(1, height)
        if w >= source.width && h >= source.height { return source }
        let key = "\(ObjectIdentifier(source))-\(w)x\(h)" as NSString
        if let cached = displayRasters.object(forKey: key) { return cached.image }
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        // Downsample once at the display's real pixel size. The transparent
        // raster then needs only bilinear composition, not blurred mip levels.
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = context.makeImage() else { return source }
        // Count the retained source too; tiny output rasters must not keep
        // dozens of large source buffers outside the cache's memory budget.
        let cost = source.bytesPerRow * source.height + image.bytesPerRow * image.height
        displayRasters.setObject(DisplayRaster(source: source, image: image), forKey: key, cost: cost)
        return image
    }
    private static var menuImages: [CompanionAvatar: NSImage] = [:]
    /// Runs a synchronous artwork operation with a fresh cache, then restores
    /// its caller's portraits, display rasters, menu images and image names.
    /// Main-actor isolation prevents another operation from seeing this scope.
    static func withIsolatedCaches<T>(_ operation: () throws -> T) rethrows -> T {
        let savedPortraits = portraits, savedMenuImages = menuImages, savedRasters = displayRasters
        let names = CompanionAvatar.allCases.map { NSImage.Name("Companion-\($0.rawValue)") }
        let savedNamedImages = names.map { ($0, NSImage(named: $0)) }
        savedNamedImages.forEach { $0.1?.setName(nil) }
        portraits = [:]; menuImages = [:]; displayRasters = makeDisplayRasterCache()
        defer {
            names.forEach { NSImage(named: $0)?.setName(nil) }
            savedNamedImages.forEach { name, image in image?.setName(name) }
            portraits = savedPortraits; menuImages = savedMenuImages; displayRasters = savedRasters
        }
        return try operation()
    }
    static func menuBarImage(for avatar: CompanionAvatar) -> NSImage? {
        if let image = menuImages[avatar] { return image }
        let image = portrait(for: avatar).copy() as! NSImage
        image.size = NSSize(width: 22, height: 22); image.isTemplate = false
        menuImages[avatar] = image
        return image
    }
}

struct CompanionCharacter: View {
    var size: CGFloat = 42
    var avatar: CompanionAvatar = .sig
    var animates = true, focusing = false, joyful = false, listening = false
    var voicePhase: CompanionVoicePhase = .inactive
    var gaze = CGSize.zero
    var mood: CompanionMood = .idle
    var strolling = false
    var previewTime: Double? = nil
    var entrance: CompanionEntranceMotion? = nil
    var animation: CompanionAnimation? = nil
    var replay = 0
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.islandReduceMotion) private var preferenceReducedMotion
    @Environment(\.islandPreview) private var staticPreview
    @Environment(\.companionMotionEnabled) private var preferenceMotion
    var body: some View {
        let moves = animates && preferenceMotion && !reducedMotion && !preferenceReducedMotion
        let resolved = animation ?? CompanionAnimation.resolve(voice: voicePhase, mood: joyful ? .happy : mood,
                                                            listening: listening, strolling: strolling)
        let motion = resolved == .idle && gaze != .zero && moves ? CompanionAnimation.cursor : resolved
        Group {
            if staticPreview, let pixels = CompanionArtwork.fullResolutionPixels(in: CompanionArtwork.portrait(for: avatar, animation: motion)) {
                // ImageRenderer cannot capture NSViewRepresentable. Previews
                // use the same artwork rather than a missing-view placeholder.
                Image(decorative: pixels, scale: 2).resizable().interpolation(.high)
            } else if !moves || (motion == .idle && previewTime == nil) {
                // Cached Retina portraits retain native lighting/depth. Core Animation
                // breathes the composited image; no SceneKit render loop is retained.
                CompanionPortrait(image: CompanionArtwork.portrait(for: avatar, animation: motion), animates: moves)
            } else {
                CompanionScene(avatar: avatar, animation: motion, time: previewTime ?? Date.timeIntervalSinceReferenceDate,
                               animates: moves, gaze: gaze == .zero ? nil : gaze, replay: replay, preview: previewTime != nil)
                    .id(avatar)
            }
        }.frame(width: size, height: size).allowsHitTesting(false).accessibilityHidden(true)
    }
}

// Idle movement is composited by Core Animation. No SwiftUI display-tick
// invalidation, SceneKit scene, or recurrent main-thread layout is involved.
struct CompanionPortrait: NSViewRepresentable {
    var image: NSImage
    var animates: Bool
    func makeNSView(context: Context) -> CompanionPortraitView { CompanionPortraitView() }
    func updateNSView(_ view: CompanionPortraitView, context: Context) { view.configure(image: image, animates: animates) }
    static func dismantleNSView(_ view: CompanionPortraitView, coordinator: ()) { view.stop() }
}
final class CompanionPortraitView: NSView {
    private let portrait = CALayer()
    private var sourcePixels: CGImage?
    private var rasterSize = CGSize.zero
    private var imageIdentity: ObjectIdentifier?
    private var animationEnabled = false
    private var visibilityObservers: [NSObjectProtocol] = []
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
    override var isHidden: Bool { didSet { refresh() } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        portrait.contentsGravity = .resizeAspect
        // Rasterize at the final backing size, then composite without another
        // mip-map blur. This keeps small eyes/accessories legible.
        portrait.minificationFilter = .linear; portrait.magnificationFilter = .linear
        layer?.addSublayer(portrait)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(image: NSImage, animates: Bool) {
        if imageIdentity != ObjectIdentifier(image) {
            imageIdentity = ObjectIdentifier(image)
            sourcePixels = CompanionArtwork.fullResolutionPixels(in: image)
            rasterSize = .zero
        }
        // Ancestor widget scaling can change the backing size while keeping
        // this view's logical bounds. Recheck on SwiftUI configuration too.
        needsLayout = true
        animationEnabled = animates; refresh()
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        portrait.frame = bounds
        let backingScale = window?.backingScaleFactor ?? 2
        let windowWidth = window == nil ? bounds.width : convert(bounds, to: nil).width
        let scale = backingScale * (bounds.width > 0 ? abs(windowWidth / bounds.width) : 1)
        portrait.contentsScale = scale
        let pixels = CGSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale))
        if let sourcePixels, pixels != rasterSize, pixels.width > 0 && pixels.height > 0 {
            portrait.contents = CompanionArtwork.displayPixels(from: sourcePixels, width: Int(pixels.width), height: Int(pixels.height))
            rasterSize = pixels
        }
        CATransaction.commit(); refresh()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
        visibilityObservers.forEach { NotificationCenter.default.removeObserver($0) }
        visibilityObservers.removeAll()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                visibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refresh() }
                })
            }
        }
        refresh()
    }
    private func refresh() {
        let plays = animationEnabled && window?.isVisible == true && window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
        if plays && portrait.animation(forKey: "breath") == nil {
            let breath = CABasicAnimation(keyPath: "transform.scale.y")
            breath.fromValue = 1; breath.toValue = 1.018; breath.duration = 1.8
            breath.autoreverses = true; breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            portrait.add(breath, forKey: "breath")
        } else if !plays { portrait.removeAnimation(forKey: "breath") }
    }
    func stop() {
        animationEnabled = false; portrait.removeAllAnimations()
        visibilityObservers.forEach { NotificationCenter.default.removeObserver($0) }
        visibilityObservers.removeAll()
    }
}

@MainActor
final class CompanionReactions: ObservableObject {
    @Published private(set) var mood: CompanionMood = .idle
    private var touchCount = 0
    private var lastTouch: Date?
    private var recovery: Task<Void, Never>?
    private let now: () -> Date
    private let recoveryDelay: Duration
    private let wakeDelay: Duration

    init(now: @escaping () -> Date = Date.init, recoveryDelay: Duration = .seconds(2), wakeDelay: Duration = .milliseconds(1100)) {
        self.now = now; self.recoveryDelay = recoveryDelay; self.wakeDelay = wakeDelay
    }

    func touch() {
        recovery?.cancel()
        if mood == .asleep {
            touchCount = 0; lastTouch = nil
            mood = .waking
            recover(after: wakeDelay)
            return
        }
        let instant = now()
        if lastTouch == nil || instant.timeIntervalSince(lastTouch!) > 3 { touchCount = 0 }
        lastTouch = instant
        touchCount += 1
        switch touchCount {
        case 1...3: mood = .happy; recover(after: recoveryDelay)
        case 4: mood = .annoyed; recover(after: recoveryDelay)
        default: mood = .asleep
        }
    }

    func reset() {
        recovery?.cancel(); recovery = nil
        touchCount = 0; lastTouch = nil; mood = .idle
    }
    func utility(_ success: Bool) {
        recovery?.cancel(); touchCount = 0; lastTouch = nil
        mood = success ? .understood : .startled
        recover(after: recoveryDelay)
    }

    private func recover(after delay: Duration) {
        recovery = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.mood = .idle
        }
    }
}
