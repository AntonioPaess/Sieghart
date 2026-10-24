import SwiftUI

// Sieg owns these conversations. Coucou's MIT chat layout and interaction are
// reused through AgentChatBackground, AgentChatBubble and AgentChatComposer;
// generation uses Apple's on-device model or Private Cloud Compute with thinking.
struct AgentRoomView: View {
    @ObservedObject var model: AgentRoomViewModel
    var compact = false
    var observesActivity = true

    var body: some View {
        LocalAgentRoomView(room: model, chat: model.localChat, compact: compact, active: observesActivity)
    }
}

private struct LocalAgentRoomView: View {
    @ObservedObject var room: AgentRoomViewModel
    @ObservedObject var chat: LocalChatViewModel
    var compact: Bool
    var active: Bool
    @Environment(\.islandPreview) private var preview
    @State private var settings = false
    @Environment(\.locale) private var locale
    private var en: Bool { locale.language.languageCode?.identifier == "en" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Button { room.page = .room } label: {
                        Label(en ? "Conversations" : "Conversas", systemImage: "square.grid.2x2")
                            .font(AdaRoomTheme.badgeFont(size: 11))
                            .foregroundStyle(room.page == .room ? CompanionStyle.ink : CompanionStyle.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background {
                                if room.page == .room {
                                    Capsule().fill(CompanionStyle.accent.opacity(0.16))
                                }
                            }
                    }.buttonStyle(.plain)

                    Button {
                        Task {
                            if chat.selected == nil { _ = await chat.create() }
                            room.page = .chat
                        }
                    } label: {
                        Label(en ? "Chat" : "Conversa", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(AdaRoomTheme.badgeFont(size: 11))
                            .foregroundStyle(room.page == .chat ? CompanionStyle.ink : CompanionStyle.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background {
                                if room.page == .chat {
                                    Capsule().fill(CompanionStyle.accent.opacity(0.16))
                                }
                            }
                    }.buttonStyle(.plain)
                }
                .padding(2.5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7) }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Image(systemName: "apple.intelligence")
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.52, green: 0.62, blue: 1.0),
                                    Color(red: 0.78, green: 0.48, blue: 0.98)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(en ? chat.configuration.mode.shortTitle : (chat.configuration.mode == .privateCloudThinking ? "Apple Cloud" : "Neste Mac"))
                        .font(AdaRoomTheme.badgeFont(size: 10.5))
                        .foregroundStyle(CompanionStyle.ink.opacity(0.85))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7) }
                .help(chat.configuration.mode.explanation)

                Button { settings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CompanionStyle.ink.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7) }
                }
                .buttonStyle(.plain)
                .help(en ? "Conversation settings · model and GitHub" : "Configurações das conversas · modelo e GitHub")
                .accessibilityLabel(en ? "Conversation settings" : "Configurações das conversas")
            }.frame(height: 26)
            if room.page == .room {
                LocalChatRooms(chat: chat, compact: compact) { id in chat.select(id); room.page = .chat }
                    .frame(height: compact ? nil : 370)
            } else if let selected = chat.selected {
                LocalChatPrompt(chat: chat, conversation: selected, compact: compact, active: active)
            } else {
                VStack(spacing: 12) {
                    CompanionCharacter(size: 56, avatar: .sig, animates: false)
                    Text(en ? "A small next step, together." : "Um próximo passo, juntos.")
                        .font(AdaRoomTheme.titleFont(size: 15))
                    Button(en ? "New chat" : "Nova conversa") { Task { _ = await chat.create(); room.page = .chat } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(CompanionStyle.ink)
        .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil, alignment: .topLeading)
        .tint(CompanionStyle.accentInk)
        .buttonStyle(CompanionButtonStyle(compact: true))
        .focusEffectDisabled()
        .task { if !preview { await chat.prepare() } }
        .sheet(isPresented: $settings) { AdaChatSettingsView(chat: chat) }
    }
}

