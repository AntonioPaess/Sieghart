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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { room.page = .room } label: {
                    Label("Rooms", systemImage: "square.grid.2x2")
                        .foregroundStyle(room.page == .room ? CompanionStyle.accentInk : CompanionStyle.muted)
                }.buttonStyle(.plain)
                Button {
                    Task {
                        if chat.selected == nil { _ = await chat.create() }
                        room.page = .chat
                    }
                } label: {
                    Label("Chat", systemImage: "bubble.left")
                        .foregroundStyle(room.page == .chat ? CompanionStyle.accentInk : CompanionStyle.muted)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                Label(chat.configuration.mode.shortTitle, systemImage: "apple.intelligence")
                    .foregroundStyle(CompanionStyle.muted)
                    .help(chat.configuration.mode.explanation)
                Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("Ada settings · model, thinking and GitHub")
                    .accessibilityLabel("Ada settings")
            }.font(.system(size: 11, weight: .medium)).frame(height: 22)
            if room.page == .room {
                LocalChatRooms(chat: chat, compact: compact) { id in chat.select(id); room.page = .chat }
                    .frame(height: compact ? nil : 370)
            } else if let selected = chat.selected {
                LocalChatPrompt(chat: chat, conversation: selected, compact: compact, active: active)
            } else {
                VStack(spacing: 12) {
                    CompanionCharacter(size: 64, avatar: .ada, animates: false)
                    Text("A small next step, together.").font(.headline)
                    Button("New chat") { Task { _ = await chat.create(); room.page = .chat } }
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
    @State private var page = 0
    private let pageSize = 5
    private var pages: Int { max(1, (chat.conversations.count + pageSize - 1) / pageSize) }
    private var visible: [LocalChatConversation] { Array(chat.conversations.dropFirst(page * pageSize).prefix(pageSize)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Choose a conversation, or start a new one.").font(.caption).foregroundStyle(CompanionStyle.muted)
                Spacer(minLength: 0)
                if pages > 1 {
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }.disabled(page == 0)
                    Text("\(page + 1) / \(pages)").font(.system(size: 10))
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
                        Image(systemName: "plus").font(.system(size: 24, weight: .light)).foregroundStyle(CompanionStyle.accentInk)
                        Text("New chat").font(.system(size: 11, weight: .medium)).foregroundStyle(CompanionStyle.muted)
                    }.frame(maxWidth: .infinity).frame(height: compact ? 120 : 150)
                        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(CompanionStyle.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                        .contentShape(RoundedRectangle(cornerRadius: 15))
                }.buttonStyle(.plain).disabled(chat.loading).accessibilityLabel("Create a new local conversation with Ada")
            }
            if let notice = chat.notice { Text(notice).font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(2).textSelection(.enabled) }
            if chat.conversations.isEmpty {
                Text(chat.loading ? "Reading saved conversations…" : "Talk directly to Ada. Choose her Apple model and connect GitHub in Ada settings.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: chat.conversations.count) { _, _ in page = min(page, pages - 1) }
    }
    private func card(_ conversation: LocalChatConversation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                CompanionCharacter(size: compact ? 48 : 64, avatar: .ada, animates: false)
                Spacer()
            }.frame(height: compact ? 54 : 72)
            Text(conversation.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Text(chat.generatingID == conversation.id ? "Replying…" : conversation.messages.last?.text ?? "A new conversation with Ada")
                .font(.system(size: 10)).foregroundStyle(CompanionStyle.muted).lineLimit(2)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).frame(height: compact ? 120 : 150)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(chat.selectedID == conversation.id ? CompanionStyle.accent.opacity(0.4) : Color.white.opacity(0.065)))
            .contentShape(RoundedRectangle(cornerRadius: 15))
    }
}
