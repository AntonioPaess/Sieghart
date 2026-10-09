import AppKit
import SwiftUI

// Stable identifiers keep the selection independent of display names.
enum CompanionAvatar: String, CaseIterable, Identifiable {
    case crtBuddy = "crt-buddy"
    case arcade1984 = "arcade-1984"
    case minimalSpirit = "minimal-spirit"
    case coastBuddy = "coast-buddy"
    case paperPal = "paper-pal"
    case inkBuddy = "ink-buddy"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .crtBuddy: "CRT Buddy"
        case .arcade1984: "Arcade 1984"
        case .minimalSpirit: "Minimal Spirit"
        case .coastBuddy: "Coast Buddy"
        case .paperPal: "Paper Pal"
        case .inkBuddy: "Ink Buddy"
        }
    }
    var subtitle: String {
        switch self {
        case .crtBuddy: "Phosphor soul"
        case .arcade1984: "Pixel nostalgia"
        case .minimalSpirit: "Less, with feeling"
        case .coastBuddy: "Take it easy"
        case .paperPal: "Folded with care"
        case .inkBuddy: "Classic, with character"
        }
    }
    var detail: String {
        switch self {
        case .crtBuddy: "A lilac square with mint eyes and a warm, curious gaze."
        case .arcade1984: "An amber pixel silhouette with playful eyes and little victory hops."
        case .minimalSpirit: "Just a face, a soft blink, and a little personality."
        case .coastBuddy: "A seafoam companion with rested eyes, a tiny curl and an unhurried rhythm."
        case .paperPal: "An ivory folded diamond with a coral edge and a gentle expression."
        case .inkBuddy: "A charcoal capsule with white eyes and a quietly cheeky personality."
        }
    }
    var tint: Color {
        switch self {
        case .crtBuddy, .minimalSpirit: CompanionStyle.accent
        case .coastBuddy: Color(red: 0.43, green: 0.77, blue: 0.71)
        case .inkBuddy: Color(red: 0.86, green: 0.84, blue: 0.78)
        case .arcade1984: Color(red: 1, green: 0.80, blue: 0.43)
        case .paperPal: Color(red: 1, green: 0.62, blue: 0.48)
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
        let t = time * (avatar == .coastBuddy ? 0.8 : 1) + index * 0.61
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
        result.offset.height = sin(t * 1.8) * size * (avatar == .minimalSpirit ? 0.009 : 0.018)
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
        case .crtBuddy: Color(red: 0.76, green: 0.65, blue: 0.97)
        case .arcade1984: Color(red: 1, green: 0.78, blue: 0.35)
        case .minimalSpirit: Color(red: 0.75, green: 0.72, blue: 0.90)
        case .coastBuddy: Color(red: 0.46, green: 0.72, blue: 0.61)
        case .paperPal: Color(red: 1, green: 0.63, blue: 0.52)
        case .inkBuddy: Color(red: 0.55, green: 0.62, blue: 0.61)
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
    static func sample(phase: CompanionVoicePhase, elapsed: Double, size: CGFloat, avatar: CompanionAvatar = .crtBuddy, animates: Bool) -> CompanionVoicePose {
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
            pose.rotation = avatar == .arcade1984 ? 0 : -2
            pose.eyeMultiplier = 1.03
        case .listening:
            pose.rotation = avatar == .arcade1984 ? 0 : -2.5 + sin(t * w) * 1.6
            pose.gaze = CGSize(width: sin(t * w) * 0.9, height: -0.4)
            pose.eyeMultiplier = avatar == .coastBuddy ? 1 : 1.06
            if avatar == .coastBuddy { pose.joy = 0.12 }
        case .thinking, .working:
            pose.rotation = avatar == .arcade1984 ? 0 : sin(t * w) * (avatar == .coastBuddy ? 1.6 : 2.4)
            pose.gaze = CGSize(width: sin(t * w) * 2.8, height: -1.7)
            pose.eyeMultiplier = 0.90; pose.offset.height *= 1.8
            if avatar == .coastBuddy { pose.joy = 0.18 }
        case .success:
            // Play once per successful lifecycle transition, then hold a calm
            // face until the result is dismissed. No full turn or looping jump.
            pose.scaleX = 1; pose.scaleY = 1; pose.offset = .zero
            let p = min(1, t / 1.05), bump = sin(p * .pi), nod = sin(p * .pi * 2) * (1 - p)
            pose.joy = min(1, max(0, sin(p * .pi * 0.7)))
            switch avatar {
            case .crtBuddy:
                pose.scaleX = 1 + bump * 0.035; pose.scaleY = 1 - bump * 0.025
                pose.rotation = nod * 4; pose.offset.height = -bump * size * (2 / 112.0)
            case .arcade1984:
                pose.offset.height = -bump * size * (4 / 112.0)
                pose.scaleX = 1 + bump * 0.025; pose.scaleY = 1 - bump * 0.025
            case .minimalSpirit:
                pose.rotation = nod * 4; pose.offset.height = -bump * size * (1.5 / 112.0)
            case .coastBuddy:
                pose.rotation = nod * 5; pose.offset.height = bump * size * (2 / 112.0)
                pose.gaze.width = bump * 0.7; pose.joy = bump * 0.35; pose.wink = bump * 0.92
            case .paperPal:
                pose.rotation = sin(p * .pi * 3) * (1 - p) * 5
                pose.scaleX = 1 + bump * 0.018; pose.offset.height = -bump * size * (2.5 / 112.0)
            case .inkBuddy:
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
    func sample(at time: Double, size: CGFloat, avatar: CompanionAvatar = .crtBuddy, animates: Bool) -> CompanionVoicePose {
        let elapsed = max(0, time - started)
        let target = CompanionVoiceMotion.sample(phase: phase, elapsed: elapsed, size: size, avatar: avatar, animates: animates)
        guard animates else { return target }
        let p = min(1, elapsed / 0.22)
        return source.blended(to: target, progress: p * p * (3 - 2 * p))
    }
    mutating func transition(to next: CompanionVoicePhase, at time: Double, size: CGFloat, avatar: CompanionAvatar = .crtBuddy, animates: Bool) {
        guard phase != next else { return }
        source = sample(at: time, size: size, avatar: avatar, animates: animates)
        started = time; phase = next
    }
}

struct CompanionLoadingShape: Shape {
    var avatar: CompanionAvatar
    func path(in rect: CGRect) -> Path {
        switch avatar {
        case .crtBuddy: return Path(roundedRect: rect, cornerRadius: rect.width * 0.24)
        case .arcade1984:
            let points: [(CGFloat,CGFloat)] = [(0.25,0),(0.75,0),(0.75,0.125),(0.875,0.125),(0.875,0.25),(1,0.25),(1,0.75),(0.875,0.75),(0.875,0.875),(0.75,0.875),(0.75,1),(0.25,1),(0.25,0.875),(0.125,0.875),(0.125,0.75),(0,0.75),(0,0.25),(0.125,0.25),(0.125,0.125),(0.25,0.125)]
            var p = Path()
            for (n, point) in points.enumerated() {
                let v = CGPoint(x: rect.minX + rect.width * point.0, y: rect.minY + rect.height * point.1)
                if n == 0 { p.move(to: v) } else { p.addLine(to: v) }
            }
            p.closeSubpath(); return p
        case .paperPal:
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath(); return p
        case .inkBuddy: return Path(roundedRect: rect.insetBy(dx: 0, dy: rect.height * 0.12), cornerRadius: rect.width * 0.38)
        case .coastBuddy: return Path(roundedRect: rect, cornerRadius: rect.width * 0.32)
        case .minimalSpirit: return Path(ellipseIn: rect)
        }
    }
}

struct CompanionLoadingBadge: View {
    var avatar: CompanionAvatar
    var time: Double
    var body: some View {
        Canvas { context, size in
            // Normalize drawing units so the compact 8-point marker remains
            // legible with the same shape as its larger counterpart.
            context.scaleBy(x: size.width / 28, y: size.height / 28)
            let size = CGSize(width: 28, height: 28)
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let shape = CompanionLoadingShape(avatar: avatar).path(in: rect)
            let inner = CompanionLoadingShape(avatar: avatar).path(in: rect.insetBy(dx: 4.0, dy: 4.0))
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.16), radius: 1.5, y: 1))
                layer.fill(shape, with: .linearGradient(Gradient(colors: [avatar.processingTint, avatar.processingTint.opacity(0.95)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)))
                layer.stroke(shape, with: .color(Color(red: 0.14, green: 0.17, blue: 0.16).opacity(0.70)), lineWidth: 1.2)
            }
            let ink = Color(red: 0.14, green: 0.17, blue: 0.16)
            context.stroke(inner, with: .color(ink.opacity(0.14)), style: StrokeStyle(lineWidth: 1.6, lineCap: avatar == .arcade1984 ? .square : .round, lineJoin: avatar == .arcade1984 ? .miter : .round))
            let start = time.truncatingRemainder(dividingBy: 2) / 2
            let length = 0.29
            let stroke = StrokeStyle(lineWidth: 1.9, lineCap: avatar == .arcade1984 ? .square : .round, lineJoin: avatar == .arcade1984 ? .miter : .round)
            context.stroke(inner.trimmedPath(from: start, to: min(1, start + length)), with: .color(ink.opacity(0.9)), style: stroke)
            if start + length > 1 { context.stroke(inner.trimmedPath(from: 0, to: start + length - 1), with: .color(ink.opacity(0.9)), style: stroke) }
        }
    }
}

