import SwiftUI

struct CompanionWorkspaceHome: View {
    @ObservedObject var room: AgentRoomViewModel
    @ObservedObject var chat: LocalChatViewModel
    @ObservedObject var coordinator: SpatialAssistantCoordinator
    let language: String
    let animates: Bool
    let openChat: () -> Void
    let speak: () -> Void
    let settings: () -> Void
    @Environment(\.islandPreview) private var preview
    @State private var query = ""
    @State private var showArchived = false
    @State private var hovered: LocalChatPersona?
    @State private var tutorial = false
    @State private var workflow = false
    private var en: Bool { language.hasPrefix("en") }
    private var conversations: [LocalChatConversation] { chat.matchingConversations(query, archived: showArchived) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(en ? "What shall we start with?" : "Por onde vamos começar?").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.3)
                    Text(en ? "Ask a question, bring a task or pick up where you left off." : "Tire uma dúvida, traga uma tarefa ou retome de onde parou.").font(WorkspaceTypography.body).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                Button(action: speak) { Label(en ? "Talk to Sieg" : "Falar com o Sieg", systemImage: "mic.fill") }.buttonStyle(CompanionButtonStyle(primary: true))
            }
            Text(en ? "Your team" : "Sua equipe").font(WorkspaceTypography.section)
            HStack(spacing: 10) {
                ForEach([LocalChatPersona.sig, .rita, .ada, .gantt, .elinor, .toni], id: \.self) { person in
                    Button {
                        Task { if await chat.openPersona(person) != nil { room.page = .chat; openChat() } }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottomTrailing) {
                                CompanionCharacter(size: 57, avatar: person.avatar, animates: animates && hovered == person,
                                    voicePhase: isWorking(person) ? .working : .inactive)
                                if isWorking(person) {
                                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                                        .overlay(Circle().stroke(CompanionStyle.surface, lineWidth: 2))
                                }
                            }
                            Text(person.title).font(.callout.weight(.medium))
                            Text(isWorking(person) ? (en ? "Working" : "Trabalhando") : role(person)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity).padding(.vertical, 15)
                            .modifier(WorkspaceSurface(selected: hovered == person, radius: 16))
                    }.buttonStyle(.plain).onHover { hovered = $0 ? person : nil }
                        .popover(isPresented: Binding(get: { hovered == person }, set: { if !$0 { hovered = nil } }), arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(person.title).font(.headline)
                                Text(isWorking(person) ? (en ? "Preparing a reply…" : "Preparando uma resposta…") : role(person)).font(.caption).foregroundStyle(.secondary)
                                if let recent = chat.matchingConversations(persona: person).first {
                                    Text(recent.title).font(.callout).lineLimit(2)
                                    Text(AdaThoughtDisclosure.parse(recent.messages.last?.text ?? "").visibleReply).font(.caption).lineLimit(3)
                                }
                            }.padding(16).frame(width: 245)
                        }
                }
            }
            HStack {
                Text(en ? "Conversations" : "Conversas").font(WorkspaceTypography.section)
                Spacer()
                Button(en ? "Work in stages" : "Trabalho em etapas") { workflow = true }
                Toggle(en ? "Archived" : "Arquivadas", isOn: $showArchived).toggleStyle(.checkbox)
                Menu {
                    ForEach(LocalChatPersona.allCases, id: \.self) { person in
                        Button(person.title) { Task { if await chat.create(person) != nil { room.page = .chat; openChat() } } }
                    }
                } label: { Label(en ? "New conversation" : "Nova conversa", systemImage: "plus") }
            }
            if preview {
                Text(en ? "Search titles and messages" : "Buscar nos títulos e nas mensagens").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CompanionStyle.muted)
                    TextField(en ? "Search conversations" : "Buscar conversas", text: $query).textFieldStyle(.plain)
                }.font(WorkspaceTypography.body).padding(11).modifier(WorkspaceSurface(radius: 11))
            }
            if conversations.isEmpty {
                WorkspaceEmptyState(title: en ? "A conversation starts here" : "Uma conversa começa aqui", detail: en ? "Choose Sieg or a specialist above. Your history stays close by." : "Escolha o Sieg ou um especialista acima. Seu histórico fica sempre por perto.", symbol: "bubble.left.and.bubble.right")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(conversations) { conversation in
                    Button {
                        chat.select(conversation.id); room.page = .chat; openChat()
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                CompanionCharacter(size: 26, avatar: conversation.persona.avatar, animates: false)
                                Text(conversation.persona.title).font(.caption.weight(.medium))
                                Spacer()
                                if conversation.pinned == true { Image(systemName: "pin.fill").font(.caption).foregroundStyle(CompanionStyle.accentInk) }
                            }
                            Text(conversation.title).font(.callout.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Text(AdaThoughtDisclosure.parse(conversation.messages.last?.text ?? (en ? "Start a conversation" : "Comece uma conversa")).visibleReply).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(conversation.updatedAt, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
                            .modifier(WorkspaceSurface())
                    }.buttonStyle(.plain).contextMenu {
                        Button(conversation.pinned == true ? (en ? "Unpin" : "Desafixar") : (en ? "Pin" : "Fixar")) { Task { await chat.setPinned(conversation.id, conversation.pinned != true) } }
                        Button(showArchived ? (en ? "Restore" : "Restaurar") : (en ? "Archive" : "Arquivar")) { Task { await chat.setArchived(conversation.id, !showArchived) } }.disabled(chat.generatingID == conversation.id)
                    }
                }
            }
            CompanionTaskShelf(journal: coordinator.taskJournal, language: language, resume: { coordinator.resumeTask($0) }, pause: { coordinator.pauseTask($0) }).companionCard()
            CompanionRoutineShelf(routines: coordinator.routines, language: language)
            CompanionArtifactShelf(library: coordinator.artifacts, language: language)
            if coordinator.screenAccessIssue == .permission { ScreenPermissionHelp(language: language).companionCard() }
            HStack {
                Button(en ? "Learn the gestures" : "Aprender os gestos") { tutorial = true }
                Spacer()
                Button(en ? "Inputs and permissions" : "Ativação e permissões", action: settings)
            }.font(.callout)
        }.task { await chat.prepare() }
            .sheet(isPresented: $workflow) { CompanionWorkflowComposer(runner: coordinator.workflows, language: language) }
            .sheet(isPresented: $tutorial) { CompanionVoiceTutorial(language: language) }
    }
    private func isWorking(_ person: LocalChatPersona) -> Bool {
        if chat.generatingID.flatMap({ id in chat.conversations.first { $0.id == id }?.persona }) == person { return true }
        return coordinator.taskJournal.tasks.contains { task in
            task.state == .running && task.workflow?.first(where: { $0.result == nil }).map { $0.kind == .research ? person == .sig : $0.persona == person } == true
        }
    }
    private func role(_ person: LocalChatPersona) -> String {
        switch person {
        case .sig: en ? "Your coordinator" : "Seu coordenador"
        case .ada: en ? "Code" : "Código"
        case .rita: en ? "Focus and breaks" : "Foco e pausas"
        case .gantt: en ? "Your day" : "Seu dia"
        case .elinor: en ? "Resources" : "Recursos"
        case .toni: en ? "Files and writing" : "Arquivos e escrita"
        }
    }
}
