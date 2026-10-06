import AppKit
import SwiftUI

// Shared palette from the approved local prototype.
enum CompanionStyle {
    static let notchBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
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
    @Published var avatar: CompanionAvatar { didSet { defaults.set(avatar.rawValue, forKey: "appearance.avatar") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hoverEnabled = defaults.object(forKey: "appearance.hover") as? Bool ?? true
        impactsEnabled = defaults.object(forKey: "appearance.impacts") as? Bool ?? false
        compactTimer = defaults.object(forKey: "appearance.compactTimer") as? Bool ?? true
        characterMotion = defaults.object(forKey: "appearance.characterMotion") as? Bool ?? true
        reduceMotion = defaults.object(forKey: "appearance.reduceMotion") as? Bool ?? false
        let savedAvatar = defaults.string(forKey: "appearance.avatar")
        let migrated = savedAvatar == "soft-orbit" ? "coast-buddy" : savedAvatar == "star-sprout" ? "ink-buddy" : savedAvatar
        avatar = migrated.flatMap(CompanionAvatar.init(rawValue:)) ?? .crtBuddy
        if savedAvatar != migrated { defaults.set(avatar.rawValue, forKey: "appearance.avatar") }
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
