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

    init() {
        let defaults = UserDefaults.standard
        hoverEnabled = defaults.object(forKey: "appearance.hover") as? Bool ?? true
        impactsEnabled = defaults.object(forKey: "appearance.impacts") as? Bool ?? false
        compactTimer = defaults.object(forKey: "appearance.compactTimer") as? Bool ?? true
        characterMotion = defaults.object(forKey: "appearance.characterMotion") as? Bool ?? true
        reduceMotion = defaults.object(forKey: "appearance.reduceMotion") as? Bool ?? false
    }

    var usesReducedMotion: Bool { reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func save(_ value: Bool, _ name: String) { UserDefaults.standard.set(value, forKey: "appearance.\(name)") }
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

struct CompanionFace: View {
    var blinking = false
    var focusing = false
    var joyful = false

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 48
            context.scaleBy(x: scale, y: scale)
            for x: CGFloat in [10, 30] {
                var brow = Path()
                brow.move(to: CGPoint(x: x - 1, y: 12))
                brow.addQuadCurve(to: CGPoint(x: x + 9, y: 12), control: CGPoint(x: x + 4, y: 8))
                context.stroke(brow, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                let eye = CGRect(x: x, y: blinking ? 22 : 16, width: 8, height: blinking ? 3 : (focusing ? 12 : 15))
                context.fill(Path(roundedRect: eye, cornerRadius: 4), with: .color(.white))
            }
            var smile = Path()
            smile.move(to: CGPoint(x: 15, y: 37))
            smile.addQuadCurve(to: CGPoint(x: 33, y: 37), control: CGPoint(x: 24, y: joyful ? 47 : focusing ? 40 : 43))
            context.stroke(smile, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}
