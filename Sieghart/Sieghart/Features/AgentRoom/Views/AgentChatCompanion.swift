import AppKit
import QuartzCore
import SwiftUI

// Ada shares Coucou's state-driven chat behavior, using our cached artwork.
// Only these few composited layers move. No SceneKit renderer, display link or
// SwiftUI frame clock is retained while a chat is open.
struct AgentChatCompanion: View {
    var state: CodingAgentState
    var sending = false
    var active = true
    var size: CGFloat = 70
    var conversationID = ""
    var failureID: UUID? = nil
    var submissionID: UUID? = nil
    @Environment(\.islandPreview) private var preview
    @Environment(\.islandReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.companionMotionEnabled) private var motionEnabled

    var body: some View {
        Group {
            if preview {
                ZStack(alignment: .bottomLeading) {
                    CompanionCharacter(size: size, avatar: .ada, animates: false)
                    if sending || state == .working {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CompanionAvatar.ada.tint)
                            .padding(4).background(Color(white: 0.12), in: Circle())
                    }
                }
            } else {
                AgentChatCompanionSurface(state: state, sending: sending,
                    active: active && motionEnabled && !reduceMotion && !systemReduceMotion,
                    conversationID: conversationID, failureID: failureID, submissionID: submissionID)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct AgentChatCompanionSurface: NSViewRepresentable {
    var state: CodingAgentState
    var sending: Bool
    var active: Bool
    var conversationID: String
    var failureID: UUID?
    var submissionID: UUID?
    func makeNSView(context: Context) -> AgentChatCompanionView { AgentChatCompanionView() }
    func updateNSView(_ view: AgentChatCompanionView, context: Context) {
        view.configure(state: state, sending: sending, active: active, conversationID: conversationID,
                       failureID: failureID, submissionID: submissionID)
    }
    static func dismantleNSView(_ view: AgentChatCompanionView, coordinator: ()) { view.stop() }
}

@MainActor
final class AgentChatCompanionView: NSView {
    private enum Phase { case idle, sending, working, waiting, blocked, completed, failed }
    private let artwork = CALayer()
    private let badge = CALayer()
    private let ring = CAShapeLayer()
    private let mark = CATextLayer()
    private var pixels: CGImage?
    private var rasterSize = CGSize.zero
    private var phase: Phase = .idle
    private var conversationID: String?
    private var failureID: UUID?
    private var submissionID: UUID?
    private var reportedState: CodingAgentState?
    private var reportedSending = false
    private var completionPending = false
    private var failedSendState: CodingAgentState?
    private var active = false
    private var playing = false
    private var idleTimer: Timer?
    private var visibilityObservers: [NSObjectProtocol] = []

    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isHidden: Bool { didSet { refreshVisibility() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        artwork.contentsGravity = .resizeAspect
        artwork.minificationFilter = .linear; artwork.magnificationFilter = .linear
        layer?.addSublayer(artwork)
        pixels = CompanionArtwork.fullResolutionPixels(in: CompanionArtwork.portrait(for: .ada))
        badge.backgroundColor = NSColor(white: 0.12, alpha: 0.96).cgColor
        badge.opacity = 0
        layer?.addSublayer(badge)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor(CompanionAvatar.ada.tint).cgColor
        ring.lineWidth = 1.5; ring.lineCap = .round
        ring.strokeStart = 0; ring.strokeEnd = 0.72
        badge.addSublayer(ring)
        mark.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        mark.fontSize = 10; mark.alignmentMode = .center
        mark.foregroundColor = NSColor(CompanionAvatar.ada.tint).cgColor
        badge.addSublayer(mark)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(state: CodingAgentState, sending: Bool, active: Bool, conversationID: String,
                   failureID: UUID? = nil, submissionID: UUID? = nil) {
        let changedConversation = self.conversationID != conversationID
        let failedSend = !changedConversation && failureID != nil && self.failureID != failureID
        let submitted = !changedConversation && submissionID != nil && self.submissionID != submissionID
        let startedSend = sending && !reportedSending
        let changedRuntimeState = reportedState != state
        let newlyFailedState = !changedConversation && state == .failed && reportedState != state
        // Once the caller supplies submission tokens they own acknowledgement;
        // an intermediate sending=true render cannot replay the same gesture.
        let acknowledgesSend = !changedConversation && (submitted || (startedSend && submissionID == nil))
        // The provider can reject a send while the old session is still marked
        // completed. Keep the failure visible until a new send or a new runtime
        // state arrives; a transcript refresh cannot turn rejection into joy.
        if changedConversation || startedSend || submitted || reportedState != state { failedSendState = nil }
        if failedSend { failedSendState = state }
        if changedConversation || startedSend || submitted { completionPending = false }
        if !changedConversation && changedRuntimeState { completionPending = state == .completed }
        self.failureID = failureID
        self.submissionID = submissionID
        reportedState = state
        reportedSending = sending
        let next: Phase
        if failedSendState != nil { next = .failed }
        else if sending { next = .sending }
        else {
            switch state {
            case .working: next = .working
            case .waiting: next = .waiting
            case .blocked: next = .blocked
            case .completed: next = .completed
            case .failed: next = .failed
            case .unknown, .ready, .interrupted: next = .idle
            }
        }
        self.conversationID = conversationID
        let previous = phase
        let changedPhase = phase != next
        phase = next
        self.active = active
        if changedConversation || changedPhase || failedSend || acknowledgesSend {
            resetMotion(preserveSend: !changedConversation && active && next != .failed && artwork.animation(forKey: "send") != nil)
            configureBadge()
            // Historic completed/failed sessions remain calm when selected.
            // A genuine turn transition receives its one-time reaction.
            if isVisibleForMotion && active {
                // A fast local queue acknowledgement may coalesce the entire
                // sending=true interval. Its token still receives the send
                // gesture, without celebrating an old completed session.
                startMotion(reaction: !changedConversation && (!submitted || failedSend)
                            && (phase != .completed || completionPending), previous: previous)
                if phase == .completed { completionPending = false }
                if acknowledgesSend && !failedSend && failedSendState == nil && !newlyFailedState {
                    addKeyframes("transform.scale.y", values: [1, 0.94, 1.035, 1], duration: 0.48, key: "send")
                }
            }
        }
        needsLayout = true
        refreshVisibility()
    }

    override func layout() {
        super.layout()
        withoutActions {
            artwork.frame = bounds
            let scale = effectiveBackingScale
            artwork.contentsScale = scale
            let size = CGSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale))
            if let pixels, size != rasterSize, size.width > 0, size.height > 0 {
                artwork.contents = CompanionArtwork.displayPixels(from: pixels, width: Int(size.width), height: Int(size.height))
                rasterSize = size
            }
            let diameter = max(14, min(18, bounds.width * 0.25))
            badge.frame = CGRect(x: bounds.minX + bounds.width * 0.10,
                                 y: bounds.minY + bounds.height * 0.09, width: diameter, height: diameter)
            badge.cornerRadius = diameter / 2
            ring.frame = badge.bounds
            ring.path = CGPath(ellipseIn: badge.bounds.insetBy(dx: 4, dy: 4), transform: nil)
            mark.contentsScale = scale
            mark.frame = CGRect(x: 0, y: (diameter - 13) / 2, width: diameter, height: 13)
        }
        refreshVisibility()
    }

    private var effectiveBackingScale: CGFloat {
        let scale = window?.backingScaleFactor ?? 2
        let windowWidth = window == nil ? bounds.width : convert(bounds, to: nil).width
        return scale * (bounds.width > 0 ? abs(windowWidth / bounds.width) : 1)
    }
    private var isVisibleForMotion: Bool {
        window?.isVisible == true && window?.isMiniaturized == false
            && window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsLayout = true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibilityObservers.forEach { NotificationCenter.default.removeObserver($0) }
        visibilityObservers.removeAll()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                visibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    let closing = note.name == NSWindow.willCloseNotification
                    Task { @MainActor [weak self] in
                        if closing { self?.stop() }
                        else { self?.refreshVisibility() }
                    }
                })
            }
        }
        needsLayout = true
        refreshVisibility()
    }
    private func refreshVisibility() {
        let next = active && isVisibleForMotion
        guard next != playing else { return }
        resetMotion()
        if next { startMotion(reaction: false, previous: phase) }
    }
    private func resetMotion(preserveSend: Bool = false) {
        playing = false
        idleTimer?.invalidate(); idleTimer = nil
        for key in artwork.animationKeys() ?? [] where !preserveSend || key != "send" {
            artwork.removeAnimation(forKey: key)
        }
        ring.removeAllAnimations(); badge.removeAllAnimations()
        withoutActions { artwork.transform = CATransform3DIdentity }
    }

    private func configureBadge() {
        withoutActions {
            badge.opacity = phase == .idle ? 0 : 1
            ring.isHidden = phase != .sending && phase != .working
            mark.isHidden = !ring.isHidden
            switch phase {
            case .waiting: mark.string = "?"
            case .blocked, .failed: mark.string = "!"
            case .completed: mark.string = "✓"
            case .sending, .working, .idle: mark.string = ""
            }
            mark.foregroundColor = phase == .blocked || phase == .failed
                ? NSColor.systemOrange.cgColor : NSColor(CompanionAvatar.ada.tint).cgColor
        }
    }
    private func startMotion(reaction: Bool, previous: Phase) {
        playing = true
        switch phase {
        case .sending, .working:
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = Double.pi * 2
            spin.duration = 1.15; spin.repeatCount = .infinity
            ring.add(spin, forKey: "progress")
            addKeyframes("transform.translation.y", values: [0, 1.3, 0, -0.6, 0], duration: 2.8,
                         repeatCount: .infinity, key: "working")
        case .completed:
            if reaction && (previous == .sending || previous == .working || previous == .waiting) {
                addKeyframes("transform.translation.y", values: [0, 4, 0, 1.5, 0], duration: 0.9, key: "complete")
                addKeyframes("transform.rotation.z", values: [0, -0.05, 0.04, 0], duration: 0.9, key: "acknowledge")
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.35
                fade.beginTime = CACurrentMediaTime() + 2
                fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
                badge.add(fade, forKey: "settle")
            }
            scheduleIdle()
        case .failed:
            if reaction {
                addKeyframes("transform.translation.x", values: [0, -2, 2, -1.3, 1.3, 0], duration: 0.5, key: "failure")
            }
            scheduleIdle()
        case .waiting, .blocked:
            if reaction {
                addKeyframes("transform.rotation.z", values: [0, -0.07, 0], duration: 0.75, key: "question")
            }
            scheduleIdle()
        case .idle: scheduleIdle()
        }
    }
    private func scheduleIdle() {
        // One wakeup every 8.5 seconds. Between these brief gestures there are
        // zero changing layers and no ongoing compositor work for Ada.
        let timer = Timer(timeInterval: 8.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshVisibility()
                guard self.playing else { return }
                self.addKeyframes("transform.scale.y", values: [1, 0.975, 1.008, 1], duration: 0.7, key: "idle")
            }
        }
        timer.tolerance = 1.5
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }
    private func addKeyframes(_ path: String, values: [Double], duration: Double,
                              repeatCount: Float = 0, key: String) {
        let animation = CAKeyframeAnimation(keyPath: path)
        animation.values = values
        animation.keyTimes = values.indices.map { NSNumber(value: Double($0) / Double(values.count - 1)) }
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: values.count - 1)
        animation.duration = duration; animation.repeatCount = repeatCount
        artwork.add(animation, forKey: key)
    }
    private func withoutActions(_ work: () -> Void) {
        CATransaction.begin(); CATransaction.setDisableActions(true); work(); CATransaction.commit()
    }
    // Read-only probe for an owned native-view fixture. It does not create a
    // window, start playback, access provider data or retain rendering resources.
    struct MotionDiagnostics: Equatable {
        var animationCount: Int
        var idleTimerScheduled: Bool
        var showingSendFailure: Bool
        var hasSendAcknowledgement = false
    }
    var motionDiagnostics: MotionDiagnostics {
        MotionDiagnostics(animationCount: [artwork, ring, badge].reduce(0) { $0 + ($1.animationKeys()?.count ?? 0) },
                          idleTimerScheduled: idleTimer != nil, showingSendFailure: failedSendState != nil,
                          hasSendAcknowledgement: artwork.animation(forKey: "send") != nil)
    }
    func stop() {
        active = false; resetMotion()
        visibilityObservers.forEach { NotificationCenter.default.removeObserver($0) }
        visibilityObservers.removeAll()
    }
}
