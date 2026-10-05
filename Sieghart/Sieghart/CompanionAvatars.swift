import SwiftUI

// Stable identifiers keep the selection independent of display names.
enum CompanionAvatar: String, CaseIterable, Identifiable {
    case crtBuddy = "crt-buddy"
    case arcade1984 = "arcade-1984"
    case minimalSpirit = "minimal-spirit"
    case softOrbit = "soft-orbit"
    case paperPal = "paper-pal"
    case starSprout = "star-sprout"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .crtBuddy: "CRT Buddy"
        case .arcade1984: "Arcade 1984"
        case .minimalSpirit: "Minimal Spirit"
        case .softOrbit: "Soft Orbit"
        case .paperPal: "Paper Pal"
        case .starSprout: "Star Sprout"
        }
    }
    var subtitle: String {
        switch self {
        case .crtBuddy: "Phosphor soul"
        case .arcade1984: "Pixel nostalgia"
        case .minimalSpirit: "Less, with feeling"
        case .softOrbit: "A little universe"
        case .paperPal: "Folded with care"
        case .starSprout: "A spark of joy"
        }
    }
    var detail: String {
        switch self {
        case .crtBuddy: "A pocket CRT with mint eyes and a warm arcade glow."
        case .arcade1984: "An amber pixel friend with a green screen and victory hops."
        case .minimalSpirit: "Just a face, a soft blink, and a little personality."
        case .softOrbit: "A pearl of light with a slowly moving orbit."
        case .paperPal: "A friendly paper creature with expressive folded ears."
        case .starSprout: "A tiny golden star with a mint sprout and a cheerful sway."
        }
    }
    var tint: Color {
        switch self {
        case .crtBuddy, .minimalSpirit, .softOrbit: CompanionStyle.accent
        case .arcade1984, .starSprout: Color(red: 1, green: 0.80, blue: 0.43)
        case .paperPal: Color(red: 1, green: 0.62, blue: 0.48)
        }
    }
}

// Every character is local vector artwork. The same expression parameters
// drive the full-size companion, voice state, celebration, and tiny island.
struct CompanionFace: View, Animatable {
    var avatar: CompanionAvatar
    var eyeOpen: CGFloat
    var smile: CGFloat
    var brow: CGFloat
    var gaze: CGSize
    var listening: Bool
    var motionTime: Double

    init(avatar: CompanionAvatar = .crtBuddy, blinking: Bool = false, focusing: Bool = false, joyful: Bool = false, gaze: CGSize = .zero, eyeOpen: CGFloat? = nil, listening: Bool = false, motionTime: Double = 0) {
        self.avatar = avatar
        self.eyeOpen = eyeOpen ?? (blinking ? 0.08 : 1)
        self.smile = joyful ? 1 : focusing ? 0.25 : 0.55
        self.brow = focusing ? 1 : 0
        self.gaze = gaze
        self.listening = listening
        self.motionTime = motionTime
    }

    nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(eyeOpen, AnimatablePair(smile, brow)) }
        set { eyeOpen = newValue.first; smile = newValue.second.first; brow = newValue.second.second }
    }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 96, y: size.height / 96)
            switch avatar {
            case .crtBuddy: drawCRT(in: context)
            case .arcade1984: drawArcade(in: context)
            case .minimalSpirit: drawMinimal(in: context)
            case .softOrbit: drawOrbit(in: context)
            case .paperPal: drawPaper(in: context)
            case .starSprout: drawStar(in: context)
            }
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }

    private var mint: Color { Color(red: 0.58, green: 1, blue: 0.83) }
    private var pink: Color { Color(red: 1, green: 0.52, blue: 0.73) }
    private var amber: Color { Color(red: 1, green: 0.80, blue: 0.43) }
    private var ink: Color { Color(red: 0.15, green: 0.13, blue: 0.23) }
    private var cream: Color { Color(red: 1, green: 0.94, blue: 0.83) }

    private func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat = 0) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
    }
    private func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func drawExpression(in context: GraphicsContext, color: Color, eyeY: CGFloat = 47, eyeWidth: CGFloat = 10, eyeHeight: CGFloat = 16, mouthY: CGFloat = 59, pixel: Bool = false, brows: Bool = true, glow: Bool = false) {
        let height = pixel ? max(3, (eyeHeight * eyeOpen / 3).rounded() * 3) : max(2, eyeHeight * eyeOpen)
        let dx = pixel ? (gaze.width / 2).rounded() * 2 : gaze.width
        let dy = pixel ? (gaze.height / 2).rounded() * 2 : gaze.height
        for x: CGFloat in [33 - eyeWidth / 2, 62 - eyeWidth / 2] {
            let eye = rect(x + dx, eyeY - height / 2 + dy, eyeWidth, height, radius: pixel ? 0 : eyeWidth / 2)
            var eyes = context
            if glow { eyes.addFilter(.shadow(color: color.opacity(0.5), radius: 3)) }
            eyes.fill(eye, with: .color(color))
            if brows {
                let eyebrow = line([CGPoint(x: x - 1, y: eyeY - eyeHeight / 2 - 5 + brow * (x < 40 ? 0 : 2)), CGPoint(x: x + eyeWidth, y: eyeY - eyeHeight / 2 - 6 + brow * (x < 40 ? 2 : 0))])
                context.stroke(eyebrow, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: pixel ? .butt : .round))
            }
        }
        if listening {
            context.stroke(Path(ellipseIn: CGRect(x: 44, y: mouthY - 1, width: 8, height: 9)), with: .color(color), lineWidth: 2.5)
        } else if pixel {
            let depth = smile > 0.7 ? CGFloat(7) : smile > 0.4 ? 4 : 1
            let mouth = line([CGPoint(x: 36, y: mouthY), CGPoint(x: 36, y: mouthY + depth), CGPoint(x: 59, y: mouthY + depth), CGPoint(x: 59, y: mouthY)])
            context.stroke(mouth, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .square))
        } else {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 39, y: mouthY))
            mouth.addQuadCurve(to: CGPoint(x: 57, y: mouthY), control: CGPoint(x: 48, y: mouthY + 1 + smile * 10))
            context.stroke(mouth, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    private func drawCRT(in context: GraphicsContext) {
        let shell = rect(7, 19, 82, 65, radius: 20)
        context.fill(shell, with: .color(Color(red: 0.17, green: 0.15, blue: 0.25)))
        context.stroke(shell, with: .color(CompanionStyle.accent), lineWidth: 3)
        context.stroke(line([CGPoint(x: 48, y: 18), CGPoint(x: 48, y: 10), CGPoint(x: 55, y: 6)]), with: .color(CompanionStyle.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        context.fill(Path(ellipseIn: CGRect(x: 52, y: 2, width: 8, height: 8)), with: .color(listening ? amber : mint))
        for x: CGFloat in [1, 89] { context.fill(rect(x, 43, 6, 18, radius: 3), with: .color(pink)) }
        let screen = rect(15, 28, 66, 43, radius: 14)
        context.fill(screen, with: .color(Color(red: 0.025, green: 0.08, blue: 0.09)))
        context.stroke(screen, with: .color(mint.opacity(0.25)), lineWidth: 1)
        for y in stride(from: 33, through: 65, by: 5) {
            context.stroke(line([CGPoint(x: 22, y: y), CGPoint(x: 74, y: y)]), with: .color(mint.opacity(0.055)), lineWidth: 1)
        }
        drawExpression(in: context, color: mint, glow: true)
        for x: CGFloat in [24, 67] { context.fill(rect(x, 59, 5, 2, radius: 1), with: .color(pink.opacity(0.7))) }
        for x: CGFloat in [32, 40, 48] { context.fill(rect(x, 76, 4, 2, radius: 1), with: .color(CompanionStyle.accent.opacity(0.65))) }
        context.fill(Path(ellipseIn: CGRect(x: 64, y: 74, width: 5, height: 5)), with: .color(amber))
        for x: CGFloat in [26, 59] { context.fill(rect(x, 84, 11, 5, radius: 2), with: .color(CompanionStyle.accent)) }
    }

    private func drawArcade(in context: GraphicsContext) {
        let shell = polygon([CGPoint(x: 18, y: 19), CGPoint(x: 78, y: 19), CGPoint(x: 78, y: 25), CGPoint(x: 84, y: 25), CGPoint(x: 84, y: 77), CGPoint(x: 78, y: 77), CGPoint(x: 78, y: 83), CGPoint(x: 18, y: 83), CGPoint(x: 18, y: 77), CGPoint(x: 12, y: 77), CGPoint(x: 12, y: 25), CGPoint(x: 18, y: 25)])
        context.fill(shell, with: .color(amber))
        context.fill(rect(22, 28, 52, 43), with: .color(Color(red: 0.06, green: 0.17, blue: 0.13)))
        context.fill(rect(25, 31, 46, 37), with: .color(mint.opacity(0.06)))
        for x: CGFloat in [3, 84] { context.fill(rect(x, 43, 9, 23), with: .color(pink)) }
        context.fill(rect(45, 10, 6, 10), with: .color(amber))
        context.fill(rect(45, 4, 12, 6), with: .color(listening ? mint : pink))
        drawExpression(in: context, color: mint, eyeY: 45, eyeWidth: 9, eyeHeight: 15, mouthY: 57, pixel: true)
        context.fill(rect(26, 76, 15, 3), with: .color(ink.opacity(0.6)))
        context.fill(rect(65, 75, 5, 5), with: .color(pink))
        for x: CGFloat in [21, 63] { context.fill(rect(x, 83, 12, 8), with: .color(amber)) }
    }

    private func drawMinimal(in context: GraphicsContext) {
        drawExpression(in: context, color: listening ? mint : CompanionStyle.accent, eyeY: 44, eyeWidth: 13, eyeHeight: 23, mouthY: 64)
        for x: CGFloat in [19, 73] { context.fill(rect(x, 58, 5, 2, radius: 1), with: .color(pink.opacity(0.6))) }
    }

    private func drawOrbit(in context: GraphicsContext) {
        let orb = Path(ellipseIn: CGRect(x: 16, y: 16, width: 64, height: 64))
        context.fill(orb, with: .linearGradient(Gradient(colors: [cream, mint, CompanionStyle.accent, pink.opacity(0.9)]), startPoint: CGPoint(x: 25, y: 15), endPoint: CGPoint(x: 74, y: 83)))
        context.stroke(orb, with: .color(.white.opacity(0.55)), lineWidth: 1.5)
        context.fill(Path(ellipseIn: CGRect(x: 26, y: 22, width: 24, height: 12)), with: .color(.white.opacity(0.3)))
        var orbit = context
        orbit.translateBy(x: 48, y: 48)
        orbit.rotate(by: .degrees(-24 + sin(motionTime * 0.65) * 8))
        orbit.stroke(Path(ellipseIn: CGRect(x: -44, y: -19, width: 88, height: 38)), with: .color(CompanionStyle.accent.opacity(0.8)), lineWidth: 2.5)
        let phase = motionTime * 0.65 + 0.5
        let satellite = CGRect(x: cos(phase) * 44 - 4, y: sin(phase) * 19 - 4, width: 8, height: 8)
        orbit.fill(Path(ellipseIn: satellite), with: .color(listening ? mint : amber))
        drawExpression(in: context, color: ink, eyeY: 46, eyeWidth: 8, eyeHeight: 13, mouthY: 58, brows: false)
        for x: CGFloat in [24, 66] { context.fill(Path(ellipseIn: CGRect(x: x, y: 56, width: 6, height: 4)), with: .color(pink.opacity(0.7))) }
    }

    private func drawPaper(in context: GraphicsContext) {
        let coral = CompanionAvatar.paperPal.tint
        let fold = sin(motionTime * 1.4) * (smile > 0.7 ? 5 : 2)
        let leftEar = polygon([CGPoint(x: 14, y: 13 + fold), CGPoint(x: 40, y: 28), CGPoint(x: 19, y: 42)])
        let rightEar = polygon([CGPoint(x: 82, y: 13 - fold), CGPoint(x: 56, y: 28), CGPoint(x: 77, y: 42)])
        context.fill(leftEar, with: .color(cream)); context.fill(rightEar, with: .color(cream))
        context.fill(polygon([CGPoint(x: 19, y: 21 + fold), CGPoint(x: 34, y: 29), CGPoint(x: 22, y: 37)]), with: .color(coral))
        context.fill(polygon([CGPoint(x: 77, y: 21 - fold), CGPoint(x: 62, y: 29), CGPoint(x: 74, y: 37)]), with: .color(coral))
        let body = polygon([CGPoint(x: 23, y: 29), CGPoint(x: 73, y: 29), CGPoint(x: 87, y: 57), CGPoint(x: 69, y: 79), CGPoint(x: 48, y: 87), CGPoint(x: 27, y: 79), CGPoint(x: 9, y: 57)])
        context.fill(body, with: .color(cream))
        context.fill(polygon([CGPoint(x: 9, y: 57), CGPoint(x: 31, y: 64), CGPoint(x: 27, y: 79)]), with: .color(coral))
        context.fill(polygon([CGPoint(x: 87, y: 57), CGPoint(x: 65, y: 64), CGPoint(x: 69, y: 79)]), with: .color(coral))
        context.fill(polygon([CGPoint(x: 27, y: 79), CGPoint(x: 48, y: 70), CGPoint(x: 69, y: 79), CGPoint(x: 48, y: 87)]), with: .color(coral.opacity(0.45)))
        context.stroke(line([CGPoint(x: 23, y: 29), CGPoint(x: 48, y: 37), CGPoint(x: 73, y: 29)]), with: .color(coral.opacity(0.4)), lineWidth: 1)
        drawExpression(in: context, color: ink, eyeY: 48, eyeWidth: 8, eyeHeight: 14, mouthY: 61, brows: false)
        for x: CGFloat in [23, 67] { context.fill(rect(x, 60, 6, 3, radius: 1.5), with: .color(listening ? mint : coral)) }
    }

    private func drawStar(in context: GraphicsContext) {
        let star = polygon([CGPoint(x: 48, y: 19), CGPoint(x: 60, y: 33), CGPoint(x: 82, y: 30), CGPoint(x: 77, y: 51), CGPoint(x: 91, y: 65), CGPoint(x: 69, y: 71), CGPoint(x: 63, y: 91), CGPoint(x: 48, y: 80), CGPoint(x: 30, y: 89), CGPoint(x: 26, y: 70), CGPoint(x: 6, y: 61), CGPoint(x: 21, y: 46), CGPoint(x: 18, y: 27), CGPoint(x: 38, y: 32)])
        context.fill(star, with: .linearGradient(Gradient(colors: [cream, amber, Color(red: 1, green: 0.61, blue: 0.32)]), startPoint: CGPoint(x: 32, y: 22), endPoint: CGPoint(x: 66, y: 90)))
        context.stroke(star, with: .color(amber), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        context.stroke(line([CGPoint(x: 48, y: 23), CGPoint(x: 48, y: 12)]), with: .color(mint), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        var leaf = Path()
        leaf.move(to: CGPoint(x: 48, y: 14))
        leaf.addQuadCurve(to: CGPoint(x: 68, y: 4), control: CGPoint(x: 50, y: 0))
        leaf.addQuadCurve(to: CGPoint(x: 48, y: 14), control: CGPoint(x: 66, y: 20))
        context.fill(leaf, with: .color(listening ? CompanionStyle.accent : mint))
        drawExpression(in: context, color: ink, eyeY: 49, eyeWidth: 8, eyeHeight: 13, mouthY: 62, brows: false)
        for x: CGFloat in [23, 67] { context.fill(Path(ellipseIn: CGRect(x: x, y: 60, width: 6, height: 4)), with: .color(pink.opacity(0.75))) }
    }
}

struct CompanionCharacter: View {
    var size: CGFloat = 42
    var avatar: CompanionAvatar = .crtBuddy
    var animates = true
    var focusing = false
    var joyful = false
    var listening = false
    var gaze = CGSize.zero

    var body: some View {
        TimelineView(.animation(minimumInterval: avatar == .arcade1984 ? 1.0 / 12 : 1.0 / 60, paused: !animates)) { context in
            let time = animates ? context.date.timeIntervalSinceReferenceDate : 0
            let phase = time.truncatingRemainder(dividingBy: 4.7)
            let eye = animates && phase < 0.26 ? 1 - sin(phase / 0.26 * .pi) * 0.96 : 1
            let amplitude = avatar == .minimalSpirit ? 0.7 : 2.0
            let float = avatar == .arcade1984 ? (sin(time * 2) * 2).rounded() : sin(time * 1.8) * amplitude
            let sway = avatar == .starSprout ? 3.0 : avatar == .minimalSpirit ? 0.3 : 1.2
            CompanionFace(avatar: avatar, focusing: focusing, joyful: joyful, gaze: gaze, eyeOpen: eye, listening: listening, motionTime: time)
                .scaleEffect(size / 42 * (animates && avatar != .arcade1984 ? 1 + sin(time * 1.8) * 0.018 : 1))
                .rotationEffect(.degrees(animates && joyful ? sin(time * 6) * 5 : sin(time * 0.9) * sway))
                .offset(y: float)
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    if joyful {
                        Image(systemName: "sparkle").font(.system(size: size * 0.20)).foregroundStyle(avatar.tint)
                            .scaleEffect(animates ? 0.85 + sin(time * 5) * 0.15 : 1)
                            .offset(x: 6, y: -2)
                    }
                }
                .animation(animates ? .spring(response: 0.4, dampingFraction: 0.7) : nil, value: joyful)
                .animation(animates ? .spring(response: 0.45, dampingFraction: 0.78) : nil, value: gaze)
        }
        .frame(width: size, height: size)
    }
}

struct CompanionAvatarPicker: View {
    @Binding var selection: CompanionAvatar
    var animates: Bool

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(CompanionAvatar.allCases) { avatar in
                CompanionInteraction(action: { selection = avatar }) {
                    VStack(spacing: 8) {
                        CompanionCharacter(size: 62, avatar: avatar, animates: animates && selection == avatar)
                            .padding(.top, 4)
                        Text(avatar.name).font(.callout.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                        Text(avatar.subtitle).font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(1).minimumScaleFactor(0.8)
                        Label(selection == avatar ? "Selected" : "Choose", systemImage: selection == avatar ? "checkmark.circle.fill" : "circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selection == avatar ? avatar.tint : CompanionStyle.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(selection == avatar ? avatar.tint.opacity(0.08) : CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(selection == avatar ? avatar.tint : CompanionStyle.separator, lineWidth: selection == avatar ? 1.5 : 1) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(avatar.name). \(avatar.detail)")
                .accessibilityValue(selection == avatar ? "Selected" : "")
                .accessibilityHint("Choose this companion")
            }
        }
    }
}
