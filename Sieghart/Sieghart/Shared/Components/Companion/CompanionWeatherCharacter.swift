import AppKit
import Metal
@preconcurrency import SceneKit
import SwiftUI

/// Weather changes the approved Sig rig, including its face and attached cloth.
/// The surrounding weather scene owns precipitation, captions and the forecast.
struct CompanionWeatherCharacter: View {
    let mood: CompanionWeatherMood
    let animates: Bool
    let previewTime: Double?
    let freezing: Bool
    @Environment(\.islandPreview) private var preview
    @Environment(\.islandReduceMotion) private var islandReduceMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.companionMotionEnabled) private var motionEnabled

    init(mood: CompanionWeatherMood, animates: Bool, previewTime: Double? = nil, freezing: Bool? = nil) {
        self.mood = mood; self.animates = animates; self.previewTime = previewTime
        self.freezing = freezing ?? (mood == .frozen)
    }

    private var moves: Bool {
        animates && motionEnabled && !reduceMotion && !islandReduceMotion && !preview && previewTime == nil
    }

    var body: some View {
        GeometryReader { proxy in
            if moves {
                WeatherCharacterScene(mood: mood, freezing: freezing)
            } else {
                // ImageRenderer cannot draw SCNView. Render the same geometry,
                // at the destination's backing size, once per cached still.
                Image(nsImage: Self.snapshot(mood: mood, time: previewTime ?? (freezing ? 5.5 : 0), size: proxy.size, freezing: freezing))
                    .resizable().interpolation(.high).scaledToFit()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true) // The parent supplies the localized caption.
    }

    /// `size` is in points; the returned image carries a 2× alpha bitmap.
    /// Explicit preview times are deterministic and never start a display clock.
    @MainActor static func snapshot(mood: CompanionWeatherMood, time: Double, size: CGSize, freezing: Bool? = nil) -> NSImage {
        WeatherCharacterSnapshots.image(mood: mood, time: time, size: size, freezing: freezing ?? (mood == .frozen))
    }
}

private struct WeatherCharacterInput: Sendable {
    var mood: CompanionWeatherMood
    var freezing: Bool
}

private struct WeatherCharacterScene: NSViewRepresentable {
    let mood: CompanionWeatherMood
    let freezing: Bool

    final class Coordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
        let rig: WeatherCharacterRig
        private let lock = NSLock()
        private var input: WeatherCharacterInput
        private var currentMood: CompanionWeatherMood
        private var elapsed = 0.0
        private var lastFrame: Double?
        private var transition: WeatherCharacterPose?
        private var lastPose: WeatherCharacterPose
        private(set) var frostLevel = 0.0

        @MainActor init(mood: CompanionWeatherMood, freezing: Bool) {
            rig = WeatherCharacterRig()
            input = WeatherCharacterInput(mood: mood, freezing: freezing); currentMood = mood
            lastPose = WeatherCharacterPose.sample(mood, time: 0)
            super.init()
            rig.apply(mood: mood, time: 0, pose: lastPose)
        }

        func configure(mood: CompanionWeatherMood, freezing: Bool) {
            lock.lock(); input = WeatherCharacterInput(mood: mood, freezing: freezing); lock.unlock()
        }

        func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            lock.lock(); let input = self.input; lock.unlock()
            let mood = input.mood
            if mood != currentMood {
                transition = lastPose; currentMood = mood; elapsed = 0; lastFrame = nil
            }
            // A hidden/occluded SCNView has no callbacks. Resume from the held
            // pose, without catching up an offscreen sequence or wall clock.
            let gap = lastFrame.map { max(0,time-$0) } ?? 0
            let delta = gap < 0.25 ? gap : 0
            elapsed += delta; lastFrame = time
            frostLevel = min(1,max(0,frostLevel + delta * (input.freezing ? 1/6.4 : -1/2.6)))
            var pose = WeatherCharacterPose.sample(mood, time: elapsed)
            if let source = transition {
                let blend = rigSmooth(elapsed / 0.35)
                pose = source.mixed(with: pose, fraction: blend)
                if blend == 1 { transition = nil }
            }
            lastPose = pose
            // The renderer owns all mutable nodes while attached. SwiftUI only
            // writes the locked mood mailbox; it never submits display ticks.
            rig.apply(mood: mood, time: elapsed, pose: pose, frost: rigSmooth(frostLevel))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(mood: mood, freezing: freezing) }
    func makeNSView(context: Context) -> CompanionRenderView {
        let view = CompanionRenderView(frame: .zero)
        CompanionSceneLighting.configure(view, scene: context.coordinator.rig.scene,
                                         camera: context.coordinator.rig.camera)
        view.preferredFramesPerSecond = 24
        view.delegate = context.coordinator
        view.animationEnabled = true
        return view
    }
    func updateNSView(_ view: CompanionRenderView, context: Context) {
        context.coordinator.configure(mood: mood, freezing: freezing)
        view.animationEnabled = true
    }
    static func dismantleNSView(_ view: CompanionRenderView, coordinator: Coordinator) {
        view.stopRendering()
    }
}

