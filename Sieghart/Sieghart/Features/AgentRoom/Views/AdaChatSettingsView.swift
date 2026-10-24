import SwiftUI

struct AdaChatSettingsView: View {
    @ObservedObject var chat: LocalChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.islandPreview) private var preview

    var body: some View {
        ZStack {
            AgentChatBackground()
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.38, green: 0.46, blue: 0.98).opacity(0.32),
                                        Color(red: 0.64, green: 0.36, blue: 0.96).opacity(0.22)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 46, height: 46)
                        CompanionCharacter(size: 36, avatar: chat.selected?.persona.avatar ?? .sig, animates: false)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conversation settings")
                            .font(AdaRoomTheme.titleFont(size: 16))
                            .foregroundStyle(CompanionStyle.ink)
                        Text("Choose where replies are generated and connect GitHub for Ada.")
                            .font(AdaRoomTheme.bodyFont(size: 11.5))
                            .foregroundStyle(CompanionStyle.muted)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(AdaRoomTheme.badgeFont(size: 12))
                }
                .padding(.bottom, 2)

                if preview {
                    settingsContents
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        settingsContents
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 500)
        .frame(height: preview ? nil : 580)
        .foregroundStyle(CompanionStyle.ink)
        .task { if !preview { await chat.github.restore() } }
    }

    private var settingsContents: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Apple Intelligence Engine", systemImage: "apple.intelligence")
                    .font(AdaRoomTheme.titleFont(size: 13))
                    .foregroundStyle(CompanionStyle.ink)

                VStack(spacing: 8) {
                    ForEach(AppleChatMode.allCases, id: \.self) { mode in
                        let isSelected = chat.configuration.mode == mode
                        Button {
                            chat.configure(mode: mode)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(
                                        isSelected
                                            ? CompanionStyle.accentInk
                                            : CompanionStyle.muted
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(mode.title))
                                        .font(AdaRoomTheme.titleFont(size: 12.5))
                                        .foregroundStyle(CompanionStyle.ink)
                                    Text(mode == .onDevice ? "Runs on this Mac when Apple Intelligence is available" : "Apple Cloud reasoning for more involved questions")
                                        .font(AdaRoomTheme.bodyFont(size: 10.5))
                                        .foregroundStyle(CompanionStyle.muted)
                                }
                                Spacer()
                            }
                            .padding(11)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        isSelected
                                            ? Color(red: 0.50, green: 0.60, blue: 0.98).opacity(0.65)
                                            : CompanionStyle.edge.opacity(0.10),
                                        lineWidth: isSelected ? 1.2 : 0.8
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(chat.generatingID != nil)
                    }
                }

                Text(LocalizedStringKey(chat.configuration.mode.explanation))
                    .font(AdaRoomTheme.bodyFont(size: 11))
                    .foregroundStyle(CompanionStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if chat.configuration.mode == .privateCloudThinking {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reasoning Depth")
                            .font(AdaRoomTheme.badgeFont(size: 11))
                            .foregroundStyle(CompanionStyle.ink.opacity(0.85))
                        HStack(spacing: 6) {
                            ForEach(AppleChatReasoning.allCases, id: \.self) { value in
                                let selected = chat.configuration.reasoning == value
                                Button {
                                    chat.configure(reasoning: value)
                                } label: {
                                    Text(LocalizedStringKey(value.title))
                                        .font(AdaRoomTheme.badgeFont(size: 11))
                                        .foregroundStyle(selected ? CompanionStyle.ink : CompanionStyle.muted)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background {
                                            if selected {
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .fill(CompanionStyle.accent.opacity(0.20))
                                            } else {
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .fill(CompanionStyle.edge.opacity(0.05))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .disabled(chat.generatingID != nil)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                if let reason = chat.readiness.reason {
                    Text(reason)
                        .font(AdaRoomTheme.bodyFont(size: 11))
                        .foregroundStyle(CompanionStyle.muted)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Check model status") { Task { await chat.prepare() } }
                    if chat.configuration.mode == .privateCloudThinking {
                        Spacer()
                        if preview {
                            Text("Apple Cloud access").foregroundStyle(CompanionStyle.accentInk)
                        } else {
                            Link("Apple Cloud access", destination: URL(string: "https://developer.apple.com/private-cloud-compute/")!)
                        }
                    }
                }
                .font(AdaRoomTheme.badgeFont(size: 11))
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(CompanionStyle.edge.opacity(0.10), lineWidth: 0.8)
            }

            AdaGitHubConnectionView(model: chat.github)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(CompanionStyle.edge.opacity(0.10), lineWidth: 0.8)
                }

            Text("Sieg keeps your conversations together. Ada helps with code and mathematics; screen access and online tools use their own permissions.")
                .font(AdaRoomTheme.bodyFont(size: 11))
                .foregroundStyle(CompanionStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
