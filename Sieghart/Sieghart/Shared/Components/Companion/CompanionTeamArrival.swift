@preconcurrency import SceneKit
import SwiftUI

// The introduction and the live Companion share point coordinates and sizes.
// The handoff changes content ownership, never the characters' final positions.
struct CompanionHomeLayout: Sendable {
    static let heroSize: CGFloat = 96
    static let heroColumnWidth: CGFloat = 124
    static let introductionTextLift: CGFloat = 10
    static let rowSpacing: CGFloat = 12
    static let dockAvatarSize: CGFloat = 38
    static let dockSpacing: CGFloat = 8
    static let dockHeight: CGFloat = 59
    static let height: CGFloat = heroSize + rowSpacing + dockHeight
    var size: CGSize = CGSize(width: 532, height: height)
    var top: CGFloat { max(0, (size.height - Self.height) / 2) }
    var hero: CGPoint { CGPoint(x: Self.heroColumnWidth / 2, y: top + Self.heroSize / 2) }
    var center: CGPoint { CGPoint(x: size.width / 2, y: top + 70) }
    func dock(_ index: Int) -> CGPoint {
        let item = (size.width - 8 - Self.dockSpacing * 4) / 5
        return CGPoint(x: 4 + item / 2 + CGFloat(index) * (item + Self.dockSpacing),
                       y: top + Self.heroSize + Self.rowSpacing + 4 + Self.dockAvatarSize / 2)
    }
    func scene(_ point: CGPoint) -> SCNVector3 {
        SCNVector3(point.x - size.width / 2, size.height / 2 - point.y, 0)
    }
    static func bodySize(_ viewport: CGFloat) -> Double { Double(viewport) * 80 / 110 }
}

// Keep the approved 640×360 stage as one uniformly scaled coordinate space.
// Its full canvas extends into the unused space above/below the home content;
// shrinking the halo/circle separately changed the approved opening.
struct CompanionOpeningLayout {
    static let referenceSize = CGSize(width: 640, height: 360)
    var home: CompanionHomeLayout
    var scale: Double { Double(home.size.width / Self.referenceSize.width) }
    var center: CGPoint { CGPoint(x: home.size.width / 2, y: home.size.height / 2) }
    static func viewport(for content: CGSize) -> CGSize {
        CGSize(width: content.width, height: max(content.height, ceil(content.width * referenceSize.height / referenceSize.width)))
    }
}

