import AppKit
import SwiftUI

struct LocalChatPrompt: View {
    @ObservedObject var chat: LocalChatViewModel
    let conversation: LocalChatConversation
    var compact: Bool
    var active: Bool
    @Environment(\.islandPreview) private var preview
    @State private var followsReply = true
    private var working: Bool { chat.generatingID == conversation.id }

    var body: some View {
        ZStack(alignment: .leading) {
            AgentChatBackground()
            AgentChatCompanion(state: chat.states[conversation.id] ?? .ready, active: active,
                size: 70, conversationID: conversation.id, failureID: chat.failures[conversation.id],
                submissionID: chat.submitted[conversation.id])
                .padding(.leading, 8).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(chat.modelName).lineLimit(1)
                    Spacer(minLength: 0)
                    if preview { Label("Follow reply", systemImage: followsReply ? "checkmark.circle.fill" : "circle") }
                    else { Toggle("Follow reply", isOn: $followsReply).toggleStyle(.checkbox) }
                }.font(.system(size: 10.5)).foregroundStyle(Color(white: 0.55))
                transcript
                if !chat.readiness.available { availability }
                if let notice = chat.notice {
                    HStack(alignment: .top, spacing: 6) {
                        Text(notice).lineLimit(3).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { chat.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.font(.system(size: 10.5)).foregroundStyle(CompanionStyle.muted)
                }
                picker
                composer
            }.padding(.leading, 84).padding(.trailing, 16).padding(.top, 14).padding(.bottom, 16)
        }.frame(height: compact ? nil : 320).frame(maxHeight: compact ? .infinity : nil)
            .preferredColorScheme(.dark).padding(.bottom, 10)
    }
    private var transcript: some View {
        Group {
            if preview {
                GeometryReader { size in
                    VStack(alignment: .leading, spacing: 6) { rows }
                        .frame(width: size.size.width, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
                        .frame(height: size.size.height, alignment: .top).clipped()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 6) { rows }.padding(.vertical, 2)
                    }
                    .onChange(of: conversation.messages) { _, _ in if followsReply { proxy.scrollTo("chat-bottom", anchor: .bottom) } }
                    .onChange(of: conversation.id) { _, _ in proxy.scrollTo("chat-bottom", anchor: .bottom) }
                    .onAppear { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder private var rows: some View {
        if conversation.messages.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("A small next step, together.").font(.system(size: 14, weight: .semibold))
                Text("Ask a question, paste a small code excerpt, or tell me where you’re stuck.")
                    .font(.system(size: 12)).foregroundStyle(CompanionStyle.muted)
            }.padding(.top, 18)
        }
        ForEach(conversation.messages.filter { $0.role != .system }) { message in
            AgentChatBubble(message: CodingMessage(id: message.id, role: message.role == .user ? .user : .assistant, text: message.text),
                isStreaming: working && message.id == conversation.messages.last?.id)
                .id(message.id)
        }
        if working && conversation.messages.last?.text.isEmpty == true {
            HStack {
                if active { AgentTypingDots() }
                Text(chat.configuration.mode == .privateCloudThinking ? "Ada is thinking…" : "Ada is replying…").font(.caption)
                Spacer(minLength: 32)
            }
        }
        Color.clear.frame(height: 1).id("chat-bottom")
    }
    private var availability: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(chat.readiness.reason ?? "The on-device model is unavailable.").font(.system(size: 10.5)).textSelection(.enabled)
            HStack {
                Button("Check again") { Task { await chat.prepare() } }
                Button("Apple Intelligence settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!) }
            }.font(.system(size: 10.5))
        }.foregroundStyle(CompanionStyle.muted)
    }
    private var picker: some View {
        HStack {
            Spacer()
            if preview { pickerLabel.frame(maxWidth: 260) }
            else {
                Menu {
                    ForEach(chat.conversations) { value in Button(value.title) { chat.select(value.id) } }
                    Divider()
                    Button("New chat") { Task { _ = await chat.create() } }
                    Button("Delete this conversation", role: .destructive) { Task { await chat.delete(conversation.id) } }
                } label: { pickerLabel }.menuStyle(.borderlessButton).frame(maxWidth: 260)
            }
        }
    }
    private var pickerLabel: some View {
        HStack(spacing: 5) {
            Circle().fill(CompanionStyle.accent).frame(width: 6, height: 6)
            Text(conversation.title).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
        }.font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color(white: 0.6))
            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.white.opacity(0.06), in: Capsule())
    }
    private var composer: some View {
        HStack(spacing: 8) {
            if preview {
                Text(chat.drafts[conversation.id].flatMap { $0.isEmpty ? nil : $0 } ?? "Ask Ada anything…")
                    .font(.system(size: 13)).foregroundStyle(Color(white: 0.7)).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AgentChatComposer(text: Binding(get: { chat.drafts[conversation.id] ?? "" }, set: { chat.drafts[conversation.id] = $0 }),
                    focusID: conversation.id, placeholder: "Ask Ada anything…") { chat.send(to: conversation.id) }
                    .frame(height: 28)
            }
            if working {
                Button { chat.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 11)).foregroundStyle(.black) }
                    .buttonStyle(AgentChatSendStyle()).help("Stop reply").accessibilityLabel("Stop reply")
            } else {
                Button { chat.send(to: conversation.id) } label: { Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(.black) }
                    .buttonStyle(AgentChatSendStyle()).disabled(!chat.canSend).opacity(chat.canSend ? 1 : 0.4)
                    .help(chat.generatingID == nil ? "Send message" : "Another conversation is replying. Wait or stop that reply.")
                    .accessibilityLabel("Send message to Ada")
            }
        }.padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
