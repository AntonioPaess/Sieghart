import SwiftUI

// Scripted preview states, independent of permissions and of the live app.
enum ConceptPhase: Int, CaseIterable {
    case arrival, idle, listening, thinking, success, sleeping
    var duration: Double { [1.8, 1.4, 2, 2, 2, 2.8][rawValue] }
    var title: String { ["CHEGADA", "EM REPOUSO", "ESCUTANDO", "PROCESSANDO", "ENTENDIDO", "DESCANSANDO"][rawValue] }
    var detail: String {
        ["Entrada com impulso, acomodação e primeiro olhar.",
         "Respiração e piscar. Nenhum indicador de tarefa.",
         "Olhar para os dois lados e uma inclinação atenta.",
         "Sinal ativo com a silhueta de cada companion.",
         "Seis pequenas reações, uma personalidade por avatar.",
         "Olhos fechados e respiração visível."][rawValue]
    }
    static func current(_ time: Double) -> (phase: ConceptPhase, local: Double) {
        var local = max(0, time).truncatingRemainder(dividingBy: 12)
        for phase in allCases {
            if local < phase.duration { return (phase, local) }
            local -= phase.duration
        }
        return (.arrival, 0)
    }
}

struct ConceptPose {
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var angle: Double = 0
    var y: CGFloat = 0
    var gaze = CGSize.zero
    var open: CGFloat = 1
    var joy: CGFloat = 0
    var wink: CGFloat = 0
    var opacity: Double = 1
    var badge: Double = 0

    func blended(to other: Self, amount: Double) -> Self {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * amount }
        var p = Self()
        p.sx = mix(sx, other.sx); p.sy = mix(sy, other.sy)
        p.angle = angle + (other.angle - angle) * amount
        p.y = mix(y, other.y); p.gaze = CGSize(width: mix(gaze.width, other.gaze.width), height: mix(gaze.height, other.gaze.height))
        p.open = mix(open, other.open); p.joy = mix(joy, other.joy); p.wink = mix(wink, other.wink)
        p.opacity = opacity + (other.opacity - opacity) * amount
        p.badge = badge + (other.badge - badge) * amount
        return p
    }
}

enum ConceptMotion {
    static func smooth(_ value: Double) -> Double {
        let x = min(1, max(0, value)); return x * x * (3 - 2 * x)
    }
    static func raw(avatar: StudyAvatar, phase: ConceptPhase, local t: Double, global: Double) -> ConceptPose {
        var p = ConceptPose()
        let index = StudyAvatar.allCases.firstIndex(of: avatar) ?? 0
        let rhythm = global * .pi * 2 / 3.4 + Double(index) * 0.3
        p.sx = 1 + sin(rhythm) * 0.005
        p.sy = 1 + sin(rhythm) * 0.012
        p.y = -sin(rhythm) * 0.6
        let blink = (global + Double(index) * 0.17).truncatingRemainder(dividingBy: 3.8)
        if blink > 3.3 && blink < 3.6 { p.open = 1 - sin((blink - 3.3) / 0.3 * .pi) * 0.96 }
        switch phase {
        case .arrival:
            let x = max(0, t - Double(index) * 0.07)
            let spring = 1 - exp(-6 * x) * cos(9 * x)
            p.sx = 0.6 + spring * 0.4
            p.sy = 0.52 + spring * 0.48
            p.y = 38 * (1 - spring)
            p.angle = avatar == .ada ? 0 : (1 - spring) * (index.isMultiple(of: 2) ? -11 : 11)
            p.opacity = smooth(x / 0.25)
            p.open = smooth(x / 0.6)
            p.gaze.width = sin(x * 3) * exp(-x) * 2
        case .idle:
            p.gaze.width = sin(t * 2.5 + Double(index) * 0.3) * 1.2
        case .listening:
            let listen = smooth(t / 0.25)
            // Travels through both signs, rather than tracking only to the right.
            p.gaze = CGSize(width: sin(t * .pi * 1.15) * 3.5 * listen, height: -0.6 * listen)
            p.angle = avatar == .ada ? 0 : sin(t * .pi * 1.15) * 3.0 * listen
            p.open = min(1.1, p.open * 1.07)
            p.sy += sin(t * 8) * 0.006
        case .thinking:
            p.badge = smooth(t / 0.2)
            p.gaze = CGSize(width: sin(t * 2.6) * 2.2, height: -1.8)
            p.angle = avatar == .ada ? 0 : sin(t * 2.6) * 2.3
            p.open *= 0.87
            p.y -= sin(t * 3.1) * 0.9
        case .success:
            let x = min(1, t / 1.25)
            let pulse = pow(sin(x * .pi), 2)
            let nod = sin(x * .pi * 2) * (1 - x)
            p.joy = smooth(t / 0.25) * (1 - smooth((t - 1.35) / 0.45)) * 0.75
            switch avatar {
            case .sig:
                p.sx += pulse * 0.035; p.sy -= pulse * 0.035
                p.wink = pulse * 0.95; p.joy *= 0.55; p.angle = nod * 3
            case .rita:
                p.angle = nod * 5; p.y += pulse * 1.5; p.joy *= 0.8
            case .ada:
                p.y -= pulse * 5; p.sx += pulse * 0.018; p.sy -= pulse * 0.018
            case .gantt:
                p.angle = nod * 4; p.y -= pulse * 2; p.sx += pulse * 0.02
            case .elinor:
                p.sx += pulse * 0.03; p.sy -= pulse * 0.025; p.y -= pulse * 2
            case .toni:
                p.angle = sin(x * .pi * 3) * (1 - x) * 4; p.y -= pulse * 2
                p.wink = pulse * 0.8; p.joy *= 0.6
            }
        case .sleeping:
            let settle = smooth(t / 0.35)
            let breath = sin(t * .pi * 2 / 2.7)
            p.open = 1 - settle * 0.94
            p.sx = 1 + breath * 0.012; p.sy = 1 + breath * 0.03
            p.y = -breath * 1.9; p.angle = avatar == .ada ? 0 : settle * -2 + breath * 1.2
            p.gaze.height = settle * 1.5
        }
        return p
    }
    static func pose(avatar: StudyAvatar, time: Double) -> ConceptPose {
        let current = ConceptPhase.current(time)
        let p = raw(avatar: avatar, phase: current.phase, local: current.local, global: time)
        // A short blend preserves a continuous contour at activity boundaries.
        guard current.phase != .sleeping, current.phase != .arrival else { return p }
        let blend = smooth((current.local - current.phase.duration + 0.24) / 0.24)
        let next = ConceptPhase(rawValue: current.phase.rawValue + 1)!
        return p.blended(to: raw(avatar: avatar, phase: next, local: 0, global: time), amount: blend)
    }
}

