import AppKit
import SwiftUI

// Shared palette from the approved local prototype.
enum CompanionStyle {
    static let notchBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
    static let background = adaptive(dark: (23, 23, 28), light: (244, 244, 247))
    static let surface = adaptive(dark: (38, 38, 45), light: (255, 255, 255))
    static let separator = adaptive(dark: (60, 60, 69), light: (223, 223, 230))
    static let accent = Color(red: 198 / 255, green: 185 / 255, blue: 1)
    static let accentInk = adaptive(dark: (198, 185, 255), light: (100, 73, 164))
    static let muted = adaptive(dark: (170, 170, 181), light: (102, 102, 116))
    static let ink = Color.primary
    static let edge = adaptive(dark: (255, 255, 255), light: (0, 0, 0))
    private static func adaptive(dark: (Double, Double, Double), light: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
        })
    }
}

private struct WorkspaceGlassKey: EnvironmentKey { static let defaultValue = false }
private struct SurfaceGlassEnabledKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var workspaceGlass: Bool { get { self[WorkspaceGlassKey.self] } set { self[WorkspaceGlassKey.self] = newValue } }
    var surfaceGlassEnabled: Bool { get { self[SurfaceGlassEnabledKey.self] } set { self[SurfaceGlassEnabledKey.self] = newValue } }
}

struct WorkspaceBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.islandPreview) private var preview
    @Environment(\.surfaceGlassEnabled) private var glass
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            if !glass || opaque || preview { CompanionStyle.background }
            else { Rectangle().fill(.regularMaterial) }
            if glass && !opaque {
                LinearGradient(colors: [CompanionStyle.background.opacity(0.65), CompanionStyle.background.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [CompanionStyle.accent.opacity(scheme == .dark ? 0.09 : 0.04), .clear], center: .topTrailing, startRadius: 20, endRadius: 650)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct WorkspaceSurface: ViewModifier {
    var selected = false
    var radius: CGFloat = 22
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.islandPreview) private var preview
    @Environment(\.surfaceGlassEnabled) private var glass
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            if !glass || opaque || preview { shape.fill(CompanionStyle.surface) }
            else if #available(macOS 26, *) { Color.clear.glassEffect(.regular.tint(CompanionStyle.surface.opacity(0.35)), in: shape) }
            else { shape.fill(.ultraThinMaterial) }
        }
        .background(selected ? CompanionStyle.accent.opacity(0.12) : .clear, in: shape)
        .overlay { shape.strokeBorder(selected ? CompanionStyle.accent.opacity(0.65) : CompanionStyle.edge.opacity(contrast == .increased ? 0.45 : 0.10), lineWidth: selected ? 1.1 : 0.75).allowsHitTesting(false) }
        .shadow(color: .black.opacity(!glass || opaque ? 0 : 0.09), radius: 14, y: 6)
    }
}

struct CompanionButtonStyle: ButtonStyle {
    var primary = false
    var compact = false
    @Environment(\.workspaceGlass) private var workspace
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 11 : 15)
            .padding(.vertical, compact ? 7 : 10)
            .foregroundStyle(primary ? Color.black : CompanionStyle.ink)
            .background(primary ? CompanionStyle.accent : workspace ? CompanionStyle.edge.opacity(0.09) : CompanionStyle.separator, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(CompanionStyle.edge.opacity(primary ? 0.14 : workspace ? 0.11 : 0), lineWidth: 0.7).allowsHitTesting(false) }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct WorkspaceSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(configuration.isOn ? CompanionStyle.accent : CompanionStyle.edge.opacity(0.16))
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
            .background(keyboardFocused && !pointerActivated ? .white.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 16))
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
