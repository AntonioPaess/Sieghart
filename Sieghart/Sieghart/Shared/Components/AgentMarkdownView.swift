// Adapted from Coucou, MIT Copyright (c) 2026 Louis Raillé.
// Commit 71b773f08101237e1ec950efdaee17a626c830e6; see THIRD_PARTY_NOTICES.md.
import AppKit
import SwiftUI

// MARK: - Markdown renderer for chat assistant messages

struct AgentMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(AgentMarkdown.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            let safe = url
            NSWorkspace.shared.open(safe)
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(_ block: AgentMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineAttributed(text))
                .font(.system(size: level <= 2 ? 14 : 13, weight: level <= 2 ? .bold : .semibold))
                .foregroundColor(AgentChatColor.hex(0xF1F2F4))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .paragraph(let text):
            Text(inlineAttributed(text))
                .font(.system(size: 12.5))
                .foregroundColor(AgentChatColor.hex(0xB0B5BE))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .codeBlock(_, let code):
            HStack(alignment: .top) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AgentChatColor.hex(0xC8CDD4))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AgentCodeCopyButton(text: code)
            }
            .padding(10)
            .background(AgentChatColor.hex(0x0D0E12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))

        case .listItem(let prefix, let text, let indent):
            HStack(alignment: .top, spacing: 6) {
                Text(prefix)
                    .font(.system(size: 12.5))
                    .foregroundColor(AgentChatColor.hex(0x6B7079))
                    .frame(minWidth: prefix.count > 2 ? 20 : 10, alignment: .leading)
                Text(inlineAttributed(text))
                    .font(.system(size: 12.5))
                    .foregroundColor(AgentChatColor.hex(0xB0B5BE))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(indent) * 12)

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(AgentChatColor.hex(0x4B5563))
                    .frame(width: 2)
                    .clipShape(Capsule())
                Text(inlineAttributed(text))
                    .font(.system(size: 12.5))
                    .foregroundColor(AgentChatColor.hex(0x8A8F98))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

        case .rule:
            Divider().opacity(0.3)
        }
    }

    private func inlineAttributed(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

// MARK: - Copy button

private struct AgentCodeCopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundColor(copied ? AgentChatColor.hex(0x22C55E) : AgentChatColor.hex(0x6B7079))
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