struct CompanionFace: View {
    var renderSize: CGFloat = 42
    var avatar: CompanionAvatar = .crtBuddy
    var blinking = false
    var focusing = false
    var joyful = false
    var gaze = CGSize.zero
    var eyeOpen: CGFloat? = nil
    var listening = false
    var motionTime: Double = 0
    var mood: CompanionMood = .idle
    var animates = false
    var joyAmount: CGFloat? = nil
    var wink: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expression: (open: CGFloat, joy: CGFloat, tilt: CGFloat) {
        let blink = eyeOpen ?? (blinking ? 0.06 : 1)
        switch joyful ? CompanionMood.happy : mood {
        case .happy, .celebrating: return (blink, 1, 0)
        case .annoyed: return (blink * 0.28, 0, 20)
        case .asleep: return (0.07, 0, -3)
        case .waking: return (blink * 1.05, 0.3, 0)
        case .startled: return (blink * 1.2, 0, 0)
        case .understood: return (blink, 0.6, 0)
        case .idle: return (blink * (focusing ? 0.75 : listening ? 1.08 : 1), 0, 0)
        }
    }

    var body: some View {
        SimpleCompanionFace(avatar: avatar, openness: expression.open, joy: joyAmount ?? expression.joy, tilt: expression.tilt,
                            gaze: CGSize(width: min(4, max(-4, gaze.width)), height: min(3, max(-3, gaze.height))), wink: wink)
            .frame(width: renderSize, height: renderSize)
            .animation(animates && !reduceMotion ? .spring(response: 0.32, dampingFraction: 0.82) : nil, value: mood)
            .animation(animates && !reduceMotion ? .spring(response: 0.32, dampingFraction: 0.82) : nil, value: joyful)
            .animation(animates && !reduceMotion ? .spring(response: 0.32, dampingFraction: 0.85) : nil, value: gaze)
            .animation(animates && !reduceMotion ? .easeInOut(duration: 0.25) : nil, value: focusing)
            .animation(animates && !reduceMotion ? .easeInOut(duration: 0.25) : nil, value: listening)
            .accessibilityHidden(true)
    }
}

