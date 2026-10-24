import AppKit
import Metal
@preconcurrency import SceneKit
import SwiftUI

// Animation belongs to SceneKit's render thread. SwiftUI sends state changes,
// never display ticks. A detached, hidden or occluded view stops its render loop.
final class CompanionRenderView: SCNView {
    var animationEnabled = false { didSet { refreshPlayback() } }
    private var visibilityObservers: [NSObjectProtocol] = []
    private var lifecycleTimer: Timer?
    private var lifecycleID = UUID()
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var focusRingMaskBounds: NSRect { .zero }
    override func drawFocusRingMask() {}
    override func layout() { super.layout(); refreshTransparency() }
    override var isHidden: Bool { didSet { refreshPlayback() } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.allowsGroupOpacity = false
        refreshTransparency()
        stopObservingLifecycle()
        let lifecycleID = self.lifecycleID
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                visibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    let closing = note.name == NSWindow.willCloseNotification
                    Task { @MainActor [weak self] in
                        guard let self, self.lifecycleID == lifecycleID else { return }
                        if closing { self.animationEnabled = false }
                        else { self.refreshPlayback() }
                    }
                })
            }
        }
        // AppKit does not notify descendants when an ancestor is hidden.
        // A cheap 2Hz visibility check prevents an attached but parked scene
        // from continuing to render after its panel leaves the screen.
        if window != nil {
            lifecycleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.lifecycleID == lifecycleID else { return }
                    self.refreshPlayback()
                }
            }
        }
        refreshPlayback()
    }
    func refreshPlayback() {
        refreshTransparency()
        let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
        let playing = animationEnabled && visible && !isHiddenOrHasHiddenAncestor
        if isPlaying != playing { isPlaying = playing }
        if rendersContinuously != playing { rendersContinuously = playing }
    }
    private func refreshTransparency() {
        // SceneKit can add a Metal backing layer after the host view attaches.
        // Its own opaque flag must also allow the weather surface through.
        func configure(_ target: CALayer) {
            target.isOpaque = false
            target.backgroundColor = NSColor.clear.cgColor
            for child in target.sublayers ?? [] { configure(child) }
        }
        if let layer { configure(layer) }
    }
    func stopRendering() {
        animationEnabled = false
        stopObservingLifecycle()
        delegate = nil; scene = nil
    }
    private func stopObservingLifecycle() {
        // Ignore callbacks already queued for a detached window or stopped view.
        lifecycleID = UUID()
        lifecycleTimer?.invalidate(); lifecycleTimer = nil
        visibilityObservers.forEach { NotificationCenter.default.removeObserver($0) }
        visibilityObservers.removeAll()
    }
    isolated deinit { stopObservingLifecycle() }
}

@MainActor enum CompanionSceneLighting {
    static func configure(_ scene: SCNScene, scale: Double = 55) -> SCNNode {
        scene.background.contents = NSColor.clear
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light?.type = .ambient; ambient.light?.intensity = 260
        ambient.light?.color = rigRgb(1, 0.99, 0.97); scene.rootNode.addChildNode(ambient)
        for (x, y, z, intensity, color) in [(-500.0, 700.0, 650.0, 650.0, rigRgb(1, 0.985, 0.95)),
                                            (400, -80, 700, 190, rigRgb(0.93, 0.96, 1))] {
            let node = SCNNode(); node.light = SCNLight(); node.light?.type = .directional
            node.light?.intensity = intensity; node.light?.color = color
            node.position = SCNVector3(x, y, z); node.look(at: SCNVector3(0, 0, 0)); scene.rootNode.addChildNode(node)
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = scale
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 2000
        camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
        camera.position = SCNVector3(0, 0, 850); scene.rootNode.addChildNode(camera)
        return camera
    }
    static func configure(_ view: SCNView, scene: SCNScene, camera: SCNNode) {
        view.wantsLayer = true
        view.scene = scene; view.pointOfView = camera; view.backgroundColor = .clear
        view.autoenablesDefaultLighting = false; view.allowsCameraControl = false
        view.antialiasingMode = .multisampling2X; view.preferredFramesPerSecond = 60
        view.isJitteringEnabled = false; view.isPlaying = false; view.rendersContinuously = false
        view.focusRingType = .none
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.allowsGroupOpacity = false
    }
}

struct CompanionRenderInput: Sendable {
    var animation: CompanionAnimation
    var time: Double
    var animates: Bool
    var gaze: CGSize?
    var replay: Int
    var preview: Bool
}

struct CompanionScene: NSViewRepresentable {
    var avatar: CompanionAvatar
    var animation: CompanionAnimation
    var time: Double
    var animates: Bool
    var gaze: CGSize?
    var replay: Int
    var preview = false
    private var input: CompanionRenderInput {
        CompanionRenderInput(animation: animation, time: time, animates: animates, gaze: gaze, replay: replay, preview: preview)
    }