private struct WeatherCharacterPose {
    var x = 0.0, y = 0.0, sx = 1.0, sy = 1.0
    var roll = 0.0, yaw = -0.09, pitch = 0.0
    var open = 1.0, joy = 0.0, gazeX = 0.0, gazeY = 0.0, wink = 0.0
    var handLX = -34.0, handLY = -14.0, handLZ = 16.0, handLRoll = 0.0
    var handRX = 34.0, handRY = -14.0, handRZ = 16.0, handRRoll = 0.0
    var hands = 0.0, tail = 0.0

    static func sample(_ mood: CompanionWeatherMood, time: Double) -> Self {
        let t = max(0, time), breath = sin(t * 1.45)
        var p = Self()
        p.sy += breath * 0.006
        let blink = t.truncatingRemainder(dividingBy: 5.8)
        let blinkOpen = 1 - pulse(blink, 4.8, 0.22) * 0.94
        switch mood {
        case .comfortable:
            p.joy = 0.35; p.open = blinkOpen
            p.roll = sin(t * 0.65) * 0.012
            p.gazeX = sin(t * 0.6) * 0.7
            p.wink = pulse(t.truncatingRemainder(dividingBy: 9.5), 6.9, 0.4) * 0.8
        case .cloudy:
            p.joy = 0.12; p.open = 0.82 * blinkOpen
            p.gazeX = sin(t*0.45)*2.2; p.gazeY = -1.4
            p.yaw += sin(t*0.45)*0.065; p.roll = sin(t*0.5)*0.018
            p.pitch = -0.035
        case .hail:
            let duck = pulse(t.truncatingRemainder(dividingBy: 4.8), 0.8, 1.1)
            p.hands = 1; p.sx = 0.95; p.sy = 0.94-duck*0.09; p.y = -duck*3
            p.open = (0.65-duck*0.38)*blinkOpen; p.pitch = 0.04+duck*0.08
            p.gazeY = -1.8; p.roll = -0.03+sin(t*8)*duck*0.015
            p.handLX = -19; p.handLY = 19; p.handLZ = 22; p.handLRoll = -0.25
            p.handRX = 16; p.handRY = 18; p.handRZ = 22; p.handRRoll = 0.25
        case .cold, .frozen, .snow:
            let severe = mood != .cold
            let phase = t.truncatingRemainder(dividingBy: severe ? 4.6 : 7.8)
            let shiver = pulse(phase, 0.65, severe ? 1.45 : 0.95)
            p.sx = severe ? 0.93 : 0.97; p.sy = (severe ? 0.86 : 0.93) + breath * 0.008
            p.y = severe ? -3 : -1
            p.x = sin(t * 43) * shiver * (severe ? 1.45 : 0.8)
            p.roll = -0.025 + sin(t * 37) * shiver * 0.025
            p.pitch = 0.13; p.open = (severe ? 0.48 : 0.72) * blinkOpen
            p.gazeY = 0.9; p.hands = 1
            p.handLX = -17; p.handLY = -12; p.handLZ = 24; p.handLRoll = -0.55
            p.handRX = 14; p.handRY = -14; p.handRZ = 25; p.handRRoll = 0.55
            p.tail = sin(t * 37) * shiver * 0.055
            if mood == .snow {
                let peek = pulse(phase, 2.7, 1.1)
                p.gazeY -= peek * 3; p.pitch -= peek * 0.15
                p.open += peek * 0.17; p.yaw -= peek * 0.08
            }
        case .hot:
            let fan = pulse(t.truncatingRemainder(dividingBy: 6.6), 1.1, 2.8)
            p.sx = 1.025; p.sy = 0.92 + breath * 0.025; p.y = -2
            p.roll = -0.055; p.pitch = 0.045; p.open = 0.34 * blinkOpen
            p.gazeX = -0.8; p.gazeY = 0.8; p.hands = 1
            p.handLX = -33; p.handLY = -19; p.handLRoll = -0.15
            p.handRX = 35 - fan * 9; p.handRY = 0 + fan * 13
            p.handRZ = 21; p.handRRoll = -0.3 + sin(t * 18) * fan * 0.65
            p.yaw += sin(t * 18) * fan * 0.018
        case .rain, .storm:
            let severe = mood == .storm
            let phase = t.truncatingRemainder(dividingBy: severe ? 6.9 : 8.2)
            let shake = pulse(phase, 4.4, 0.85)
            p.sx = severe ? 0.95 : 0.99; p.sy = severe ? 0.89 : 0.96
            p.roll = -0.065 + sin(t * 25) * shake * 0.065
            p.yaw += sin(t * 25) * shake * 0.12
            p.pitch = -0.045; p.open = (severe ? 0.53 : 0.65) * blinkOpen
            p.gazeX = -1.4; p.gazeY = -1.2; p.hands = 1
            // A hand of the same charcoal material shields the actual brow.
            p.handLX = -17; p.handLY = 18; p.handLZ = 21; p.handLRoll = -0.2
            p.handRX = 28; p.handRY = -13; p.handRZ = 22; p.handRRoll = 0.6
            if severe {
                let huddle = pulse(phase, 0.8, 1.2)
                p.sy -= huddle * 0.04; p.y -= huddle * 2
                p.open *= 1 - huddle * 0.6
                p.handRX -= huddle * 8
            }
        }
        return p
    }

