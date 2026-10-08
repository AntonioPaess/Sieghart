import SwiftUI

// Preview-only choreography, deliberately independent of the app lifecycle.
enum StudyPhase: Int, CaseIterable {
    case listening, thinking, success
    var title: String {
        switch self {
        case .listening: "ESCUTANDO"
        case .thinking: "PENSANDO / CARREGANDO"
        case .success: "CONCLUÍDO"
        }
    }
    var detail: String {
        switch self {
        case .listening: "Olhar atento · inclinação suave"
        case .thinking: "Indicador no canto · mesma silhueta"
        case .success: "Uma reação curta · personalidade própria"
        }
    }
}

struct StudyPose {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation = 0.0
    var lift: CGFloat = 0
    var gaze = CGSize.zero
    var open: CGFloat = 1
    var joy: CGFloat = 0
    var wink: CGFloat = 0
}

enum StudyMotion {
    static func pose(avatar: StudyAvatar, phase: StudyPhase, time: Double) -> StudyPose {
        var result = StudyPose()
        let t = max(0, time)
        let w = Double.pi * 2 / 4
        let breath = sin(t * w) * 0.014
        result.scaleX = 1 + breath * 0.5
        result.scaleY = 1 + breath
        result.lift = -sin(t * w) * 0.8
        let blink = t.truncatingRemainder(dividingBy: 4)
        if blink > 3.52 && blink < 3.80 { result.open = 1 - sin((blink - 3.52) / 0.28 * .pi) * 0.95 }
        switch phase {
        case .listening:
            result.rotation = avatar == .arcade1984 ? 0 : -2.5 + sin(t * w) * 1.6
            result.gaze = CGSize(width: sin(t * w) * 0.9, height: -0.4)
            result.open *= avatar == .coastBuddy ? 1.0 : 1.06
            if avatar == .coastBuddy { result.joy = 0.12 }
        case .thinking:
            result.rotation = avatar == .arcade1984 ? 0 : sin(t * w) * (avatar == .coastBuddy ? 1.6 : 2.4)
            result.gaze = CGSize(width: sin(t * w) * 2.8, height: -1.7)
            result.open *= 0.90
            result.lift *= 1.8
            if avatar == .coastBuddy { result.joy = 0.18 }
        case .success:
            // One acknowledgement, then a calm happy hold. This board repeats
            // the gesture for review; a future runtime trigger would play once.
            let p = min(1, t / 1.05)
            let bump = sin(p * .pi)
            let nod = sin(p * .pi * 2) * (1 - p)
            result.joy = min(1, max(0, sin(p * .pi * 0.7))) * (avatar == .coastBuddy ? 0.65 : 1)
            switch avatar {
            case .crtBuddy:
                result.scaleX = 1 + bump * 0.035
                result.scaleY = 1 - bump * 0.025
                result.rotation = nod * 4
                result.lift = -bump * 2
            case .arcade1984:
                result.lift = -bump * 4
                result.scaleX = 1 + bump * 0.025
                result.scaleY = 1 - bump * 0.025
            case .minimalSpirit:
                result.rotation = nod * 4
                result.lift = -bump * 1.5
            case .coastBuddy:
                result.rotation = nod * 5
                result.lift = bump * 2
                result.gaze.width = bump * 0.7
                result.joy = bump * 0.35
                result.wink = bump * 0.92
            case .paperPal:
                result.rotation = sin(p * .pi * 3) * (1 - p) * 5
                result.scaleX = 1 + bump * 0.018
                result.lift = -bump * 2.5
            case .inkBuddy:
                result.scaleX = 1 + bump * 0.045
                result.scaleY = 1 - bump * 0.05
                result.rotation = nod * 3
                result.wink = bump * 0.92
                result.joy = bump * 0.45
            }
        }
        return result
    }
}

struct StudyBadgeShape: Shape {
    var avatar: StudyAvatar
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

struct StudyBadge: View {
    var avatar: StudyAvatar
    var time: Double
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let shape = StudyBadgeShape(avatar: avatar).path(in: rect)
            let inner = StudyBadgeShape(avatar: avatar).path(in: rect.insetBy(dx: 4.0, dy: 4.0))
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.16), radius: 1.5, y: 1))
                layer.fill(shape, with: .linearGradient(Gradient(colors: [avatar.tint, avatar.tint.opacity(0.95)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)))
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

struct StudyCharacter: View {
    var avatar: StudyAvatar
    var phase: StudyPhase
    var time: Double
    var size: CGFloat = 112
    var body: some View {
        let pose = StudyMotion.pose(avatar: avatar, phase: phase, time: time)
        ZStack(alignment: .topLeading) {
            StudyFace(avatar: avatar, openness: pose.open, joy: pose.joy, tilt: 0, gaze: pose.gaze, wink: pose.wink)
                .scaleEffect(x: pose.scaleX, y: pose.scaleY)
                .rotationEffect(.degrees(pose.rotation))
                .offset(y: pose.lift)
            if phase == .thinking {
                StudyBadge(avatar: avatar, time: time)
                    .frame(width: size * 0.24, height: size * 0.24)
                    .offset(x: size * (avatar == .minimalSpirit ? 0.1 : 0.07), y: size * (avatar == .coastBuddy ? 0.04 : avatar == .inkBuddy ? 0.19 : 0.1))
            }
        }.frame(width: size, height: size)
    }
}