private struct SimpleCompanionFace: View, Animatable {
    var avatar: CompanionAvatar
    var openness: CGFloat
    var joy: CGFloat
    var tilt: CGFloat
    var gaze: CGSize
    var wink: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    nonisolated var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(AnimatablePair(openness, joy), AnimatablePair(AnimatablePair(tilt, gaze.width), AnimatablePair(gaze.height, wink))) }
        set { openness = newValue.first.first; joy = newValue.first.second; tilt = newValue.second.first.first; gaze = CGSize(width: newValue.second.first.second, height: newValue.second.second.first); wink = newValue.second.second.second }
    }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 96, y: size.height / 96)
            drawBody(in: context)
            let eyeColor: Color = avatar == .crtBuddy ? Color(red: 0.55, green: 0.95, blue: 0.82) : avatar == .inkBuddy ? .white : avatar == .minimalSpirit && colorScheme == .dark ? .white : Color(red: 0.10, green: 0.12, blue: 0.12)
            let pixel = avatar == .arcade1984
            let eyeWidth: CGFloat = pixel ? 12 : avatar == .minimalSpirit ? 14 : 11
            let eyeHeight: CGFloat = pixel ? 12 : avatar == .minimalSpirit ? 29 : 22
            let centers: [CGFloat] = avatar == .paperPal ? [36, 59] : [34, 62]
            for (index, centerX) in centers.enumerated() {
                let width = eyeWidth + joy * 5
                let height = max(1.8, eyeHeight * openness * (avatar == .coastBuddy ? 0.66 : 1) * (index == 1 ? 1 - wink : 1))
                let frame = CGRect(x: centerX - width / 2 + gaze.width, y: 48 - height / 2 + gaze.height, width: width, height: height)
                var eye = context
                eye.translateBy(x: frame.midX, y: frame.midY)
                eye.rotate(by: .degrees(Double(tilt) * (index == 0 ? 1 : -1)))
                eye.translateBy(x: -frame.midX, y: -frame.midY)
                if avatar == .coastBuddy {
                    let relaxed = max(0, 1 - joy / 0.3) * max(0, 1 - wink / 0.4)
                    eye.clip(to: Path(CGRect(x: frame.minX - 1, y: frame.minY + height * 0.18 * relaxed, width: frame.width + 2, height: height)))
                }
                let lightEyes = avatar == .crtBuddy || avatar == .inkBuddy || (avatar == .minimalSpirit && colorScheme == .dark)
                let bottom: Color = avatar == .crtBuddy ? Color(red: 0.43, green: 0.85, blue: 0.73) : lightEyes ? Color(white: 0.91) : Color(red: 0.06, green: 0.08, blue: 0.08)
                eye.fill(Self.eyePath(in: frame, joy: joy, pixel: pixel), with: .linearGradient(Gradient(colors: [eyeColor, bottom]), startPoint: CGPoint(x: frame.minX, y: frame.minY), endPoint: CGPoint(x: frame.maxX, y: frame.maxY)))
            }
            if avatar == .minimalSpirit {
                var mouth = Path()
                mouth.move(to: CGPoint(x: 43 + gaze.width * 0.4, y: 70 + gaze.height * 0.4))
                mouth.addQuadCurve(to: CGPoint(x: 53 + gaze.width * 0.4, y: 70 + gaze.height * 0.4), control: CGPoint(x: 48, y: 76 + joy * 2))
                context.stroke(mouth, with: .color(eyeColor), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            }
        }
    }

    // Draw light on the native paths at the final display size. Clipped edge
    // shading gives a matte rounded surface without enlarging a small canvas.
    private func fillShell(_ path: Path, in context: GraphicsContext, colors: [Color], shadow: CGFloat = 1.2) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.10), radius: shadow, x: 0.4, y: 1.4))
            layer.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 20 + gaze.width, y: 15 + gaze.height), endPoint: CGPoint(x: 76, y: 85)))
        }
        context.fill(path, with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.06), .clear]), center: CGPoint(x: 29 + gaze.width * 0.5, y: 21 + gaze.height * 0.5), startRadius: 0, endRadius: 67))
        var edge = context
        edge.clip(to: path)
        edge.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.25), .clear, .black.opacity(0.18)]), startPoint: CGPoint(x: 22, y: 15), endPoint: CGPoint(x: 70, y: 83)), lineWidth: 1.3)
        edge.fill(path, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.06), location: 1)]), startPoint: CGPoint(x: 48, y: 15), endPoint: CGPoint(x: 48, y: 81)))
    }

    private func drawBody(in context: GraphicsContext) {
        switch avatar {
        case .crtBuddy:
            let shell = Path(roundedRect: CGRect(x: 12, y: 15, width: 72, height: 66), cornerRadius: 21)
            fillShell(shell, in: context, colors: [Color(red: 0.81, green: 0.71, blue: 1), Color(red: 0.72, green: 0.59, blue: 0.92)])
            let visor = Path(roundedRect: CGRect(x: 20, y: 23, width: 56, height: 50), cornerRadius: 17)
            context.fill(visor, with: .linearGradient(Gradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.10), Color(red: 0.11, green: 0.13, blue: 0.13), Color(red: 0.045, green: 0.06, blue: 0.06)]), startPoint: CGPoint(x: 28, y: 25), endPoint: CGPoint(x: 68, y: 71)))
            context.stroke(visor, with: .linearGradient(Gradient(colors: [.black.opacity(0.32), .white.opacity(0.18)]), startPoint: CGPoint(x: 48, y: 23), endPoint: CGPoint(x: 48, y: 73)), lineWidth: 0.8)
        case .arcade1984:
            let points: [CGPoint] = [(30,14),(66,14),(66,22),(77,22),(77,33),(84,33),(84,66),(77,66),(77,78),(19,78),(19,66),(12,66),(12,33),(19,33),(19,22),(30,22)].map { CGPoint(x: $0.0, y: $0.1) }
            let shell = Self.roundedPolygon(points, radius: 1.5)
            fillShell(shell, in: context, colors: [Color(red: 1, green: 0.82, blue: 0.43), Color(red: 0.99, green: 0.74, blue: 0.29)], shadow: 0.65)
        case .minimalSpirit: break
        case .coastBuddy:
            var pebble = Path()
            pebble.move(to: CGPoint(x: 10, y: 55))
            pebble.addCurve(to: CGPoint(x: 48, y: 22), control1: CGPoint(x: 10, y: 35), control2: CGPoint(x: 28, y: 22))
            pebble.addCurve(to: CGPoint(x: 86, y: 55), control1: CGPoint(x: 68, y: 22), control2: CGPoint(x: 86, y: 35))
            pebble.addCurve(to: CGPoint(x: 48, y: 76), control1: CGPoint(x: 86, y: 73), control2: CGPoint(x: 70, y: 76))
            pebble.addCurve(to: CGPoint(x: 10, y: 55), control1: CGPoint(x: 26, y: 76), control2: CGPoint(x: 10, y: 73))
            fillShell(pebble, in: context, colors: [Color(red: 0.57, green: 0.87, blue: 0.81), Color(red: 0.40, green: 0.75, blue: 0.67)])
            var curl = Path(); curl.move(to: CGPoint(x: 42, y: 19))
            curl.addCurve(to: CGPoint(x: 62, y: 10), control1: CGPoint(x: 53, y: 17), control2: CGPoint(x: 59, y: 18))
            context.stroke(curl, with: .linearGradient(Gradient(colors: [Color(red: 0.28, green: 0.72, blue: 0.63), Color(red: 0.19, green: 0.64, blue: 0.55)]), startPoint: CGPoint(x: 42, y: 19), endPoint: CGPoint(x: 62, y: 10)), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
        case .paperPal:
            var folded = Path()
            folded.move(to: CGPoint(x: 44, y: 13))
            folded.addCurve(to: CGPoint(x: 55, y: 16), control1: CGPoint(x: 49, y: 12), control2: CGPoint(x: 52, y: 13))
            folded.addLine(to: CGPoint(x: 83, y: 42))
            folded.addQuadCurve(to: CGPoint(x: 83, y: 54), control: CGPoint(x: 90, y: 48))
            folded.addLine(to: CGPoint(x: 53, y: 81))
            folded.addQuadCurve(to: CGPoint(x: 38, y: 81), control: CGPoint(x: 46, y: 88))
            folded.addLine(to: CGPoint(x: 13, y: 54))
            folded.addQuadCurve(to: CGPoint(x: 13, y: 42), control: CGPoint(x: 7, y: 48))
            folded.addLine(to: CGPoint(x: 38, y: 17)); folded.addQuadCurve(to: CGPoint(x: 44, y: 13), control: CGPoint(x: 41, y: 13))
            folded.closeSubpath()
            fillShell(folded, in: context, colors: [Color(red: 1, green: 0.65, blue: 0.56), Color(red: 1, green: 0.54, blue: 0.46)])
            var front = Path()
            front.move(to: CGPoint(x: 44, y: 13))
            front.addCurve(to: CGPoint(x: 50, y: 18), control1: CGPoint(x: 47, y: 13), control2: CGPoint(x: 49, y: 15))
            front.addCurve(to: CGPoint(x: 70, y: 43), control1: CGPoint(x: 56, y: 29), control2: CGPoint(x: 63, y: 35))
            front.addCurve(to: CGPoint(x: 70, y: 57), control1: CGPoint(x: 75, y: 49), control2: CGPoint(x: 75, y: 52))
            front.addLine(to: CGPoint(x: 51, y: 80))
            front.addQuadCurve(to: CGPoint(x: 38, y: 81), control: CGPoint(x: 44, y: 88))
            front.addLine(to: CGPoint(x: 13, y: 54))
            front.addQuadCurve(to: CGPoint(x: 13, y: 42), control: CGPoint(x: 7, y: 48))
            front.addLine(to: CGPoint(x: 38, y: 17)); front.addQuadCurve(to: CGPoint(x: 44, y: 13), control: CGPoint(x: 41, y: 13))
            front.closeSubpath()
            fillShell(front, in: context, colors: [Color(red: 1, green: 0.97, blue: 0.90), Color(red: 0.97, green: 0.88, blue: 0.76)], shadow: 0.8)
            var foldEdge = Path()
            foldEdge.move(to: CGPoint(x: 50, y: 18))
            foldEdge.addCurve(to: CGPoint(x: 70, y: 43), control1: CGPoint(x: 56, y: 29), control2: CGPoint(x: 63, y: 35))
            foldEdge.addCurve(to: CGPoint(x: 70, y: 57), control1: CGPoint(x: 75, y: 49), control2: CGPoint(x: 75, y: 52))
            context.stroke(foldEdge, with: .linearGradient(Gradient(colors: [.white.opacity(0.28), Color(red: 0.67, green: 0.37, blue: 0.29).opacity(0.13)]), startPoint: CGPoint(x: 50, y: 18), endPoint: CGPoint(x: 70, y: 57)), lineWidth: 0.75)
        case .inkBuddy:
            let shell = Path(roundedRect: CGRect(x: 8, y: 25, width: 80, height: 46), cornerRadius: 20)
            fillShell(shell, in: context, colors: [Color(red: 0.16, green: 0.18, blue: 0.18), Color(red: 0.065, green: 0.08, blue: 0.08)])
        }
    }

    private static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        for index in points.indices {
            let point = points[index], previous = points[(index + points.count - 1) % points.count], next = points[(index + 1) % points.count]
            func approach(_ neighbor: CGPoint) -> CGPoint {
                let x = neighbor.x - point.x, y = neighbor.y - point.y, distance = sqrt(x * x + y * y)
                let fraction = min(radius / distance, 0.5)
                return CGPoint(x: point.x + x * fraction, y: point.y + y * fraction)
            }
            let entry = approach(previous), exit = approach(next)
            if index == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
            path.addQuadCurve(to: exit, control: point)
        }
        path.closeSubpath(); return path
    }

    // Four cubic segments keep one topology from a dot to a smiling arch.
    private static func eyePath(in rect: CGRect, joy: CGFloat, pixel: Bool) -> Path {
        let j = min(1, max(0, joy)), w = rect.width, h = rect.height
        if pixel {
            let step = w / 4
            var p = Path()
            for column in 0..<4 {
                let raised = column == 1 || column == 2
                p.addRect(CGRect(x: rect.minX + CGFloat(column) * step, y: rect.minY + (raised ? 0 : h * 0.3 * j), width: step + 0.05, height: max(1.8, h * (1 - j * 0.72))))
            }
            return p
        }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        func mix(_ normal: (CGFloat, CGFloat), _ happy: (CGFloat, CGFloat)) -> CGPoint {
            point(normal.0 + (happy.0 - normal.0) * j, normal.1 + (happy.1 - normal.1) * j)
        }
        let k: CGFloat = pixel ? 0 : 0.224
        var p = Path()
        p.move(to: mix((0,0.5),(0,0.8)))
        p.addCurve(to: mix((0.5,0),(0.5,0.15)), control1: mix((0,k),(0,0.48)), control2: mix((k,0),(0.22,0.15)))
        p.addCurve(to: mix((1,0.5),(1,0.8)), control1: mix((1-k,0),(0.78,0.15)), control2: mix((1,k),(1,0.48)))
        p.addCurve(to: mix((0.5,1),(0.5,0.4)), control1: mix((1,1-k),(1,0.98)), control2: mix((1-k,1),(0.80,0.4)))
        p.addCurve(to: mix((0,0.5),(0,0.8)), control1: mix((k,1),(0.20,0.4)), control2: mix((0,1-k),(0,0.98)))
        p.closeSubpath(); return p
    }
}

