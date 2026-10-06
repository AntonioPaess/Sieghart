import AppKit
import CoreImage.CIFilterBuiltins
import ImageIO
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
        case .coastBuddy: "Work from anywhere"
        case .paperPal: "Folded with care"
        case .inkBuddy: "Classic, with character"
        }
    }
    var detail: String {
        switch self {
        case .crtBuddy: "A pocket CRT with mint eyes and a warm arcade glow."
        case .arcade1984: "An amber pixel friend with a green screen and victory hops."
        case .minimalSpirit: "Just a face, a soft blink, and a little personality."
        case .coastBuddy: "A seafoam pocket radio with a sun hat, backpack, and a relaxed rhythm."
        case .paperPal: "A friendly paper creature with expressive folded ears."
        case .inkBuddy: "A quiet ivory and charcoal desk companion with vintage cartoon limbs."
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

// Vector fallback for a missing resource; production characters use the
// approved illustrated sprite designs below.
private struct CompanionVectorFace: View, Animatable {
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
            case .coastBuddy: drawObject(in: context, coast: true)
            case .paperPal: drawPaper(in: context)
            case .inkBuddy: drawObject(in: context, coast: false)
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

    private func drawObject(in context: GraphicsContext, coast: Bool) {
        let shell = rect(14, 17, 68, 65, radius: 18)
        let teal = Color(red: 0.43, green: 0.77, blue: 0.71)
        context.fill(shell, with: .color(coast ? teal : ink))
        context.fill(rect(21, 24, 54, 40, radius: 12), with: .color(coast ? ink : cream))
        drawExpression(in: context, color: coast ? mint : ink, eyeY: 41, eyeWidth: 8, eyeHeight: 13, mouthY: 52)
        if coast {
            context.fill(rect(17, 10, 62, 9, radius: 4), with: .color(cream))
            context.fill(rect(29, 3, 35, 12, radius: 4), with: .color(cream))
            for y: CGFloat in [69, 73, 77] { context.fill(rect(27, y, 22, 2, radius: 1), with: .color(ink)) }
        } else {
            context.fill(polygon([CGPoint(x: 38, y: 68), CGPoint(x: 49, y: 73), CGPoint(x: 58, y: 68), CGPoint(x: 58, y: 78), CGPoint(x: 49, y: 73), CGPoint(x: 38, y: 78)]), with: .color(cream))
        }
        for x: CGFloat in [7, 83] { context.fill(rect(x, 48, 6, 13, radius: 3), with: .color(cream)) }
        for x: CGFloat in [28, 58] { context.fill(rect(x, 82, 12, 8, radius: 4), with: .color(coast ? cream : ink)) }
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


}

enum CompanionMood: Equatable {
    case idle, happy, annoyed, asleep, waking, startled, understood, celebrating
}

enum CompanionPose: Int, CaseIterable {
    case idle, blink, happy, annoyed, asleep, listening, focused, waking, startled
}

@MainActor
enum CompanionSprites {
    static var directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("AvatarSprites")
    private static var sheets: [CompanionAvatar: CGImage] = [:]
    private static var frames: [String: NSImage] = [:]
    private static var originalBoard: CGImage?
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let renderer = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
    private static let blackMatte: Data = {
        let dimension = 64
        var values: [Float] = []
        values.reserveCapacity(dimension * dimension * dimension * 4)
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    // Remove the board's near-black backdrop at rendering time;
                    // the approved source PNG and colored artwork stay intact.
                    let peak = max(r, max(g, b))
                    let alpha: Float = peak <= 3 ? 0 : min(1, Float(peak) / 63 / 0.35)
                    // The board already has black-matted glow: preserve that
                    // emitted light while making the outer glow translucent.
                    values += alpha == 0 ? [0, 0, 0, 0] : [Float(r) / 63, Float(g) / 63, Float(b) / 63, alpha]
                }
            }
        }
        return values.withUnsafeBytes { Data($0) }
    }()

    static func image(for avatar: CompanionAvatar, pose: CompanionPose) -> NSImage? {
        let key = "\(avatar.rawValue).\(pose.rawValue)"
        if let image = frames[key] { return image }
        if pose == .idle, let approved = approvedIdle(for: avatar) {
            frames[key] = approved
            return approved
        }
        if sheets[avatar] == nil, let url = directory?.appendingPathComponent("\(avatar.rawValue).png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            sheets[avatar] = sheet
        }
        guard let sheet = sheets[avatar] else { return nil }
        let width = CGFloat(sheet.width) / 3, height = CGFloat(sheet.height) / 3
        let crop = CGRect(x: CGFloat(pose.rawValue % 3) * width, y: CGFloat(pose.rawValue / 3) * height, width: width, height: height)
        guard let frame = sheet.cropping(to: crop) else { return nil }
        let image = NSImage(cgImage: frame, size: CGSize(width: 42, height: 42))
        image.isTemplate = false
        frames[key] = image
        return image
    }

    private static func approvedIdle(for avatar: CompanionAvatar) -> NSImage? {
        // The four retained neutral designs use the unchanged approved board.
        // The two replacements use their own new sprite artwork.
        let crop: CGRect
        switch avatar {
        case .crtBuddy: crop = CGRect(x: 60, y: 170, width: 390, height: 390)
        case .arcade1984: crop = CGRect(x: 435, y: 168, width: 395, height: 395)
        case .minimalSpirit: crop = CGRect(x: 880, y: 230, width: 286, height: 286)

        case .paperPal: crop = CGRect(x: 1643, y: 180, width: 385, height: 385)
        case .coastBuddy, .inkBuddy: return nil
        }
        if originalBoard == nil, let url = directory?.appendingPathComponent("approved-directions.png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            originalBoard = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let original = originalBoard?.cropping(to: crop) else { return nil }
        let input = CIImage(cgImage: original)
        let matte = CIFilter.colorCubeWithColorSpace()
        matte.inputImage = input; matte.cubeDimension = 64
        matte.cubeData = blackMatte; matte.colorSpace = colorSpace
        guard let glow = matte.outputImage,
              let mask = bodyMask(for: avatar, size: crop.size) else { return nil }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = input; blend.backgroundImage = glow
        blend.maskImage = CIImage(cgImage: mask)
        guard let output = blend.outputImage,
              let rendered = renderer.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: colorSpace) else { return nil }
        let image = NSImage(cgImage: rendered, size: NSSize(width: 42, height: 42))
        image.isTemplate = false
        return image
    }

    private static func bodyMask(for avatar: CompanionAvatar, size: CGSize) -> CGImage? {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 0, alpha: 1); context.fill(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        context.setFillColor(gray: 1, alpha: 1)
        switch avatar {
        case .crtBuddy:
            context.addPath(CGPath(roundedRect: CGRect(x: 45, y: 96, width: 291, height: 222), cornerWidth: 50, cornerHeight: 50, transform: nil)); context.fillPath()
        case .arcade1984: context.fill(CGRect(x: 108, y: 153, width: 205, height: 153))

        case .paperPal: context.fill(CGRect(x: 110, y: 155, width: 175, height: 112))
        case .minimalSpirit, .coastBuddy, .inkBuddy: break
        }
        return context.makeImage()
    }

    static func menuBarImage(for avatar: CompanionAvatar) -> NSImage? {
        guard let image = image(for: avatar, pose: .idle)?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = false
        return image
    }
}

