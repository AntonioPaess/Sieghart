import SwiftUI

// Adapted from Coucou's MIT CardBackground, ChatBubble, TypingDotsView and
// SendButtonStyle (71b773f08101237e1ec950efdaee17a626c830e6), upgraded with
// Sieghart's Apple-like glassmorphic Ada Room design system.
// Copyright (c) 2026 Louis Raillé. See THIRD_PARTY_NOTICES.md.
enum AgentChatColor {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct AgentChatBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.islandPreview) private var preview

    var body: some View {
        RoundedRectangle(cornerRadius: WorkspaceMetrics.cardRadius, style: .continuous)
            .fill(CompanionStyle.surface)
            .overlay(RoundedRectangle(cornerRadius: WorkspaceMetrics.cardRadius).stroke(CompanionStyle.edge.opacity(0.075)))
    }
}

struct AgentChatBubble: View {
    let message: CodingMessage
    var isStreaming = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.islandPreview) private var preview
    @Environment(\.islandReduceMotion) private var reduceMotion

    var body: some View {
        if !message.text.isEmpty {
            let disclosure = AdaThoughtDisclosure.parse(message.text)
            HStack(alignment: .bottom, spacing: 8) {
                if message.role == .user {
                    Spacer(minLength: 42)
                    Text(verbatim: message.text)
                        .font(AdaRoomTheme.bodyFont(size: 13))
                        .foregroundStyle(AdaRoomTheme.userTextColor(for: scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            let bubbleShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                            bubbleShape.fill(scheme == .dark ? CompanionStyle.accent.opacity(0.18) : CompanionStyle.accentInk)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                        }
                        
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Group {
                            if isStreaming {
                                Text(verbatim: disclosure.visibleReply + " ▌")
                                    .font(AdaRoomTheme.bodyFont(size: 13))
                                    .foregroundStyle(AdaRoomTheme.assistantTextColor(for: scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if message.role == .tool {
                                Text(verbatim: disclosure.visibleReply)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(AdaRoomTheme.assistantTextColor(for: scheme).opacity(0.88))
                                    .textSelection(.enabled)
                            } else {
                                AgentMarkdownView(markdown: disclosure.visibleReply)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            let bubbleShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                            bubbleShape.fill(scheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.025))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 0.7)
                        }
                        .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.05), radius: 6, y: 2)
                    }
                    Spacer(minLength: 16)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))

        }
    }
}

struct AgentTypingDots: View {
    @Environment(\.islandPreview) private var preview
    @Environment(\.islandReduceMotion) private var reduced
    @State private var phase = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AdaRoomTheme.auroraCyan, AdaRoomTheme.auroraViolet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 5.5, height: 5.5)
                    .scaleEffect(phase ? 1.25 : 0.65)
                    .animation(preview || reduced ? nil : .easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.14), value: phase)
            }
        }.padding(.horizontal, 2).padding(.vertical, 4).onAppear { if !preview && !reduced { phase = true } }
    }
}

struct AgentChatSendStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(
                    colors: [AdaRoomTheme.auroraIndigo, AdaRoomTheme.auroraViolet],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
            }
            .shadow(color: AdaRoomTheme.auroraIndigo.opacity(0.35), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(AdaRoomTheme.springAnimation, value: configuration.isPressed)
    }
}