@MainActor enum CompanionArtwork {
    private static var menuImages: [CompanionAvatar: NSImage] = [:]
    static func menuBarImage(for avatar: CompanionAvatar) -> NSImage? {
        if let cached = menuImages[avatar] { return cached }
        let renderer = ImageRenderer(content: CompanionFace(renderSize: 22, avatar: avatar).environment(\.colorScheme, avatar == .minimalSpirit ? .light : .dark))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: 22, height: 22))
        image.isTemplate = avatar == .minimalSpirit
        menuImages[avatar] = image; return image
    }
}

struct CompanionCharacter: View {
    var size: CGFloat = 42
    var avatar: CompanionAvatar = .crtBuddy
    var animates = true
    var focusing = false
    var joyful = false
    var listening = false
    var voicePhase: CompanionVoicePhase = .inactive
    var gaze = CGSize.zero
    var mood: CompanionMood = .idle
    var strolling = false
    // Deterministic offscreen previews use this without starting an app window.
    var previewTime: Double? = nil
    var entrance: CompanionEntranceMotion? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var voiceAnimator = CompanionVoiceAnimator()
    private var effectiveVoicePhase: CompanionVoicePhase {
        if voicePhase != .inactive { return voicePhase }
        if listening { return .listening }
        return mood == .understood || mood == .celebrating ? .success : .inactive
    }