    static func pulse(_ time: Double, _ start: Double, _ duration: Double) -> Double {
        guard time > start, time < start + duration else { return 0 }
        return pow(sin((time - start) / duration * .pi), 2)
    }

    func mixed(with b: Self, fraction f: Double) -> Self {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        var p = b
        p.x = m(x,b.x); p.y = m(y,b.y); p.sx = m(sx,b.sx); p.sy = m(sy,b.sy)
        p.roll = m(roll,b.roll); p.yaw = m(yaw,b.yaw); p.pitch = m(pitch,b.pitch)
        p.open = m(open,b.open); p.joy = m(joy,b.joy)
        p.gazeX = m(gazeX,b.gazeX); p.gazeY = m(gazeY,b.gazeY); p.wink = m(wink,b.wink)
        p.handLX = m(handLX,b.handLX); p.handLY = m(handLY,b.handLY); p.handLZ = m(handLZ,b.handLZ)
        p.handRX = m(handRX,b.handRX); p.handRY = m(handRY,b.handRY); p.handRZ = m(handRZ,b.handRZ)
        p.handLRoll = m(handLRoll,b.handLRoll); p.handRRoll = m(handRRoll,b.handRRoll)
        p.hands = m(hands,b.hands); p.tail = m(tail,b.tail)
        return p
    }
}

/// One Sig model and a bounded collection of reusable meshes. Nothing is
/// tessellated or allocated at display frequency except the rig's bounded eye variants.
private final class WeatherCharacterRig {
    let scene = SCNScene()
    let camera: SCNNode
    let model: CompanionRigModel
    private let scarf = SCNNode(), tail = SCNNode(), snow = SCNNode()
    private let leftHand: SCNNode, rightHand: SCNNode
    private var ice: [SCNNode] = []
    private var frostMaterials: [SCNMaterial] = []
    private var breath: [SCNNode] = [], drops: [SCNNode] = [], flakes: [SCNNode] = []