struct CompanionTeamFormation {
    static let assembleTime = CompanionGreetingTiming.end
    static let positionTime = 7.4
    static let dockTime = 10.0
    static let specialistStart = 13.0
    static let returnTime = 28.0
    static let duration = 31.0
    static let boundaries = [4.6, 7.4, 10, 13, 16, 19, 22, 25, 28, 31]
    static func activeMember(at time: Double) -> CompanionAvatar? {
        guard time >= specialistStart && time < returnTime else { return nil }
        return CompanionAvatar.specialists[min(4, Int((time - specialistStart) / 3))]
    }
    static func spotlight(index: Int, time: Double) -> Double {
        let start = specialistStart + Double(index) * 3
        return CompanionEase.inOut(rigGSeg(time, start, start + 0.55))
            * (1 - CompanionEase.inOut(rigGSeg(time, start + 2.45, start + 3)))
    }
    static func turn(at time: Double) -> Int {
        guard time >= specialistStart else { return 0 }
        return min(6, 1 + Int((time - specialistStart) / 3))
    }
    static func dockSlot(member: CompanionAvatar, turn: Int) -> Int? {
        let index = CompanionAvatar.allCases.firstIndex(of: member)!
        let relative = (index - turn + 12) % 6
        return relative == 0 ? nil : relative - 1
    }
    struct QueuePose {
        var point: CGPoint
        var hero: Double
        var travelling: Bool
    }
    static func queue(member: CompanionAvatar, time: Double, layout: CompanionHomeLayout = .init()) -> QueuePose {
        let turn = turn(at: time)
        func point(_ turn: Int) -> CGPoint { dockSlot(member: member, turn: turn).map(layout.dock) ?? layout.hero }
        let current = point(turn)
        guard turn > 0 else { return QueuePose(point: current, hero: member == .sig ? 1 : 0, travelling: false) }
        let previous = point(turn - 1)
        let start = specialistStart + Double(turn - 1) * 3
        let p = CompanionEase.inOut(rigGSeg(time, start, start + 0.55))
        let wasHero = dockSlot(member: member, turn: turn - 1) == nil
        let isHero = dockSlot(member: member, turn: turn) == nil
        var position = CGPoint(x: rigGLerp(previous.x, current.x, p), y: rigGLerp(previous.y, current.y, p))
        if wasHero && p < 1 {
            // The previous speaker takes the lower route to the back of the
            // queue, leaving the copy and incoming speaker unobscured.
            let u = 1 - p, lower = Double(layout.top + 148)
            position = CGPoint(x: u*u*u*previous.x + 3*u*u*p*previous.x + 3*u*p*p*current.x + p*p*p*current.x,
                               y: u*u*u*previous.y + 3*u*u*p*lower + 3*u*p*p*lower + p*p*p*current.y)
        }
        return QueuePose(point: position, hero: rigGLerp(wasHero ? 1 : 0, isHero ? 1 : 0, p), travelling: p < 1)
    }
    static func waitingTime(member: CompanionAvatar, time: Double) -> Double? {
        let turn = turn(at: time)
        guard time >= dockTime, time < returnTime,
              member == CompanionAvatar.allCases[(turn + 1) % 6] else { return nil }
        let start = turn == 0 ? dockTime : specialistStart + Double(turn - 1) * 3
        let local = time - start - 1
        return local >= 0 && local < 0.85 ? local : nil
    }
    static func position(index: Int, time: Double, layout: CompanionHomeLayout = .init()) -> (x: Double, y: Double, emergence: Double, dock: Double) {
        let opening = CompanionOpeningLayout(home: layout)
        let start = assembleTime + Double(index) * 0.09
        let u = rigGSeg(time, start, start + 1)
        // Original v6 paths, stagger, overshoot, spin and downward docking arc.
        let angles = [150.0, 30, 90, 222, 318]
        let spin = 240 * (1 - CompanionEase.inOut(rigGSeg(time, assembleTime + 1, positionTime)))
        let angle = (angles[index] - spin) * .pi / 180
        let radius = 112 * opening.scale * CompanionEase.back(u)
        let x = Double(opening.center.x) + cos(angle) * radius
        let y = Double(opening.center.y) - sin(angle) * radius
        let d = CompanionEase.inOut(rigGSeg(time, positionTime + Double(index) * 0.08, 9.5 + Double(index) * 0.08))
        let target = layout.dock(index)
        return (rigGLerp(x, Double(target.x), d), rigGLerp(y, Double(target.y), d) - sin(d * .pi) * 22 * opening.scale,
                CompanionEase.out(rigGSeg(time, start, start + 0.25)), d)
    }
}

struct CompanionIntroductionCaption: View {
    var member: CompanionAvatar
    var copy: CompanionIntroductionCopy
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(member.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(member.tint)
            Text(copy.headline).font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(copy.description).font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(2)
            Text(copy.role).font(.system(size: 10, weight: .medium)).foregroundStyle(member.tint)
        }
    }
}

struct CompanionTeamArrival: View {
    var animates = true
    var previewTime: Double? = nil
    var started: Date? = nil
    var language: CompanionIntroductionLanguage = .english
    @State private var appeared = Date()
    @State private var stageTime = 0.0
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.islandReduceMotion) private var preferenceReducedMotion
    private var moves: Bool { animates && !reducedMotion && !preferenceReducedMotion }
    var body: some View {
        let t = moves ? max(0, previewTime ?? stageTime) : CompanionTeamFormation.duration
        GeometryReader { geometry in
            let layout = CompanionHomeLayout(size: geometry.size)
            ZStack {
                if moves {
                    let viewport = CompanionOpeningLayout.viewport(for: geometry.size)
                    CompanionTeamScene(time: t, animates: true, started: started ?? appeared,
                                       preview: previewTime != nil, size: viewport)
                        .frame(width: viewport.width, height: viewport.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .allowsHitTesting(false)
                } else {
                    CompanionCharacter(size: 96, avatar: .sig, animates: false)
                        .position(layout.hero)
                    ForEach(Array(CompanionAvatar.specialists.enumerated()), id: \.element.id) { index, member in
                        CompanionCharacter(size: 38, avatar: member, animates: false).position(layout.dock(index))
                    }
                }
                if t >= CompanionTeamFormation.dockTime || !moves {
                    let member = CompanionTeamFormation.activeMember(at: t) ?? .sig
                    let copy = CompanionIntroductionCopy.forIntroduction(at: t, language: language)
                    CompanionIntroductionCaption(member: member, copy: copy)
                        .frame(width: max(0, geometry.size.width - 142), alignment: .leading)
                        .position(x: 142 + max(0, geometry.size.width - 142) / 2, y: layout.hero.y - CompanionHomeLayout.introductionTextLift)
                        .id(member).transition(.opacity)
                }
                if t >= CompanionTeamFormation.dockTime {
                    ForEach(CompanionAvatar.allCases) { member in
                        let turn = CompanionTeamFormation.turn(at: t)
                        let slot = CompanionTeamFormation.dockSlot(member: member, turn: turn)
                        Text(member.name).font(.system(size: 9, weight: .medium)).foregroundStyle(CompanionStyle.muted)
                            .position(x: slot.map { layout.dock($0).x } ?? layout.hero.x, y: slot.map { layout.dock($0).y + 26.5 } ?? layout.hero.y)
                            .opacity(slot == nil ? 0 : 1)
                    }
                }
            }
        }.task(id: started) {
            guard moves, previewTime == nil else { return }
            let origin = started ?? appeared
            stageTime = max(0, Date().timeIntervalSince(origin))
            // Text updates only at stage boundaries; all frame-by-frame motion belongs
            // to one SceneKit renderer. Finished introductions stop rendering.
            for boundary in CompanionTeamFormation.boundaries {
                let delay = boundary - Date().timeIntervalSince(origin)
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.55)) { stageTime = max(boundary, Date().timeIntervalSince(origin)) }
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Sig greets you and introduces the Companions. Meet Rita, Ada, Gantt, Elinor and Toni. Sig returns and introduces himself as your orchestrator.")
    }
}