    // The lock protects only the small input mailbox. Rig/pose ownership transfers
    // to the renderer at attachment and returns after detachment; no main-thread
    // mutation or synchronous dispatch is performed while it is rendering.
    final class Coordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
        let scene = SCNScene()
        let camera: SCNNode
        let actor: CompanionRigActor
        let avatar: CompanionAvatar
        private(set) var renderedFrameCount = 0
        private(set) var renderedOffMain = true
        private let inputLock = NSLock()
        private var pending: CompanionRenderInput?
        private var completed: (CompanionAnimation, Int)?
        private var animation: CompanionAnimation?
        private var replay = -1
        private var started = 0.0
        private var transitionSource: CompanionRigPose?
        private var pauseSent = false
        @MainActor weak var renderView: CompanionRenderView?
        @MainActor init(_ avatar: CompanionAvatar) {
            self.avatar = avatar
            actor = CompanionRigActor(avatar, CompanionAvatar.allCases.firstIndex(of: avatar) ?? 0)
            camera = CompanionSceneLighting.configure(scene)
            super.init()
            let bounds = actor.bounds, scale = 80 / max(bounds.width, bounds.height)
            actor.model.root.scale = SCNVector3(scale, scale, scale)
            actor.model.root.position = SCNVector3(-bounds.midX * scale, -bounds.midY * scale, 0)
            scene.rootNode.addChildNode(actor.model.root)
        }
        @MainActor func configure(_ value: CompanionScene) {
            inputLock.lock()
            if pending?.animation != value.animation || pending?.replay != value.replay { completed = nil }
            pending = value.input; inputLock.unlock()
        }
        private func readInput() -> CompanionRenderInput? {
            inputLock.lock(); defer { inputLock.unlock() }; return pending
        }
        func shouldPlay(_ value: CompanionRenderInput) -> Bool {
            inputLock.lock(); defer { inputLock.unlock() }
            return value.animates && !value.preview && !(completed?.0 == value.animation && completed?.1 == value.replay)
        }
        // Used only before attachment, in deterministic tests and offscreen exports.
        @MainActor func update(_ value: CompanionScene) { advance(value.input, at: value.time) }
        func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            renderedFrameCount += 1; renderedOffMain = renderedOffMain && !Thread.isMainThread
            inputLock.lock(); let input = pending; inputLock.unlock()
            guard let input, input.animates, !input.preview else { return }
            let now = Date.timeIntervalSinceReferenceDate
            advance(input, at: now)
            if !input.animation.continuous && now - started >= input.animation.duration + 0.22 && !pauseSent {
                pauseSent = true
                inputLock.lock(); completed = (input.animation, input.replay); inputLock.unlock()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let current = self.readInput()
                    guard current?.animation == input.animation, current?.replay == input.replay else { return }
                    self.renderView?.animationEnabled = false
                }
            }
        }
        private func advance(_ value: CompanionRenderInput, at time: Double) {
            if animation != value.animation || replay != value.replay {
                transitionSource = animation == nil ? nil : actor.lastPose
                animation = value.animation; replay = value.replay; started = time; pauseSent = false
            }
            let elapsed = value.preview ? max(0, value.time) : max(0, time - started)
            let current = !value.animation.continuous && !value.animation.holdsFinalPose && elapsed >= value.animation.duration ? CompanionAnimation.idle : value.animation
            let blend = value.animates ? rigSmooth(min(1, elapsed / 0.22)) : 1
            actor.update(id: current.rawValue, t: value.animates ? elapsed : 0, duration: current.duration,
                         global: value.animates ? time : 0, continuous: current.continuous,
                         gaze: value.gaze, source: transitionSource, transition: blend, animates: value.animates)
            if blend == 1 { transitionSource = nil }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(avatar) }
    func makeNSView(context: Context) -> CompanionRenderView {
        let view = CompanionRenderView(frame: .zero)
        context.coordinator.update(self); context.coordinator.configure(self)
        CompanionSceneLighting.configure(view, scene: context.coordinator.scene, camera: context.coordinator.camera)
        context.coordinator.renderView = view
        view.delegate = context.coordinator
        view.animationEnabled = context.coordinator.shouldPlay(input)
        return view
    }
    func updateNSView(_ view: CompanionRenderView, context: Context) {
        context.coordinator.configure(self)
        view.animationEnabled = context.coordinator.shouldPlay(input)
    }
    static func dismantleNSView(_ view: CompanionRenderView, coordinator: Coordinator) { view.stopRendering() }
    @MainActor static func snapshot(avatar: CompanionAvatar, animation: CompanionAnimation = .idle,
                                    time: Double = 0, size: CGSize) -> NSImage {
        let coordinator = Coordinator(avatar)
        coordinator.update(Self(avatar: avatar, animation: animation, time: time, animates: true, gaze: nil, replay: 0, preview: true))
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = coordinator.scene; renderer.pointOfView = coordinator.camera; renderer.autoenablesDefaultLighting = false
        return renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
    }
}
