import AppKit
import SwiftUI

// Shared palette from the approved local prototype.
enum CompanionStyle {
    static let background = Color(red: 23 / 255, green: 23 / 255, blue: 28 / 255)
    static let surface = Color(red: 38 / 255, green: 38 / 255, blue: 45 / 255)
    static let separator = Color(red: 60 / 255, green: 60 / 255, blue: 69 / 255)
    static let accent = Color(red: 198 / 255, green: 185 / 255, blue: 1)
    static let muted = Color(red: 170 / 255, green: 170 / 255, blue: 181 / 255)
}

@MainActor
final class CompanionPreferences: ObservableObject {
    @Published var hoverEnabled: Bool { didSet { save(hoverEnabled, "hover") } }
    @Published var impactsEnabled: Bool { didSet { save(impactsEnabled, "impacts") } }
    @Published var compactTimer: Bool { didSet { save(compactTimer, "compactTimer") } }
    @Published var characterMotion: Bool { didSet { save(characterMotion, "characterMotion") } }
    @Published var reduceMotion: Bool { didSet { save(reduceMotion, "reduceMotion") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hoverEnabled = defaults.object(forKey: "appearance.hover") as? Bool ?? true
        impactsEnabled = defaults.object(forKey: "appearance.impacts") as? Bool ?? false
        compactTimer = defaults.object(forKey: "appearance.compactTimer") as? Bool ?? true
        characterMotion = defaults.object(forKey: "appearance.characterMotion") as? Bool ?? true
        reduceMotion = defaults.object(forKey: "appearance.reduceMotion") as? Bool ?? false
    }

    var usesReducedMotion: Bool { reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func save(_ value: Bool, _ name: String) { defaults.set(value, forKey: "appearance.\(name)") }
}

struct CompanionButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background(primary ? CompanionStyle.accent : CompanionStyle.separator, in: RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

// Custom interaction avoids AppKit's rectangular mouse focus ring. Keyboard
// navigation and VoiceOver keep a real action and a rounded focus indicator.
struct CompanionInteraction<Content: View>: View {
    var action: () -> Void
    var content: Content
    @FocusState private var keyboardFocused: Bool
    @State private var pointerActivated = false
    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action; self.content = content()
    }
    var body: some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { pointerActivated = true; action() }
            .focusable()
            .focused($keyboardFocused)
            .focusEffectDisabled()
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(CompanionStyle.accent.opacity(keyboardFocused && !pointerActivated ? 0.45 : 0), lineWidth: 1) }
            .onChange(of: keyboardFocused) { _, focused in if !focused { pointerActivated = false } }
            .onKeyPress(keys: [.space, .return]) { _ in pointerActivated = false; action(); return .handled }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

// An original vector character: a pocket-sized CRT companion with phosphor
// eyes, an antenna, and warm arcade accents. No downloaded assets are needed.
struct CompanionFace: View, Animatable {
    var eyeOpen: CGFloat
    var smile: CGFloat
    var brow: CGFloat
    var gaze: CGSize
    var listening: Bool

    init(blinking: Bool = false, focusing: Bool = false, joyful: Bool = false, gaze: CGSize = .zero, eyeOpen: CGFloat? = nil, listening: Bool = false) {
        self.eyeOpen = eyeOpen ?? (blinking ? 0.08 : 1)
        self.smile = joyful ? 1 : focusing ? 0.25 : 0.55
        self.brow = focusing ? 1 : 0
        self.gaze = gaze
        self.listening = listening
    }

    nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(eyeOpen, AnimatablePair(smile, brow)) }
        set { eyeOpen = newValue.first; smile = newValue.second.first; brow = newValue.second.second }
    }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 96, y: size.height / 96)
            let mint = Color(red: 0.58, green: 1, blue: 0.83)
            let pink = Color(red: 1, green: 0.52, blue: 0.73)
            let amber = Color(red: 1, green: 0.80, blue: 0.43)
            let shell = Path(roundedRect: CGRect(x: 7, y: 19, width: 82, height: 65), cornerRadius: 20)
            context.fill(shell, with: .color(Color(red: 0.17, green: 0.15, blue: 0.25)))
            context.stroke(shell, with: .color(CompanionStyle.accent), lineWidth: 3)
            let antenna = Path { p in
                p.move(to: CGPoint(x: 48, y: 18)); p.addLine(to: CGPoint(x: 48, y: 10)); p.addLine(to: CGPoint(x: 55, y: 6))
            }
            context.stroke(antenna, with: .color(CompanionStyle.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: 52, y: 2, width: 8, height: 8)), with: .color(listening ? amber : mint))
            for x: CGFloat in [1, 89] {
                context.fill(Path(roundedRect: CGRect(x: x, y: 43, width: 6, height: 18), cornerRadius: 3), with: .color(pink))
            }
            let screen = Path(roundedRect: CGRect(x: 15, y: 28, width: 66, height: 43), cornerRadius: 14)
            context.fill(screen, with: .color(Color(red: 0.025, green: 0.08, blue: 0.09)))
            context.stroke(screen, with: .color(mint.opacity(0.25)), lineWidth: 1)
            for y in stride(from: 33, through: 65, by: 5) {
                var scan = Path(); scan.move(to: CGPoint(x: 22, y: y)); scan.addLine(to: CGPoint(x: 74, y: y))
                context.stroke(scan, with: .color(mint.opacity(0.055)), lineWidth: 1)
            }
            let eyeHeight = max(2, 16 * eyeOpen)
            for x: CGFloat in [28, 57] {
                let eye = Path(roundedRect: CGRect(x: x + gaze.width, y: 47 - eyeHeight / 2 + gaze.height, width: 10, height: eyeHeight), cornerRadius: 3)
                var glow = context; glow.addFilter(.shadow(color: mint.opacity(0.5), radius: 3))
                glow.fill(eye, with: .color(mint))
                var eyebrow = Path()
                eyebrow.move(to: CGPoint(x: x - 1, y: 34 + brow * (x < 40 ? 0 : 2)))
                eyebrow.addLine(to: CGPoint(x: x + 10, y: 33 + brow * (x < 40 ? 2 : 0)))
                context.stroke(eyebrow, with: .color(mint.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            var mouth = Path()
            mouth.move(to: CGPoint(x: 39, y: 59))
            mouth.addQuadCurve(to: CGPoint(x: 57, y: 59), control: CGPoint(x: 48, y: 60 + smile * 10))
            context.stroke(mouth, with: .color(mint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            for x: CGFloat in [24, 67] { context.fill(Path(roundedRect: CGRect(x: x, y: 59, width: 5, height: 2), cornerRadius: 1), with: .color(pink.opacity(0.7))) }
            for x: CGFloat in [32, 40, 48] { context.fill(Path(roundedRect: CGRect(x: x, y: 76, width: 4, height: 2), cornerRadius: 1), with: .color(CompanionStyle.accent.opacity(0.65))) }
            context.fill(Path(ellipseIn: CGRect(x: 64, y: 74, width: 5, height: 5)), with: .color(amber))
            for x: CGFloat in [26, 59] { context.fill(Path(roundedRect: CGRect(x: x, y: 84, width: 11, height: 5), cornerRadius: 2), with: .color(CompanionStyle.accent)) }
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

struct CompanionCharacter: View {
    var size: CGFloat = 42
    var animates = true
    var focusing = false
    var joyful = false
    var listening = false
    var gaze = CGSize.zero

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animates)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = time.truncatingRemainder(dividingBy: 4.7)
            let eye = animates && phase < 0.26 ? 1 - sin(phase / 0.26 * .pi) * 0.96 : 1
            let float = animates ? sin(time * 1.8) * 2 : 0
            CompanionFace(focusing: focusing, joyful: joyful, gaze: gaze, eyeOpen: eye, listening: listening)
                .scaleEffect(size / 42 * (animates ? 1 + sin(time * 1.8) * 0.018 : 1))
                .rotationEffect(.degrees(animates && joyful ? sin(time * 6) * 5 : animates ? sin(time * 0.9) * 1.2 : 0))
                .offset(y: float)
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    if joyful {
                        Image(systemName: "sparkle").font(.system(size: size * 0.20)).foregroundStyle(CompanionStyle.accent)
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