    var body: some View {
        let moves = animates && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !moves || previewTime != nil)) { context in
            let reaction = effectiveVoicePhase == .failure ? .startled : effectiveVoicePhase != .inactive ? .idle : joyful || entrance?.joy == true ? .happy : mood
            let time = previewTime ?? context.date.timeIntervalSinceReferenceDate
            let voice = previewTime != nil ? CompanionVoiceMotion.sample(phase: effectiveVoicePhase, elapsed: time, size: size, avatar: avatar, animates: moves) : voiceAnimator.sample(at: time, size: size, avatar: avatar, animates: moves)
            let motion = CompanionMotion.sample(time: time, size: size, avatar: avatar, mood: effectiveVoicePhase == .inactive ? reaction : .idle, listening: false, strolling: strolling && effectiveVoicePhase == .inactive, animates: moves)
            CompanionFace(renderSize: size, avatar: avatar, focusing: focusing, joyful: joyful, gaze: moves ? CGSize(width: gaze.width + voice.gaze.width, height: gaze.height + voice.gaze.height) : .zero, eyeOpen: motion.eyeOpen * voice.eyeMultiplier * (entrance?.eyeOpen ?? 1),
                          listening: false, motionTime: time, mood: reaction, animates: moves, joyAmount: effectiveVoicePhase != .inactive || voice.joy > 0 ? voice.joy : nil, wink: voice.wink)
                .overlay(alignment: .trailing) {
                    if let entrance, entrance.wave > 0 {
                        Capsule().fill(avatar == .minimalSpirit || avatar == .inkBuddy ? Color.white : avatar.tint)
                            .frame(width: size * 0.12, height: size * 0.19)
                            .rotationEffect(.degrees(-28 + entrance.waveAngle), anchor: .bottom)
                            .offset(x: size * 0.06, y: -size * 0.05).opacity(entrance.wave)
                    }
                }
                .scaleEffect(x: motion.scaleX * voice.scaleX * (entrance?.scaleX ?? 1), y: motion.scaleY * voice.scaleY * (entrance?.scaleY ?? 1))
                .rotation3DEffect(.degrees(moves ? -gaze.height * 1.5 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                .rotation3DEffect(.degrees(moves ? gaze.width * 1.4 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                .rotationEffect(.degrees(motion.rotation + voice.rotation + (entrance?.rotation ?? 0)))
                .offset(x: motion.offset.width + voice.offset.width + (entrance?.offsetX ?? 0) * size, y: motion.offset.height + voice.offset.height + (entrance?.offset ?? 0) * size)
                .opacity(entrance?.opacity ?? 1)
                .frame(width: size, height: size)
                .overlay(alignment: .topLeading) {
                    if voice.loading > 0 {
                        CompanionLoadingBadge(avatar: avatar, time: moves ? time : 0)
                            .frame(width: max(8, size * 0.24), height: max(8, size * 0.24))
                            .offset(x: size * (avatar == .minimalSpirit ? 0.1 : 0.07), y: size * (avatar == .coastBuddy ? 0.04 : avatar == .inkBuddy ? 0.19 : 0.1))
                            .opacity(voice.loading)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if reaction == .asleep && size >= 42 {
                        let phase = moves ? (time + Double(CompanionAvatar.allCases.firstIndex(of: avatar) ?? 0) * 0.61).truncatingRemainder(dividingBy: 3) / 3 : 0.4
                        Text("z").font(.system(size: size * (0.12 + phase * 0.04), weight: .medium, design: .rounded)).foregroundStyle(avatar.tint)
                            .opacity(moves ? sin(phase * .pi) * 0.8 : 0.7)
                            .offset(x: size * phase * 0.08, y: -size * phase * 0.2)
                    }
                }
                .animation(moves ? .spring(response: 0.36, dampingFraction: 0.82) : nil, value: mood)
                .animation(moves ? .spring(response: 0.36, dampingFraction: 0.82) : nil, value: joyful)
                .accessibilityHidden(true)
        }.frame(width: size, height: size)
            .onAppear { voiceAnimator.transition(to: effectiveVoicePhase, at: Date.timeIntervalSinceReferenceDate, size: size, avatar: avatar, animates: moves) }
            .onChange(of: effectiveVoicePhase) { _, phase in
                voiceAnimator.transition(to: phase, at: Date.timeIntervalSinceReferenceDate, size: size, avatar: avatar, animates: moves)
            }
            .onChange(of: avatar) { _, _ in
                voiceAnimator = CompanionVoiceAnimator()
                voiceAnimator.transition(to: effectiveVoicePhase, at: Date.timeIntervalSinceReferenceDate, size: size, avatar: avatar, animates: moves)
            }
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


struct CompanionAvatarPicker: View {
    @Binding var selection: CompanionAvatar
    var animates: Bool
    var compact = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(CompanionAvatar.allCases) { avatar in
                CompanionInteraction(action: { selection = avatar }) {
                    VStack(spacing: 8) {
                        CompanionCharacter(size: compact ? 48 : 62, avatar: avatar, animates: animates && selection == avatar)
                            .padding(.top, 4)
                        Text(avatar.name).font(.callout.weight(.semibold)).foregroundStyle(CompanionStyle.ink).lineLimit(1).minimumScaleFactor(0.8)
                        if !compact { Text(avatar.subtitle).font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(1).minimumScaleFactor(0.8) }
                        Label(selection == avatar ? "Selected" : "Choose", systemImage: selection == avatar ? "checkmark.circle.fill" : "circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selection == avatar ? CompanionStyle.accentInk : CompanionStyle.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .modifier(WorkspaceSurface(selected: selection == avatar, radius: 18))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(avatar.name). \(avatar.detail)")
                .accessibilityValue(selection == avatar ? "Selected" : "")
                .accessibilityHint("Choose this companion")
            }
        }
    }
}
