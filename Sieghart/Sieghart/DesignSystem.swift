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

private struct WorkspaceGlassKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var workspaceGlass: Bool { get { self[WorkspaceGlassKey.self] } set { self[WorkspaceGlassKey.self] = newValue } }
}

struct WorkspaceBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.islandPreview) private var preview
    var body: some View {
        ZStack {
            if opaque || preview { CompanionStyle.background }
            else { Rectangle().fill(.regularMaterial) }
            LinearGradient(colors: [Color(red: 0.16, green: 0.15, blue: 0.22).opacity(0.8), CompanionStyle.background.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [CompanionStyle.accent.opacity(opaque ? 0 : 0.09), .clear], center: .topTrailing, startRadius: 20, endRadius: 650)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct WorkspaceSurface: ViewModifier {
    var selected = false
    var radius: CGFloat = 22
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.islandPreview) private var preview
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            if opaque { shape.fill(CompanionStyle.surface) }
            else if preview { shape.fill(Color(white: selected ? 0.22 : 0.17)) }
            else if #available(macOS 26, *) { Color.clear.glassEffect(.regular.tint(CompanionStyle.surface.opacity(0.35)), in: shape) }
            else { shape.fill(.ultraThinMaterial) }
        }
        .background(selected ? CompanionStyle.accent.opacity(0.12) : .clear, in: shape)
        .overlay { shape.strokeBorder(selected ? CompanionStyle.accent.opacity(0.65) : .white.opacity(contrast == .increased ? 0.45 : 0.10), lineWidth: selected ? 1.1 : 0.75).allowsHitTesting(false) }
        .shadow(color: .black.opacity(opaque ? 0 : 0.09), radius: 14, y: 6)
    }
}

enum WidgetSize: String, CaseIterable, Identifiable {
    case small = "Small", medium = "Medium", large = "Large"
    var id: String { rawValue }
    var scale: CGFloat { self == .small ? 0.85 : self == .large ? 1.2 : 1 }
}

@MainActor
final class CompanionPreferences: ObservableObject {
    @Published var hoverEnabled: Bool { didSet { save(hoverEnabled, "hover") } }
    @Published var impactsEnabled: Bool { didSet { save(impactsEnabled, "impacts") } }
    @Published var compactTimer: Bool { didSet { save(compactTimer, "compactTimer") } }
    @Published var characterMotion: Bool { didSet { save(characterMotion, "characterMotion") } }
    @Published var reduceMotion: Bool { didSet { save(reduceMotion, "reduceMotion") } }
    @Published var widgetSize: WidgetSize { didSet { defaults.set(widgetSize.rawValue, forKey: "appearance.widgetSize") } }
    @Published var avatar: CompanionAvatar { didSet { defaults.set(avatar.rawValue, forKey: "appearance.avatar") } }
    @Published var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: "onboarding.completed.v1") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        widgetSize = defaults.string(forKey: "appearance.widgetSize").flatMap(WidgetSize.init(rawValue:)) ?? .medium
        onboardingComplete = defaults.bool(forKey: "onboarding.completed.v1")
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
    @Environment(\.workspaceGlass) private var workspace
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background(primary ? CompanionStyle.accent : workspace ? .white.opacity(0.09) : CompanionStyle.separator, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(primary ? 0.14 : workspace ? 0.11 : 0), lineWidth: 0.7).allowsHitTesting(false) }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct WorkspaceSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(configuration.isOn ? CompanionStyle.accent : .white.opacity(0.16))
                .frame(width: 36, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(configuration.isOn ? Color.black.opacity(0.85) : .white).frame(width: 16, height: 16).padding(3)
                }
        }.buttonStyle(.plain).focusEffectDisabled()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isOn)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
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

extension View {
    @ViewBuilder
    func companionCard(height: CGFloat? = nil, padding: CGFloat? = nil) -> some View {
        modifier(CompanionCardModifier(height: height, inset: padding))
    }
}

private struct CompanionCardModifier: ViewModifier {
    var height: CGFloat?
    var inset: CGFloat?
    @Environment(\.islandGlass) private var glass
    @Environment(\.workspaceGlass) private var workspace
    func body(content: Content) -> some View {
        let padding: CGFloat = inset ?? (workspace || !glass ? 24 : 16)
        let sized = content.frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height.map { max(0, $0 - padding * 2) }, alignment: .topLeading).padding(padding)
        if workspace { sized.modifier(WorkspaceSurface()) }
        else if glass { sized.modifier(IslandControlSurface()) }
        else { sized.background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 17)) }
    }
}