    @MainActor init() {
        model = CompanionRigModel(.sig)
        camera = CompanionSceneLighting.configure(scene, scale: 51)
        model.root.position.y = 6
        scene.rootNode.addChildNode(model.root)
        if let body = model.head.childNodes.first?.geometry {
            // Modify only this new model's surface, preserving its approved
            // geometry shader, cream eyes and mint pin. No enclosing ice box.
            var identifiers: Set<ObjectIdentifier> = []
            for material in body.materials where identifiers.insert(ObjectIdentifier(material)).inserted {
                var shaders = material.shaderModifiers ?? [:]
                shaders[.surface] = Self.frostShader
                material.shaderModifiers = shaders
                material.setValue(Float(0), forKey: "weatherFrost")
                frostMaterials.append(material)
            }
        }
        let iceMaterial = rigMaterial(rigRgb(0.57,0.79,0.87))
        iceMaterial.roughness.contents = 0.30; iceMaterial.metalness.contents = 0.06
        for (index, point) in [(-34.0,12.0),(-25,22),(-10,24),(7,24),(38,5),(37,-8),(-38,-3),(-29,-20),(11,-24)].enumerated() {
            let geometry = SCNPyramid(width: 3.0, height: 4.5+Double(index%3), length: 2.8)
            geometry.materials = [iceMaterial]
            let crystal = SCNNode(geometry: geometry)
            crystal.position = SCNVector3(point.0,point.1,model.front-1)
            crystal.eulerAngles.z = CGFloat(atan2(point.1,point.0) - .pi/2)
            model.head.addChildNode(crystal); ice.append(crystal)
        }
        let charcoal = rigMaterial(CompanionAvatar.sig.color)
        leftHand = Self.ellipsoid(5.6, 3.5, 3.0, material: charcoal)
        rightHand = Self.ellipsoid(5.6, 3.5, 3.0, material: charcoal)
        model.head.addChildNode(leftHand); model.head.addChildNode(rightHand)

        let cloth = rigMaterial(rigRgb(0.65, 0.32, 0.39)); cloth.roughness.contents = 0.86
        let fold = rigMaterial(rigRgb(0.73, 0.39, 0.44)); fold.roughness.contents = 0.86
        let collar = Self.collar(material: cloth)
        scarf.addChildNode(collar)
        let knot = Self.ellipsoid(5.7, 4.4, 3.0, material: fold)
        knot.position = SCNVector3(23, -15, 19); knot.eulerAngles.z = -0.22
        scarf.addChildNode(knot)
        tail.position = SCNVector3(22, -16, 19)
        tail.addChildNode(Self.scarfTail(material: cloth))
        // The hems and fringe have actual thickness and share scene lighting.
        for index in 0..<3 {
            let fringe = Self.ellipsoid(0.8, 2.4, 0.7, material: fold)
            fringe.position = SCNVector3(1 + Double(index) * 2.0, -24.0 - Double(index % 2), 0.8)
            tail.addChildNode(fringe)
        }
        scarf.addChildNode(tail); model.head.addChildNode(scarf)

        let snowMaterial = rigMaterial(rigRgb(0.87, 0.94, 0.97)); snowMaterial.roughness.contents = 0.94
        for (x, y, width) in [(-22.0, 23.0, 10.0), (-7, 24, 13), (8, 23.8, 8)] {
            let mound = Self.ellipsoid(width, 3.1, 6.0, material: snowMaterial)
            mound.position = SCNVector3(x, y, 3.8); snow.addChildNode(mound)
        }
        model.head.addChildNode(snow)
        let vaporMaterial = rigMaterial(rigRgb(0.83, 0.90, 0.92))
        vaporMaterial.transparency = 0.2; vaporMaterial.writesToDepthBuffer = false
        for _ in 0..<3 {
            let node = Self.ellipsoid(3.8, 2.2, 1.2, material: vaporMaterial)
            model.head.addChildNode(node); breath.append(node)
        }
        let water = rigMaterial(rigRgb(0.48, 0.67, 0.74))
        water.roughness.contents = 0.22; water.metalness.contents = 0.08
        for _ in 0..<6 {
            let node = Self.ellipsoid(1.0, 1.9, 0.8, material: water)
            model.head.addChildNode(node); drops.append(node)
        }
        for _ in 0..<4 {
            let node = Self.ellipsoid(1.1, 0.8, 0.7, material: snowMaterial)
            model.head.addChildNode(node); flakes.append(node)
        }
    }