struct CompanionTeamScene: NSViewRepresentable {
    var time: Double
    var animates: Bool
    var started: Date? = nil
    var preview = false
    var size = CompanionOpeningLayout.viewport(for: CGSize(width: 532, height: CompanionHomeLayout.height))
    struct Input: Sendable {
        var start: Double
        var animates: Bool
        var size: CGSize
    }
    final class Coordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
        let greeting = CompanionGreetingRig(.sig)
        let agents: [CompanionRigModel]
        let camera: SCNNode
        private let sigContainer = SCNNode()
        private let agentBounds: [CGRect]
        private let inputLock = NSLock()
        private var input: Input?
        private var greetingFinished = false
        private var settledAgents: Set<Int> = []
        private var previousTime = -Double.infinity
        private var previousSize = CGSize.zero
        private var previousTurn = -1
        private let speakerHalo = SCNNode()
        private(set) var renderedFrameCount = 0
        private(set) var renderedOffMain = true
        private(set) var agentPoseUpdates = 0
        @MainActor override init() {
            agents = CompanionAvatar.specialists.map(CompanionRigModel.init)
            agentBounds = agents.map { rigNsPath(rigBodyPath($0.hero)).bounds }
            camera = greeting.scene.rootNode.childNodes.first(where: { $0.camera != nil })!
            let moving = [greeting.model.root, greeting.halo] + greeting.warps + greeting.ring
            for node in moving { sigContainer.addChildNode(node) }
            greeting.scene.rootNode.addChildNode(sigContainer)
            speakerHalo.geometry = SCNPlane(width: 94, height: 94)
            let glow = SCNMaterial(); glow.lightingModel = .constant
            glow.diffuse.contents = CompanionGreetingRig.glowTexture(); glow.writesToDepthBuffer = false; glow.readsFromDepthBuffer = false
            speakerHalo.geometry?.materials = [glow]; speakerHalo.opacity = 0
            speakerHalo.renderingOrder = -100
            greeting.scene.rootNode.addChildNode(speakerHalo)
            for model in agents { greeting.scene.rootNode.addChildNode(model.root); model.root.isHidden = true }
            super.init()
        }
        func configure(_ value: Input) { inputLock.lock(); input = value; inputLock.unlock() }
        func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            renderedFrameCount += 1; renderedOffMain = renderedOffMain && !Thread.isMainThread
            inputLock.lock(); let value = input; inputLock.unlock()
            guard let value, value.animates else { return }
            update(time: min(CompanionTeamFormation.duration, max(0, Date.timeIntervalSinceReferenceDate - value.start)),
                   animates: true, size: value.size)
        }
        func update(time: Double, animates: Bool, size: CGSize = CompanionOpeningLayout.viewport(for: CGSize(width: 532, height: CompanionHomeLayout.height))) {
            let layout = CompanionHomeLayout(size: size)
            let opening = CompanionOpeningLayout(home: layout)
            if camera.camera?.orthographicScale != Double(size.height) / 2 { camera.camera?.orthographicScale = Double(size.height) / 2 }
            let t = animates ? time : CompanionTeamFormation.duration
            if t < previousTime {
                greetingFinished = false; settledAgents.removeAll()
                sigContainer.opacity = 1
                (greeting.warps + greeting.ring).forEach { $0.isHidden = false }
            }
            if size != previousSize { settledAgents.removeAll(); previousSize = size }
            previousTime = t
            let active = CompanionTeamFormation.activeMember(at: t)
            let turn = CompanionTeamFormation.turn(at: t)
            if turn != previousTurn { settledAgents.removeAll(); previousTurn = turn }
            let bodySize = CompanionHomeLayout.bodySize(96)
            let sigScale = bodySize / max(greeting.bounds.width, greeting.bounds.height)
            let dock = CompanionEase.inOut(rigGSeg(t, CompanionTeamFormation.positionTime, CompanionTeamFormation.dockTime))
            let heroPoint = CGPoint(x: rigGLerp(Double(opening.center.x), Double(layout.hero.x), dock),
                                    y: rigGLerp(Double(opening.center.y), Double(layout.hero.y), dock))
            let sigPosition = layout.scene(heroPoint)
            if t < CompanionTeamFormation.dockTime && (sigContainer.position.x != sigPosition.x || sigContainer.position.y != sigPosition.y) { sigContainer.position = sigPosition }
            sigContainer.isHidden = false
            if t < CompanionTeamFormation.assembleTime {
                greeting.update(t)
                sigContainer.scale = SCNVector3(opening.scale, opening.scale, opening.scale)
            } else {
                if !greetingFinished {
                    greeting.update(CompanionTeamFormation.assembleTime); greetingFinished = true
                    (greeting.warps + greeting.ring).forEach { $0.isHidden = true }
                    sigContainer.scale = SCNVector3(1, 1, 1)
                    greeting.halo.position = SCNVector3(0, 0, -32)
                }
                if t < CompanionTeamFormation.dockTime {
                    let head = greeting.model.head
                    let s = rigGLerp(58 * opening.scale / greeting.bounds.height, sigScale, dock)
                    head.scale = SCNVector3(s, s, s)
                    head.position = SCNVector3(-greeting.bounds.midX * s, -greeting.bounds.midY * s, 0)
                    head.eulerAngles = SCNVector3(0, -0.07 + sin(t * 0.8) * 0.015, 0)
                    head.opacity = 1
                    greeting.handL.opacity = 0; greeting.handR.opacity = 0
                    greeting.model.updateEyes(open: 1, joy: 0.2, gaze: CGSize(width: dock * 1.5, height: 0), wink: 0, anger: 0)
                }
                let haloSize = rigGLerp(285, 200, dock) * opening.scale
                if Double(greeting.halo.scale.x) != haloSize { greeting.halo.scale = SCNVector3(haloSize, haloSize, 1) }
                let haloOpacity = CGFloat(rigGLerp(0.8, 0.24, dock) * (1 - rigGSeg(t, CompanionTeamFormation.specialistStart - 0.5, CompanionTeamFormation.specialistStart)))
                if greeting.halo.opacity != haloOpacity { greeting.halo.opacity = haloOpacity }
            }
            let models = [greeting.model] + agents
            for (index, model) in models.enumerated() {
                if index == 0 && t < CompanionTeamFormation.dockTime { continue }
                let bound = index == 0 ? greeting.bounds : agentBounds[index - 1]
                let base = index == 0 ? nil : CompanionTeamFormation.position(index: index - 1, time: t, layout: layout)
                let queued = t >= CompanionTeamFormation.dockTime
                let queue = CompanionTeamFormation.queue(member: model.hero, time: t, layout: layout)
                let isSpeaker = queued && queue.hero == 1
                let waitingTime = queued ? CompanionTeamFormation.waitingTime(member: model.hero, time: t) : nil
                // Settled miniatures have no frame-by-frame transform or eye
                // writes. At most one waiting companion reacts briefly.
                let isSettled = queued && !queue.travelling && !isSpeaker && waitingTime == nil
                if isSettled && settledAgents.contains(index) { continue }
                settledAgents.remove(index)
                if index > 0 { agentPoseUpdates += 1 }
                let spotlight = queued ? queue.hero : 0
                let local = max(0, t - (turn == 0 ? CompanionTeamFormation.dockTime : CompanionTeamFormation.specialistStart + Double(turn - 1) * 3) - 0.55)
                let pose = waitingTime.map { rigWaitingPose(model.hero, $0) }
                    ?? (isSpeaker ? rigIdentityHelloPose(model.hero, local) : rigIdentityHelloPose(model.hero, 0))
                let viewport = rigGLerp(38, 96, spotlight)
                let s = CompanionHomeLayout.bodySize(viewport) / max(bound.width, bound.height)
                let emergence = queued ? 1 : base!.emergence
                let pop = rigGLerp(0.5, 1, emergence)
                let root = index == 0 ? sigContainer : model.root
                root.isHidden = emergence == 0; root.opacity = emergence
                root.position = layout.scene(queued ? queue.point : CGPoint(x: base!.x, y: base!.y))
                root.position.z = CGFloat(-24 * (1 - emergence))
                if !queued {
                    let start = CompanionTeamFormation.assembleTime + Double(index - 1) * 0.09
                    let u = rigGSeg(t, start, start + 1)
                    let s = rigGLerp(rigGLerp(0.08, 40 / bound.height, CompanionEase.back(u)) * opening.scale,
                                     CompanionHomeLayout.bodySize(38) / max(bound.width, bound.height), base!.dock)
                    model.head.scale = SCNVector3(s, s, s)
                    model.head.position = SCNVector3(-bound.midX * s, -bound.midY * s, 0)
                    model.head.eulerAngles = SCNVector3(0, -0.1 + sin(t + Double(index - 1)) * 0.025, sin(t * 1.4 + Double(index - 1)) * 0.012)
                    let blink = (t + Double(index - 1) * 0.37).truncatingRemainder(dividingBy: 4.2)
                    let open = blink > 3.55 && blink < 3.85 ? 1 - sin((blink - 3.55) / 0.3 * .pi) * 0.95 : 1
                    let angles = [150.0, 30, 90, 222, 318]
                    let spin = 240 * (1 - CompanionEase.inOut(rigGSeg(t, 5.6, 7.4)))
                    let angle = (angles[index - 1] - spin) * .pi / 180
                    model.updateEyes(open: open, joy: 0, gaze: CGSize(width: -cos(angle) * 0.8 * (1 - base!.dock), height: 0), wink: 0, anger: 0)
                    root.position.z = CGFloat(-28 * (1 - CompanionEase.out(u)))
                    model.activity.isHidden = true
                    continue
                }
                model.head.scale = SCNVector3(s * pop * pose.sx, s * pop * pose.sy, s * pop)
                model.head.position = SCNVector3(-bound.midX * s * pop * pose.sx, -bound.midY * s * pop * pose.sy + pose.y * s, 0)
                model.head.eulerAngles = SCNVector3(pose.pitch, pose.yaw, pose.roll)
                model.updateEyes(open: pose.open, joy: pose.joy, gaze: pose.gaze, wink: pose.wink, anger: pose.anger)
                model.updateIdentityHello(time: local, strength: isSpeaker ? 1 : 0)
                if let waitingTime { model.updateWaitingGesture(time: waitingTime) }
                model.activity.isHidden = true
                if isSettled { settledAgents.insert(index) }
            }
            let speaker = active ?? .sig
            let lightStrength = t >= CompanionTeamFormation.specialistStart && t < CompanionTeamFormation.duration - 0.6 ? 0.24 : 0.0
            if speakerHalo.opacity != lightStrength { speakerHalo.opacity = lightStrength }
            if lightStrength > 0 {
                speakerHalo.position = layout.scene(layout.hero); speakerHalo.position.z = -32
                speakerHalo.geometry?.firstMaterial?.multiply.contents = NSColor(speaker.tint)
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> CompanionRenderView {
        let view = CompanionRenderView(frame: .zero)
        context.coordinator.update(time: time, animates: animates, size: size)
        CompanionSceneLighting.configure(view, scene: context.coordinator.greeting.scene, camera: context.coordinator.camera)
        configure(view, coordinator: context.coordinator); view.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: CompanionRenderView, context: Context) { configure(view, coordinator: context.coordinator) }
    private func configure(_ view: CompanionRenderView, coordinator: Coordinator) {
        coordinator.configure(Input(start: started?.timeIntervalSinceReferenceDate ?? Date.timeIntervalSinceReferenceDate - time,
                                    animates: animates && !preview, size: size))
        view.animationEnabled = animates && !preview && time < CompanionTeamFormation.duration
    }
    static func dismantleNSView(_ view: CompanionRenderView, coordinator: Coordinator) { view.stopRendering() }
}
