import AppKit
import SwiftUI

// Shared palette from the approved local prototype.
enum CompanionStyle {
    static let notchBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
    static let background = adaptive(dark: (18, 20, 26), light: (246, 247, 250))
    static let surface = adaptive(dark: (28, 31, 39), light: (255, 255, 255))
    static let separator = adaptive(dark: (51, 56, 69), light: (224, 228, 236))
    static let accent = Color(red: 183 / 255, green: 173 / 255, blue: 239 / 255)
    static let accentInk = adaptive(dark: (194, 185, 244), light: (103, 80, 169))
    static let muted = adaptive(dark: (154, 161, 178), light: (101, 109, 126))
    static let sidebar = adaptive(dark: (22, 25, 32), light: (240, 242, 246))
    static let ink = Color.primary
    static let edge = adaptive(dark: (255, 255, 255), light: (0, 0, 0))
    private static func adaptive(dark: (Double, Double, Double), light: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
        })
    }
}

enum WorkspaceMetrics {
    static let pageInset: CGFloat = 30
    static let sectionGap: CGFloat = 24
    static let contentWidth: CGFloat = 1080
    static let cardInset: CGFloat = 20
    static let cardRadius: CGFloat = 18
}

enum WorkspaceTypography {
    static let title = Font.system(size: 27, weight: .semibold, design: .rounded)
    static let section = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11)
}

// One restrained cadence for navigation, control feedback and first appearance.
// Repeated interactions never wait for decorative character choreography.
enum InterfaceMotion {
    static let feedbackDuration = 0.14
    static let pageDuration = 0.22
    static let arrivalDuration = 0.30
    static let feedback = Animation.easeOut(duration: feedbackDuration)
    static let page = Animation.easeOut(duration: pageDuration)
    static let arrival = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: arrivalDuration)
}

struct WorkspacePageArrival: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.islandReduceMotion) private var reducedMotion
    @Environment(\.islandPreview) private var preview
    @State private var arrived = false
    private var visible: Bool { arrived || preview || reducedMotion || systemReducedMotion }
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 6)
            .task {
                guard !arrived else { return }
                if reducedMotion || systemReducedMotion || preview { arrived = true }
                else { withAnimation(InterfaceMotion.arrival) { arrived = true } }
            }
    }
}

struct WorkspacePageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(WorkspaceTypography.title).tracking(-0.45)
                .foregroundStyle(CompanionStyle.ink)
            Text(subtitle).font(WorkspaceTypography.body).foregroundStyle(CompanionStyle.muted)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
    }
}

struct WorkspaceEmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 21, weight: .light))
                .foregroundStyle(CompanionStyle.accentInk).frame(width: 48, height: 48)
                .background(CompanionStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            Text(title).font(WorkspaceTypography.section)
            Text(detail).font(WorkspaceTypography.caption).foregroundStyle(CompanionStyle.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
        }.padding(26).frame(maxWidth: .infinity).modifier(WorkspaceSurface())
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
    var radius: CGFloat = WorkspaceMetrics.cardRadius
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
        .background(selected ? CompanionStyle.accent.opacity(0.07) : .clear, in: shape)
        .overlay { shape.strokeBorder(selected ? CompanionStyle.accent.opacity(0.40) : CompanionStyle.edge.opacity(contrast == .increased ? 0.48 : 0.075), lineWidth: selected ? 1 : 0.7).allowsHitTesting(false) }
        .shadow(color: .black.opacity(!glass || opaque ? 0 : 0.09), radius: 14, y: 6)
    }
}

struct CompanionButtonStyle: ButtonStyle {
    var primary = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        CompanionButtonBody(label: configuration.label, pressed: configuration.isPressed, primary: primary, compact: compact)
    }
}
private struct CompanionButtonBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let primary: Bool
    let compact: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandReduceMotion) private var preferenceReduceMotion
    @State private var hovered = false
    var body: some View {
        label.font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
            .padding(.horizontal, compact ? 11 : 15).padding(.vertical, compact ? 6 : 9)
            .frame(minHeight: compact ? 28 : 34)
            .foregroundStyle(primary ? Color(red: 0.12, green: 0.10, blue: 0.20) : CompanionStyle.ink)
            .background(primary ? CompanionStyle.accent : CompanionStyle.edge.opacity(hovered ? 0.085 : 0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(CompanionStyle.edge.opacity(primary ? 0.12 : hovered ? 0.16 : 0.09), lineWidth: 0.7).allowsHitTesting(false) }
            .opacity(enabled ? (pressed ? 0.72 : 1) : 0.42)
            .scaleEffect(pressed && !reduceMotion && !preferenceReduceMotion ? 0.985 : 1)
            .animation(InterfaceMotion.feedback, value: hovered)
            .animation(reduceMotion || preferenceReduceMotion ? nil : InterfaceMotion.feedback, value: pressed)
            .onHover { hovered = $0 }
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
        let padding: CGFloat = inset ?? (workspace ? WorkspaceMetrics.cardInset : !glass ? 22 : 16)
        let sized = content.frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height.map { max(0, $0 - padding * 2) }, alignment: .topLeading).padding(padding)
        if workspace { sized.modifier(WorkspaceSurface()) }
        else if glass { sized.modifier(IslandControlSurface()) }
        else { sized.background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: WorkspaceMetrics.cardRadius)) }
    }
}