    func apply(mood: CompanionWeatherMood, time: Double, pose p: WeatherCharacterPose, frost: Double = 0) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        model.head.position = SCNVector3(p.x, p.y, 0)
        model.head.scale = SCNVector3(p.sx*(1-frost*0.035), p.sy*(1-frost*0.05), 1)
        model.head.eulerAngles = SCNVector3(p.pitch, p.yaw, p.roll)
        model.updateEyes(open: p.open, joy: p.joy,
                         gaze: CGSize(width: p.gazeX, height: p.gazeY), wink: p.wink, anger: 0)
        leftHand.position = SCNVector3(p.handLX, p.handLY, p.handLZ)
        rightHand.position = SCNVector3(p.handRX, p.handRY, p.handRZ)
        leftHand.eulerAngles.z = CGFloat(p.handLRoll); rightHand.eulerAngles.z = CGFloat(p.handRRoll)
        leftHand.opacity = p.hands; rightHand.opacity = p.hands
        for material in frostMaterials { material.setValue(Float(frost), forKey: "weatherFrost") }
        for (index, crystal) in ice.enumerated() {
            let grow = rigSmooth((frost-Double(index)*0.045)*2.1)
            crystal.isHidden = grow <= 0.002
            crystal.scale = SCNVector3(0.25+grow*0.75, max(0.01,grow), 0.4+grow*0.6)
            crystal.opacity = grow*0.78
        }
        let chilly = mood == .cold || mood == .frozen || mood == .snow || frost > 0.01
        scarf.isHidden = !chilly
        tail.eulerAngles = SCNVector3(0.07, p.tail * 0.6, -0.10 + p.tail)
        snow.isHidden = mood != .snow

