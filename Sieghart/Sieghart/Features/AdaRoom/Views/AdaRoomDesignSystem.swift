import SwiftUI

/// Parses intermediate reasoning steps from an assistant message so they can be collapsed
/// into a discrete *Thought Disclosure* accordion ("Pensando... N passos").
struct AdaThoughtDisclosure: Equatable, Sendable {
    let steps: [String]
    let visibleReply: String

    var stepCount: Int { steps.count }
    var headerTitle: String {
        let count = max(1, steps.count)
        return count == 1 ? "Pensando... 1 passo" : "Pensando... \(count) passos"
    }

    static func parse(_ rawText: String) -> AdaThoughtDisclosure {
        if let startRange = rawText.range(of: "<think>"),
           let endRange = rawText.range(of: "</think>"),
           startRange.upperBound <= endRange.lowerBound {
            let thoughtBlock = String(rawText[startRange.upperBound..<endRange.lowerBound])
            let steps = thoughtBlock
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let remainder = (String(rawText[..<startRange.lowerBound]) + String(rawText[endRange.upperBound...]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return AdaThoughtDisclosure(
                steps: steps,
                visibleReply: remainder.isEmpty ? thoughtBlock : remainder
            )
        }
        return AdaThoughtDisclosure(steps: [], visibleReply: rawText)
    }
}

/// Apple-like premium Design System tokens for the remodeled Ada Room.
enum AdaRoomTheme {
    static let springAnimation = Animation.spring(response: 0.35, dampingFraction: 0.8)

    static let auroraIndigo = Color(red: 0.39, green: 0.40, blue: 0.95)
    static let auroraViolet = Color(red: 0.62, green: 0.42, blue: 0.98)
    static let auroraCyan = Color(red: 0.24, green: 0.78, blue: 0.98)

    static func titleFont(size: CGFloat = 14) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func bodyFont(size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func badgeFont(size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func userTextColor(for scheme: ColorScheme) -> Color {
        .white
    }

    static func assistantTextColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.93, green: 0.95, blue: 0.98) : Color(red: 0.12, green: 0.14, blue: 0.18)
    }

    static func userBubbleGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                auroraIndigo.opacity(scheme == .dark ? 0.62 : 0.88),
                auroraViolet.opacity(scheme == .dark ? 0.52 : 0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func subtleBorderGradient(for scheme: ColorScheme, isUser: Bool) -> LinearGradient {
        if isUser {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.42),
                    auroraCyan.opacity(0.35),
                    Color.white.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color.white.opacity(scheme == .dark ? 0.24 : 0.75),
                auroraViolet.opacity(scheme == .dark ? 0.22 : 0.28),
                auroraCyan.opacity(scheme == .dark ? 0.12 : 0.20),
                Color.white.opacity(scheme == .dark ? 0.05 : 0.30)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Collapsible *Thought Disclosure* accordion ("Pensando... N passos") with spring transition.
struct AdaThoughtDisclosureView: View {
    let steps: [String]
    var isStreaming: Bool = false
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.islandReduceMotion) private var reduceMotion

    var body: some View {
        let count = max(1, steps.count)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : AdaRoomTheme.springAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isStreaming ? "sparkles" : "cpu.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AdaRoomTheme.auroraCyan)
                    Text(count == 1 ? "Pensando... 1 passo" : "Pensando... \(count) passos")
                        .font(AdaRoomTheme.badgeFont(size: 10.5))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.78) : Color.primary.opacity(0.75))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(CompanionStyle.muted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [AdaRoomTheme.auroraCyan.opacity(0.45), AdaRoomTheme.auroraViolet.opacity(0.25)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 0.85
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Raciocínio retrátil da Ada")

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 7) {
                            Text("\(idx + 1)")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(AdaRoomTheme.auroraCyan)
                                .frame(width: 15, height: 15)
                                .background(AdaRoomTheme.auroraCyan.opacity(0.16), in: Circle())
                            Text(step)
                                .font(.system(size: 11, weight: .regular, design: .default))
                                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 0.75)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
            }
        }
    }
}