struct CompanionFace: View {
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

    private var pose: CompanionPose {
        switch mood {
        case .annoyed: return .annoyed
        case .asleep: return .asleep
        case .waking: return .waking
        case .startled: return .startled
        case .happy: return .happy
        case .understood: return .focused
        case .celebrating: return .happy
        case .idle: break
        }
        if joyful { return .happy }
        if listening { return .listening }
        if blinking { return .blink }
        return focusing ? .focused : .idle
    }

    var body: some View {
        Group {
            if let image = CompanionSprites.image(for: avatar, pose: pose) {
                ZStack {
                    Image(nsImage: image).resizable().interpolation(avatar == .arcade1984 ? .none : .high).scaledToFit()
                    if mood == .idle, !listening, !joyful, let blink = CompanionSprites.image(for: avatar, pose: .blink) {
                        Image(nsImage: blink).resizable().interpolation(avatar == .arcade1984 ? .none : .high).scaledToFit()
                            .opacity(Double(min(1, max(0, 1 - (eyeOpen ?? 1)))))
                    }
                }
                .scaleEffect(1.1)
                .offset(x: gaze.width * 0.2, y: gaze.height * 0.2)
                .id(pose)
                .transition(.opacity)
            } else {
                CompanionVectorFace(avatar: avatar, blinking: blinking, focusing: focusing, joyful: joyful || mood == .happy, gaze: gaze, eyeOpen: mood == .asleep ? 0.08 : eyeOpen, listening: listening, motionTime: motionTime)
            }
        }
        .frame(width: 42, height: 42)
        .animation(animates ? .easeInOut(duration: 0.2) : nil, value: pose)
        .accessibilityHidden(true)
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

    private func recover(after delay: Duration) {
        recovery = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.mood = .idle
        }
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
    var mood: CompanionMood = .idle
    var strolling = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animates)) { context in
            let time = animates ? context.date.timeIntervalSinceReferenceDate : 0
            let phase = time.truncatingRemainder(dividingBy: 4.7)
            let eye = animates && phase < 0.26 ? 1 - sin(phase / 0.26 * .pi) * 0.96 : 1
            let amplitude = avatar == .minimalSpirit ? 0.7 : 2.0
            let float = sin(time * 1.8) * amplitude
            let sway = avatar == .minimalSpirit || avatar == .inkBuddy ? 0.3 : 1.2
            let reaction = joyful ? CompanionMood.happy : mood
            // Cosine has a smooth landing; absolute-sine hops kink at every step.
            let hop = (reaction == .happy || reaction == .celebrating) && animates ? (cos(time * 6) - 1) * size * (reaction == .celebrating ? 0.045 : 0.035) : strolling && animates ? (cos(time * 6) - 1) * 1.2 : float
            let shake = reaction == .annoyed && animates ? sin(time * 18) * size * 0.025 : 0
            let stretch: CGFloat = reaction == .waking ? 1.08 : reaction == .asleep ? 0.96 : 1
            let breath = animates ? 1 + sin(time * (reaction == .asleep ? 1.5 : 1.8)) * (reaction == .asleep ? 0.02 : 0.009) : 1
            let nod = reaction == .understood && animates ? (1 - cos(time * 5)) * 3 : 0
            CompanionFace(avatar: avatar, focusing: focusing, joyful: joyful, gaze: gaze, eyeOpen: eye, listening: listening, motionTime: time, mood: reaction, animates: animates)
                .scaleEffect(x: size / 42 * breath, y: size / 42 * stretch * breath)
                .rotationEffect(.degrees(strolling && animates ? sin(time * 6) * 4 : reaction == .understood ? nod : reaction == .celebrating && animates ? sin(time * 7) * 9 : reaction == .asleep ? 6 : reaction == .annoyed && animates ? sin(time * 12) * 4 : animates && joyful ? sin(time * 6) * 5 : sin(time * 0.9) * sway))
                .rotation3DEffect(.degrees(animates ? Double(gaze.width) * 1.6 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
                .rotation3DEffect(.degrees(animates ? -Double(gaze.height) * 1.2 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.3)
                .offset(x: shake, y: reaction == .asleep ? size * 0.035 : hop)
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    if reaction == .happy {
                        Image(systemName: "sparkle").font(.system(size: size * 0.20)).foregroundStyle(avatar.tint)
                            .scaleEffect(animates ? 0.85 + sin(time * 5) * 0.15 : 1)
                            .offset(x: 6, y: -2)
                    } else if reaction == .asleep {
                        Text("z").font(.system(size: size * 0.18, weight: .medium, design: .rounded)).foregroundStyle(avatar.tint.opacity(0.7))
                            .offset(x: 3, y: animates ? -3 - sin(time * 1.5) * 3 : -3)
                    } else if reaction == .understood {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: size * 0.22)).foregroundStyle(.mint)
                            .offset(x: 4, y: 0)
                    } else if reaction == .celebrating {
                        ForEach(0..<6) { index in
                            let angle = Double(index) * .pi / 3 + (animates ? time * 0.5 : 0)
                            Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                                .font(.system(size: size * 0.08))
                                .foregroundStyle(index.isMultiple(of: 2) ? avatar.tint : .mint)
                                .offset(x: cos(angle) * size * 0.34 - size * 0.4, y: sin(angle) * size * 0.32 + size * 0.4)
                        }
                    }
                }
                .animation(animates ? .spring(response: 0.4, dampingFraction: 0.7) : nil, value: joyful)
                .animation(animates ? .spring(response: 0.45, dampingFraction: 0.78) : nil, value: gaze)
                .animation(animates ? .spring(response: 0.45, dampingFraction: 0.72) : nil, value: mood)
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