        for (index, node) in breath.enumerated() {
            let cycle = (max(0, time) + Double(index) * 0.18).truncatingRemainder(dividingBy: 4.6)
            let v = (cycle - 2.5) / 1.35
            node.isHidden = !chilly || v <= 0 || v >= 1
            if !node.isHidden {
                node.position = SCNVector3(-7 - v * 18 - Double(index), -8 + v * 6, 24)
                let scale = 0.65 + v * 1.3
                node.scale = SCNVector3(scale, scale, scale)
                node.opacity = sin(v * .pi) * 0.42
            }
        }
        let wet = mood == .rain || mood == .storm || mood == .hail
        for (index, node) in drops.enumerated() {
            let v = (max(0, time) / (mood == .hot ? 1.9 : 2.3) + Double(index) * 0.173)
                .truncatingRemainder(dividingBy: 1)
            node.isHidden = !(wet || mood == .hot)
            if !node.isHidden {
                let side = index % 2 == 0 ? 1.0 : -1.0
                node.position = mood == .hot
                    ? SCNVector3(side * (23 + Double(index / 2) * 3 + sin(v * .pi) * 4), 23 - v * 46, 21)
                    : SCNVector3(side * (31 + sin(v * .pi) * 4), 17 - v * 33, 15)
                node.opacity = sin(v * .pi) * (mood == .hot ? 0.98 : 0.85)
                node.scale = mood == .hot ? SCNVector3(1.35, 1.1 + v * 0.55, 1.2) : SCNVector3(1, 0.7, 1)
            }
        }
        for (index, node) in flakes.enumerated() {
            let v = (max(0, time) / 3.2 + Double(index) * 0.23).truncatingRemainder(dividingBy: 1)
            node.isHidden = mood != .snow
            if !node.isHidden {
                node.position = SCNVector3(-28 + Double(index) * 14 + sin(v * .pi * 2) * 3,
                                          43 - v * 20, 6 + Double(index % 2) * 8)
                node.opacity = sin(v * .pi) * 0.8
            }
        }
        SCNTransaction.commit()
    }

    private static let frostShader = """
    #pragma arguments
    float weatherFrost;
    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    float grain = sin(uv.x*21.0+sin(uv.y*15.0))*sin(uv.y*25.0+sin(uv.x*11.0));
    float rim = abs(uv.x-0.5)*1.1+abs(uv.y-0.5)*0.65;
    float threshold = 1.12-weatherFrost*1.65;
    float coverage = smoothstep(threshold-0.22,threshold+0.18,rim+grain*0.025)*weatherFrost;
    float3 ice = float3(0.35,0.58,0.67)+grain*0.007;
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb,ice,coverage*0.80);
    _surface.roughness = mix(_surface.roughness,0.30,coverage);
    """

    private static func ellipsoid(_ x: Double, _ y: Double, _ z: Double, material: SCNMaterial) -> SCNNode {
        let sphere = SCNSphere(radius: 1); sphere.segmentCount = 16
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere); node.scale = SCNVector3(x, y, z)
        // Keep the mesh dimensions in a child; pose animation scales its wrapper.
        let root = SCNNode(); root.addChildNode(node); return root
    }

    /// A continuous closed cloth tube follows the body's X/Z cross-section.
    /// Its front drapes lower than its back; the ring is never a frontal capsule.
    private static func collar(material: SCNMaterial) -> SCNNode {
        mesh(rows: 64, columns: 12, material: material) { i, j in
            let u = Double(i) / 64 * .pi * 2, v = Double(j) / 12 * .pi * 2
            let drape = max(0, sin(u))
            let x = (36 + cos(v) * 2.4) * cos(u)
            let y = -11 - drape * drape * 6 + sin(v) * 3.4
            let z = (16.4 + cos(v) * 2.0) * sin(u)
            return SCNVector3(x, y, z)
        }
    }

    /// Closed rounded ribbon, including tapered ends, with folds in depth.
    private static func scarfTail(material: SCNMaterial) -> SCNNode {
        mesh(rows: 24, columns: 12, material: material) { i, j in
            let u = Double(i) / 24, v = Double(j) / 12 * .pi * 2
            let cap = min(1, sin(u * .pi) * 8)
            return SCNVector3(sin(u * 3.5) * 3 + cos(v) * 4.1 * cap,
                              -u * 24,
                              sin(u * .pi * 2) * 1.8 + sin(v) * 1.65 * cap)
        }
    }

    private static func mesh(rows: Int, columns: Int, material: SCNMaterial,
                             point: (Int, Int) -> SCNVector3) -> SCNNode {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        var uv: [CGPoint] = []
        // Surface normals use finite differences; both meshes are closed around
        // each cross-section and have persistent, smoothly shaded vertices.
        for i in 0...rows {
            for j in 0...columns {
                let p = point(i,j)
                let a = point(min(rows,i+1),j), b = point(max(0,i-1),j)
                let c = point(i,(j+1) % columns), d = point(i,(j+columns-1) % columns)
                let ux = a.x-b.x, uy = a.y-b.y, uz = a.z-b.z
                let vx = c.x-d.x, vy = c.y-d.y, vz = c.z-d.z
                let nx = uy*vz-uz*vy, ny = uz*vx-ux*vz, nz = ux*vy-uy*vx
                let length = max(0.0001, sqrt(nx*nx+ny*ny+nz*nz))
                vertices.append(p); normals.append(SCNVector3(-nx/length,-ny/length,-nz/length))
                uv.append(CGPoint(x: Double(i)/Double(rows), y: Double(j)/Double(columns)))
                if i < rows && j < columns {
                    let a = Int32(i*(columns+1)+j), b = a+Int32(columns+1)
                    indices += [a,a+1,b,a+1,b+1,b]
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                             SCNGeometrySource(textureCoordinates: uv)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}

@MainActor private enum WeatherCharacterSnapshots {
    private static var cache: [String: NSImage] = [:]
    private static var order: [String] = []

    static func image(mood: CompanionWeatherMood, time: Double, size: CGSize, freezing: Bool) -> NSImage {
        let width = Int(min(512, max(1, size.width.isFinite ? size.width : 154)) * 2)
        let height = Int(min(512, max(1, size.height.isFinite ? size.height : 156)) * 2)
        let safeTime = time.isFinite ? min(86_400, max(0, time)) : 0
        let frame = Int((safeTime * 24).rounded()), t = Double(frame) / 24
        let key = "\(mood.rawValue):\(freezing):\(frame):\(width):\(height)"
        if let cached = cache[key] { return cached }
        let rig = WeatherCharacterRig()
        rig.apply(mood: mood, time: t, pose: WeatherCharacterPose.sample(mood, time: t),
                  frost: freezing ? rigSmooth(t/6.4) : 0)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = rig.scene; renderer.pointOfView = rig.camera
        renderer.autoenablesDefaultLighting = false
        let rendered = renderer.snapshot(atTime: t, with: CGSize(width: width, height: height), antialiasingMode: .multisampling4X)
        let image = NSImage(size: CGSize(width: CGFloat(width)/2, height: CGFloat(height)/2))
        guard let cg = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // A headless/Metal-unavailable host may not produce a scene image.
            // Keep the approved silhouette when bundled; do not cache a failed render.
            return NSImage(named: "Companion-sig") ?? image
        }
        let rep = NSBitmapImageRep(cgImage: cg); rep.size = image.size; image.addRepresentation(rep)
        cache[key] = image; order.append(key)
        // Bound raster memory by both count and pixels (approximately 8 MiB).
        func pixels() -> Int { cache.values.reduce(0) { $0 + Int($1.size.width * $1.size.height * 4) } }
        while order.count > 14 || pixels() > 2_097_152 {
            cache.removeValue(forKey: order.removeFirst())
        }
        return image
    }
}