struct ConceptBadgeShape: Shape {
    var avatar: StudyAvatar
    func path(in rect: CGRect) -> Path {
        switch avatar {
        case .ada:
            let points: [(CGFloat, CGFloat)] = [(0.25,0),(0.75,0),(0.75,0.125),(0.875,0.125),(0.875,0.25),(1,0.25),(1,0.75),(0.875,0.75),(0.875,0.875),(0.75,0.875),(0.75,1),(0.25,1),(0.25,0.875),(0.125,0.875),(0.125,0.75),(0,0.75),(0,0.25),(0.125,0.25),(0.125,0.125),(0.25,0.125)]
            var p = Path()
            for (i, point) in points.enumerated() {
                let v = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
                if i == 0 { p.move(to: v) } else { p.addLine(to: v) }
            }
            p.closeSubpath(); return p
        case .toni:
            var p = Path(); p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.midY)); p.closeSubpath(); return p
        case .sig:
            return Path(roundedRect: rect.insetBy(dx: 0, dy: rect.height * 0.15), cornerRadius: rect.width * 0.32)
        case .gantt:
            return Path(roundedRect: rect, cornerRadius: rect.width * 0.22)
        case .rita, .elinor:
            return Path(roundedRect: rect, cornerRadius: rect.width * 0.4)
        }
    }
}

struct ConceptBadge: View {
    var avatar: StudyAvatar
    var time: Double
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let outer = ConceptBadgeShape(avatar: avatar).path(in: rect)
            let inner = ConceptBadgeShape(avatar: avatar).path(in: rect.insetBy(dx: 4, dy: 4))
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.14), radius: 1.4, y: 1))
                layer.fill(outer, with: .linearGradient(Gradient(colors: [avatar.tint, avatar.tint.opacity(0.92)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            }
            let ink = Color(red: 0.16, green: 0.20, blue: 0.18)
            let stroke = StrokeStyle(lineWidth: 1.7, lineCap: avatar == .ada ? .square : .round, lineJoin: avatar == .ada ? .miter : .round)
            context.stroke(inner, with: .color(ink.opacity(0.13)), style: stroke)
            let start = time.truncatingRemainder(dividingBy: 1.7) / 1.7
            let end = start + 0.28
            context.stroke(inner.trimmedPath(from: start, to: min(1, end)), with: .color(ink.opacity(0.8)), style: stroke)
            if end > 1 { context.stroke(inner.trimmedPath(from: 0, to: end - 1), with: .color(ink.opacity(0.8)), style: stroke) }
        }
    }
}

struct ConceptCharacter: View {
    var avatar: StudyAvatar
    var time: Double
    var size: CGFloat = 170
    var body: some View {
        let p = ConceptMotion.pose(avatar: avatar, time: time)
        ZStack(alignment: .topLeading) {
            Ellipse().fill(.black.opacity(0.065))
                .frame(width: size * 0.53, height: size * 0.045)
                .blur(radius: 4)
                .scaleEffect(x: p.sx, y: 1)
                .offset(x: size * 0.235, y: size * 0.83)
                .opacity(p.opacity)
            StudyFace(avatar: avatar, openness: p.open, joy: p.joy, tilt: 0, gaze: p.gaze, wink: p.wink)
                .scaleEffect(x: p.sx, y: p.sy)
                .rotationEffect(.degrees(p.angle))
                .offset(y: p.y * size / 96)
                .opacity(p.opacity)
            ConceptBadge(avatar: avatar, time: time)
                .frame(width: size * 0.23, height: size * 0.23)
                .offset(x: size * 0.02, y: size * (avatar == .sig ? 0.20 : 0.10))
                .opacity(p.badge)
        }.frame(width: size, height: size)
    }
}
