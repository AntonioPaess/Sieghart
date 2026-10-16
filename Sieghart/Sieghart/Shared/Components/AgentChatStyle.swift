import SwiftUI

// Adapted from Coucou's MIT CardBackground, ChatBubble, TypingDotsView and
// SendButtonStyle (71b773f08101237e1ec950efdaee17a626c830e6).
// Copyright (c) 2026 Louis Raillé. See THIRD_PARTY_NOTICES.md.
enum AgentChatColor {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
struct AgentChatBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20).fill(AgentChatColor.hex(0x141518))
            .overlay {
                RadialGradient(stops: [.init(color: AgentChatColor.hex(0x6366F1).opacity(0.5), location: 0), .init(color: .clear, location: 0.7)], center: UnitPoint(x: 0.5, y: 1.3), startRadius: 0, endRadius: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }.overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.035), lineWidth: 1))
    }
}
struct AgentChatBubble: View {
    let message: CodingMessage
    var isStreaming = false
    var body: some View {
        if !message.text.isEmpty {
            HStack(alignment: .top) {
                if message.role == .user {
                    Spacer(minLength: 32)
                    Text(verbatim: message.text).font(.system(size: 12.5)).foregroundStyle(AgentChatColor.hex(0xF1F2F4))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Group {
                        if isStreaming {
                            // Streaming events are already batched at 15 Hz. Avoid
                            // a second per-frame render loop just for a caret.
                            Text(verbatim: message.text + " ▌").font(.system(size: 12.5))
                                .foregroundStyle(AgentChatColor.hex(0xB0B5BE)).fixedSize(horizontal: false, vertical: true)
                        } else if message.role == .tool {
                            Text(verbatim: message.text).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AgentChatColor.hex(0xB0B5BE)).textSelection(.enabled)
                        } else { AgentMarkdownView(markdown: message.text) }
                    }.padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    Spacer(minLength: 8)
                }
            }
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
                Circle().fill(AgentChatColor.hex(0x6B7079)).frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1.2 : 0.6)
                    .animation(preview || reduced ? nil : .easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.14), value: phase)
            }
        }.padding(.horizontal, 2).padding(.vertical, 4).onAppear { if !preview && !reduced { phase = true } }
    }
}
struct AgentChatSendStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 28, height: 28).background(AgentChatColor.hex(0xF5F6F8), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