private struct LocalChatRooms: View {
    @ObservedObject var chat: LocalChatViewModel
    var compact: Bool
    var open: (String) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.islandPreview) private var preview
    private var en: Bool { locale.language.languageCode?.identifier == "en" }
    @State private var page = 0
    private let pageSize = 5
    private var pages: Int { max(1, (chat.conversations.count + pageSize - 1) / pageSize) }
    private var visible: [LocalChatConversation] { Array(chat.conversations.dropFirst(page * pageSize).prefix(pageSize)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Choose a conversation, or start a new one.")
                    .font(AdaRoomTheme.bodyFont(size: 11.5))
                    .foregroundStyle(CompanionStyle.muted)
                if preview {
                    Label(en ? "Talk to…" : "Conversar com…", systemImage: "chevron.down")
                        .font(WorkspaceTypography.caption).foregroundStyle(CompanionStyle.accentInk)
                } else {
                    Menu("Talk to…") {
                        ForEach(LocalChatPersona.allCases, id: \.rawValue) { persona in
                            Button(persona.title + " · " + persona.avatar.subtitle) {
                                Task { if let id = await chat.create(persona) { open(id) } }
                            }
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Spacer(minLength: 0)
                if pages > 1 {
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }.disabled(page == 0)
                    Text("\(page + 1) / \(pages)").font(AdaRoomTheme.badgeFont(size: 10))
                    Button { page = min(pages - 1, page + 1) } label: { Image(systemName: "chevron.right") }.disabled(page + 1 >= pages)
                }
            }.frame(height: 22)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(visible) { conversation in
                    Button { open(conversation.id) } label: { card(conversation) }.buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete conversation", role: .destructive) { Task { await chat.delete(conversation.id) } }
                        }
                }
                Button {
                    Task { if let id = await chat.create() { open(id) } }
                } label: {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(CompanionStyle.accent.opacity(0.18))
                                .frame(width: 38, height: 38)
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(CompanionStyle.accentInk)
                        }
                        Text(en ? "New chat" : "Nova conversa")
                            .font(AdaRoomTheme.badgeFont(size: 11.5))
                            .foregroundStyle(CompanionStyle.ink.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 120 : 150)
                    .modifier(WorkspaceSurface(radius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                CompanionStyle.accentInk.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain).disabled(chat.loading).accessibilityLabel(en ? "Create a new conversation with Sieg" : "Criar uma nova conversa com o Sieg")
            }
            if let notice = chat.notice {
                Text(notice)
                    .font(AdaRoomTheme.badgeFont(size: 11))
                    .foregroundStyle(CompanionStyle.muted)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if chat.conversations.isEmpty {
                Text(chat.loading ? (en ? "Reading saved conversations…" : "Lendo suas conversas…") : (en ? "Start with Sieg. Your specialists are a conversation away." : "Comece com o Sieg. Seus especialistas estão a uma conversa de distância."))
                    .font(AdaRoomTheme.bodyFont(size: 11.5))
                    .foregroundStyle(CompanionStyle.muted)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: chat.conversations.count) { _, _ in page = min(page, pages - 1) }
    }
    private func card(_ conversation: LocalChatConversation) -> some View {
        let isSelected = chat.selectedID == conversation.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                CompanionCharacter(size: compact ? 38 : 48, avatar: conversation.persona.avatar, animates: false)
                Spacer()
            }.frame(height: compact ? 50 : 66)
            Text(conversation.title)
                .font(AdaRoomTheme.titleFont(size: 11.5))
                .foregroundStyle(CompanionStyle.ink)
                .lineLimit(1)
            Text(chat.generatingID == conversation.id ? (en ? "Replying…" : "Respondendo…") : conversation.messages.last?.text ?? (en ? "Start a conversation with \(conversation.persona.title)." : "Comece uma conversa com \(conversation.persona.title)."))
                .font(AdaRoomTheme.bodyFont(size: 10.5))
                .foregroundStyle(CompanionStyle.muted)
                .lineLimit(2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: compact ? 120 : 150)
        .modifier(WorkspaceSurface(selected: isSelected, radius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
