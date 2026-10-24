import AppKit
import Combine
import SwiftUI

struct NotchWidgetView: View {
    @EnvironmentObject private var notch: NotchWidgetViewModel
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var activation: ActivationController
    @EnvironmentObject private var preferences: CompanionPreferences
    @EnvironmentObject private var aiActivity: AIUsageViewModel
    @StateObject private var reactions = CompanionReactions()
    @State private var avatarPointer = CGSize.zero
    private var scrollable: Bool

    init(reactions: CompanionReactions = CompanionReactions(), scrollable: Bool = true) {
        _reactions = StateObject(wrappedValue: reactions)
        self.scrollable = scrollable
    }

    private var panelScale: CGFloat { notch.presentation == .island ? 1 : preferences.widgetSize.scale }

    @Environment(\.nativeIslandCanvas) private var nativeCanvas
    @Environment(\.islandPreview) private var staticPreview
    private var compact: Bool { notch.presentation == .island }
    private var gutter: CGFloat { compact ? 0 : 72 }
    private var bottomInset: CGFloat { compact ? 0 : 64 }

    var body: some View {
        ZStack(alignment: .top) {
            surface
                .frame(width: notch.geometry.width, height: notch.geometry.height, alignment: .top)
            if !compact { quickAccess }
        }
        .frame(width: notch.geometry.width + gutter * 2, height: notch.geometry.height + bottomInset, alignment: .top)
        .foregroundStyle(compact ? Color.white : CompanionStyle.ink)
        .tint(CompanionStyle.accent)
        .preferredColorScheme(compact ? .dark : preferences.appearance.colorScheme)
        .environment(\.surfaceGlassEnabled, preferences.islandGlass)
        .environment(\.locale, Locale(identifier: activation.voiceLanguage))
        .environment(\.islandGlass, !compact)
        .environment(\.islandReduceMotion, preferences.usesReducedMotion)
        .environment(\.companionMotionEnabled, preferences.characterMotion)
        .onHover { notch.setPointerInsidePanel($0) }
        .overlay { if !staticPreview { IslandFileDropOverlay(notch: notch) } }
        .focusEffectDisabled()
        .onExitCommand { if notch.welcomeStartedAt != nil { notch.finishWelcome() } else { notch.hide() } }
        .onChange(of: notch.utilityReaction) { _, _ in reactions.utility(notch.utilitySucceeded) }
        .onChange(of: preferences.avatar) { _, _ in reactions.reset() }
        .onChange(of: notch.presentation) { _, presentation in if presentation != .home { reactions.reset(); notch.finishWelcome(); notch.fileReceiverPageDidChange() } }
    }

    private var surface: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.geometry.contentTop).allowsHitTesting(false)
            VStack(spacing: 14) {
                if !compact { pageHeader }
                switch notch.presentation {
                case .home: home
                case .focusSetup: pageScroll { setup }
                case .timer: timer
                case .completion: completion
                case .island: island
                case .celebration: celebration
                case .tools: tools
                case .calendar: pageScroll { CalendarView(model: notch.calendar, events: notch.events, compact: true, island: true) }
                case .files: pageScroll { FilesView(model: notch.files) }
                case .capture: pageScroll { CaptureToolsView(model: notch.capture) }
                case .clipboard: ClipboardHistoryView(clipboard: notch.clipboard, showsTitle: false, listHeight: 180, dismiss: { notch.hide() })
                case .system: pageScroll { SystemMonitorView(monitor: notch.monitor) }
                case .keepAwake: pageScroll { KeepAwakeView(controller: notch.keepAwake) }
                case .displayPower: pageScroll { DisplayPowerView(controller: notch.displayPower) }
                case .audio: pageScroll { AudioControlsView().environmentObject(notch.audio) }
                case .avatars: CompanionTeamGallery(animates: animates, compact: true, onAda: { notch.showAgentRoom() })
                case .aiLimits:
                    pageScroll { AIUsageView(showsHeader: false, onOpenRoom: { notch.showAgentRoom() }) }
                case .agentRoom: AgentRoomView(model: notch.agentRoom, compact: true, observesActivity: notch.isVisible)
                }
            }
            .padding(.horizontal, compact ? 0 : 44)
            .padding(.vertical, compact ? 0 : 28)
            .frame(width: notch.geometry.width / panelScale, height: notch.geometry.bodyHeight / panelScale, alignment: .top)
            .scaleEffect(panelScale, anchor: .top)
            .frame(width: notch.geometry.width, height: notch.geometry.bodyHeight, alignment: .top)
        }
        .background {
            if !nativeCanvas { IslandBackdrop(compact: compact, stripHeight: notch.geometry.cutoutHeight, glassEnabled: preferences.islandGlass) }
        }
        .clipShape(NotchPanelShape())
        .contentShape(NotchPanelShape())
        .animation(preferences.usesReducedMotion ? nil : .easeOut(duration: 0.15), value: notch.isPointerHovering)
    }

    @ViewBuilder private func pageScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if scrollable { ScrollView(.vertical) { content() }.scrollIndicators(.hidden) }
        else { content().fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped() }
    }

    private var pageHeader: some View {
        HStack {
            Text(pageTitle).font(.system(size: 20, weight: .semibold))
            Spacer()
            if notch.welcomeStartedAt != nil {
                Button(activation.voiceLanguage.hasPrefix("en") ? "Skip introduction" : "Pular apresentação") { notch.finishWelcome() }
                    .buttonStyle(CompanionButtonStyle(compact: true))
                    .help(activation.voiceLanguage.hasPrefix("en") ? "Continue now. You can replay the introduction in settings." : "Continue agora. A apresentação pode ser revista nas preferências.")
            }
            if staticPreview {
                HStack(spacing: 5) { Image(systemName: "ellipsis"); Image(systemName: "chevron.down").font(.caption2.weight(.bold)) }
            } else { Menu {
                Button("Companion") { notch.show() }
                Button("Timers") { notch.showTimer() }
                Button("AI agents") { notch.showAILimits() }
                Button("Ada’s room") { notch.showAgentRoom() }
                Button("System") { notch.showSystem() }
                Button("Keep awake") { notch.showKeepAwake() }
                Button("Display & power") { notch.showDisplayPower() }
                Button("Audio") { notch.showAudio() }
                Button("Clipboard") { notch.showClipboard() }
                Button("Calendar") { notch.showCalendar() }
                Button("Files") { notch.showFiles() }
                Button("Downloads") { notch.showFiles(downloads: true) }
                Button("Capture") { notch.showCapture() }
                Button("Tools") { notch.showTools() }
                Divider()
                Button("Close") { notch.hide() }
            } label: {
                HStack(spacing: 5) { Image(systemName: "ellipsis"); Image(systemName: "chevron.down").font(.caption2.weight(.bold)) }
            }.menuStyle(.borderlessButton).fixedSize().focusEffectDisabled().accessibilityLabel("Island pages") }
        }.frame(height: 24)
    }

    private var pageTitle: String {
        if activation.voiceLanguage.hasPrefix("en") { return englishPageTitle }
        if notch.presentation == .agentRoom { return notch.agentRoom.page == .chat ? "Conversa com " + (notch.agentRoom.localChat.selected?.persona.title ?? "Sieg") : "Conversas" }
        return ["Companion": "Sieg", "Timers": "Timers", "AI agents": "Uso de IA", "Your tools": "Suas ferramentas", "System": "Sistema", "Keep awake": "Keep Awake", "Display & power": "Tela e energia", "Audio": "Áudio", "Clipboard": "Área de transferência", "Calendar": "Agenda", "Files": "Arquivos", "Capture": "Captura", "Your team": "Sua equipe", "Session complete": "Sessão concluída"][englishPageTitle] ?? englishPageTitle
    }
    private var englishPageTitle: String {
        switch notch.presentation {
        case .home: "Companion"
        case .focusSetup, .timer: "Timers"
        case .aiLimits: "AI agents"
        case .agentRoom: notch.agentRoom.page == .chat ? "Chat with " + (notch.agentRoom.localChat.selected?.persona.title ?? "Sieg") : "Conversations"
        case .tools: "Your tools"
        case .system: "System"
        case .keepAwake: "Keep awake"
        case .displayPower: "Display & power"
        case .audio: "Audio"
        case .clipboard: "Clipboard"
        case .calendar: "Calendar"
        case .files: "Files"
        case .capture: "Capture"
        case .avatars: "Your team"
        case .completion, .celebration: "Session complete"
        case .island: ""
        }
    }

    private var quickAccess: some View {
        let width = notch.geometry.width + 144
        return ZStack(alignment: .topLeading) {
            ForEach(0..<6) { slot in
                let action = preferences.railActions[slot]
                if action != .none {
                    floatingButton(action.symbol, label: action.rawValue) { activateRail(action) }
                        .position(x: slot < 3 ? 28 : width - 28, y: notch.geometry.contentTop + 52 + CGFloat(slot % 3) * 54)
                }
            }
            Button { notch.show() } label: {
                CompanionCharacter(size: 32, avatar: preferences.avatar, animates: animates, voicePhase: companionPhase(), mood: notch.utilityMood)
                    .frame(width: 44, height: 44).background(.black.opacity(0.6), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.75) }
            }.buttonStyle(IslandButtonStyle()).focusEffectDisabled().accessibilityLabel("Your companion")
                .position(x: width / 2, y: notch.geometry.height + 32)
        }.frame(width: width, height: notch.geometry.height + 64)
    }

    private func activateRail(_ action: IslandRailAction) {
        switch action {
        case .tools: notch.showTools()
        case .timer: notch.showTimer()
        case .clipboard: notch.showClipboard()
        case .calendar: notch.showCalendar()
        case .files: notch.showFiles()
        case .downloads: notch.showFiles(downloads: true)
        case .capture: notch.showCapture()
        case .preferences: notch.focusMainWindow()
        case .system: notch.showSystem()
        case .keepAwake: notch.showKeepAwake()
        case .displayPower: notch.showDisplayPower()
        case .audio: notch.showAudio()
        case .ai: notch.showAILimits()
        case .avatars: notch.showAvatars()
        case .voice: activation.toggleListening()
        case .companion: notch.show()
        case .none: break
        }
    }

    private func floatingButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(.black.opacity(0.95), in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.75) }
        }.buttonStyle(IslandButtonStyle()).focusEffectDisabled().accessibilityLabel(label).help(label)
    }

    private var animates: Bool { preferences.characterMotion && !preferences.usesReducedMotion && notch.isVisible }
    private func companionPhase() -> CompanionVoicePhase {
        // External agents and telemetry reads belong to their own dashboard.
        // The Companion reflects only an action it is handling for the user.
        activation.companionVoicePhase
    }
    private var face: some View {
        CompanionInteraction(action: { notch.show() }) {
            CompanionCharacter(avatar: preferences.avatar, animates: animates, focusing: assistant.isRunning && assistant.interval == .focus, listening: activation.isListening, voicePhase: companionPhase(), mood: activation.commandAcknowledged ? .understood : .idle)
        }.accessibilityLabel("Show companion")
    }

    @ViewBuilder private var home: some View {
        if notch.fileReceptionPhase != .idle {
            VStack(spacing: 8) {
                CompanionFileReceiver(model: notch.fileReception, animates: animates)
                if notch.fileReceptionPhase == .ready || notch.fileReceptionPhase == .failed {
                    CompanionFileAttachment(model: notch.fileReception, onFiles: { notch.showFiles() }, onPreview: { ref in
                        notch.showFiles(); Task { await notch.files.open(ref, preview: true) }
                    })
                }
            }
        } else if let start = notch.welcomeStartedAt {
            CompanionTeamArrival(animates: animates, started: start, language: preferences.introductionLanguage)
                .frame(height: CompanionHomeLayout.height)
                .contentShape(Rectangle()).onTapGesture { notch.finishWelcome() }
        } else { companionHome }
    }

    @ViewBuilder private var companionHome: some View {
        if let observation = notch.spatialAssistant.weatherObservation {
            CompanionWeatherScene(observation: observation, language: notch.spatialAssistant.responseLanguage, animates: animates,
                stop: notch.spatialAssistant.overlay.voiceSynthesizer.isSpeaking ? { notch.spatialAssistant.overlay.voiceSynthesizer.stop(); notch.spatialAssistant.screenInteraction.finishResponse() } : nil)
        } else { companionStandardHome }
    }
    private var companionStandardHome: some View {
        VStack(spacing: CompanionHomeLayout.rowSpacing) {
            HStack(spacing: 18) {
                CompanionInteraction(action: reactToTouch) {
                    CompanionCharacter(size: 96, avatar: preferences.avatar,
                                       animates: animates,
                                       listening: activation.isListening, voicePhase: companionPhase(), gaze: avatarPointer,
                                       mood: activation.commandAcknowledged ? .understood : activation.isVoiceBusy ? .idle : reactions.mood)
                        .frame(width: 124, height: 96)
                }
                .accessibilityLabel("Interact with Sieghart")
                .accessibilityValue(reactionDescription)
                .help("Say hello. Repeated taps make Sieghart grumpy, then sleepy. Tap again to wake.")
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): avatarPointer = animates ? CompanionGaze.sample(point: location, in: CGSize(width: 124, height: 96)) : .zero
                    case .ended: avatarPointer = .zero
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(activation.voicePresented ? (activation.voiceLanguage.hasPrefix("en") ? "YOUR COMPANION · VOICE" : "SEU COMPANHEIRO · VOZ") : assistant.hasActiveSession ? assistant.activityTitle.uppercased() : (activation.voiceLanguage.hasPrefix("en") ? "YOUR COMPANION" : "SEU COMPANHEIRO"))
                        .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(CompanionStyle.muted)
                    Text(homeHeadline).font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    homeMessageText.font(.callout).foregroundStyle(CompanionStyle.muted).lineLimit(2)
                    HStack(spacing: 12) {
                        Button { if activation.voicePresented { activation.cancelVoiceCommand(keepCompanionVisible: true) } else { activation.toggleListening() } } label: {
                            Label(activation.isVoiceBusy ? (activation.voiceLanguage.hasPrefix("en") ? "Cancel" : "Cancelar") : activation.voicePresented ? (activation.voiceLanguage.hasPrefix("en") ? "Back" : "Voltar") : (activation.voiceLanguage.hasPrefix("en") ? "Speak" : "Falar"), systemImage: activation.isListening ? "waveform" : "mic")
                        }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel(activation.voicePresented ? "Cancel voice and return to companion" : "Speak to your companion")
                        if activation.isConversing {
                            Button(activation.voiceLanguage.hasPrefix("en") ? "Stop conversation" : "Encerrar conversa") { activation.cancelVoiceCommand(keepCompanionVisible: true) }
                                .buttonStyle(.plain).foregroundStyle(.green)
                        }
                        else if activation.isListening { Text(activation.voiceLanguage.hasPrefix("en") ? "Speak or select an area." : "Fale ou marque uma região.") }
                        else if activation.voicePresented && !activation.transcript.isEmpty { Text(LocalizedStringKey(activation.voiceStatus)).lineLimit(1) }
                        else { Label(assistant.hasActiveSession ? assistant.pomodoroTimeLabel : "\(assistant.focusMinutes) min " + (activation.voiceLanguage.hasPrefix("en") ? "focus" : "de foco"), systemImage: "timer").monospacedDigit() }
                        if let document = notch.spatialAssistant.overlay.generatedCanvas, document.isCode {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(document.code, forType: .string)
                            } label: {
                                Label(activation.voiceLanguage.hasPrefix("en") ? "Copy code" : "Copiar código", systemImage: "doc.on.doc")
                            }.buttonStyle(.plain)
                        }
                        if notch.spatialAssistant.overlay.isPresentingOverlay {
                            Button { notch.spatialAssistant.overlay.dismiss() } label: {
                                Label("Fechar desenho", systemImage: "xmark.circle.fill")
                            }.buttonStyle(.plain).accessibilityLabel("Dismiss spatial overlay")
                        }
                        if notch.spatialAssistant.researchAgent.isResearching {
                            CircularResearchWidgetView(agent: notch.spatialAssistant.researchAgent, size: 28) {
                                notch.showAgentRoom()
                            }
                        }
                        if let pending = notch.spatialAssistant.systemExecutor.pendingConfirmation {
                            HStack(spacing: 6) {
                                Text(pending.title).lineLimit(1)
                                Button("Confirmar") { _ = notch.spatialAssistant.systemExecutor.confirmPendingAction() }.buttonStyle(.plain)
                                Button("Cancelar") { _ = notch.spatialAssistant.systemExecutor.cancelPendingAction() }.buttonStyle(.plain)
                            }
                        }
                    }.font(.caption.weight(.medium)).foregroundStyle(CompanionStyle.accentInk)
                }.frame(maxWidth: .infinity, alignment: .leading)

            }.frame(height: CompanionHomeLayout.heroSize)
            if let observation = notch.spatialAssistant.weatherObservation {
                CompanionWeatherCard(observation: observation, language: notch.spatialAssistant.responseLanguage,
                                     animates: animates, dismiss: { notch.spatialAssistant.dismissWeather() })
            } else if let response = notch.spatialAssistant.response {
                CompanionResponseCard(needsScreenPermission: notch.spatialAssistant.screenAccessIssue == .permission, retryScreen: { notch.spatialAssistant.retryScreenReading() }, response: response, language: notch.spatialAssistant.responseLanguage,
                    speaks: notch.spatialAssistant.overlay.voiceSynthesizer.isSpeaking,
                    stop: { notch.spatialAssistant.overlay.voiceSynthesizer.stop(); notch.spatialAssistant.screenInteraction.finishResponse() },
                    dismiss: { notch.spatialAssistant.dismissResponse() },
                    clearContext: { notch.spatialAssistant.clearConversationContext(); notch.spatialAssistant.dismissResponse() },
                    reviewSummary: notch.spatialAssistant.screenControls.pendingReview?.summary,
                    confirmReview: { notch.spatialAssistant.confirmScreenReview() },
                    cancelReview: { notch.spatialAssistant.screenControls.cancelReview() })
            }
            CompanionTeamDock(animates: animates, events: notch.events, onAda: { notch.showAgentRoom() }, onSelect: { member in
                Task { if await notch.agentRoom.localChat.openPersona(LocalChatPersona(rawValue: member.rawValue) ?? .sig) != nil {
                    notch.showAgentRoom(); notch.agentRoom.page = .chat
                } }
            })
        }.frame(height: CompanionHomeLayout.height + (notch.spatialAssistant.resultCardHeight == 0 ? 0 : notch.spatialAssistant.resultCardHeight + CompanionHomeLayout.rowSpacing), alignment: .top)
    }

    private var tools: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), spacing: 14) {
            ForEach(preferences.toolActions) { action in
                toolTile(action.rawValue, subtitle: action == .companion ? preferences.avatar.name : action.subtitle,
                         symbol: action.symbol, avatar: action == .companion ? preferences.avatar : nil) {
                    activateTool(action)
                }
            }
        }
    }

    private func activateTool(_ action: IslandToolAction) {
        switch action {
        case .companion: notch.show()
        case .audio: notch.showAudio()
        case .ai: notch.showAILimits()
        case .timer: notch.showTimer()
        case .clipboard: notch.showClipboard()
        case .calendar: notch.showCalendar()
        case .files: notch.showFiles()
        case .downloads: notch.showFiles(downloads: true)
        case .capture: notch.showCapture()
        case .avatars: notch.showAvatars()
        case .system: notch.showSystem()
        case .keepAwake: notch.showKeepAwake()
        case .displayPower: notch.showDisplayPower()
        case .preferences: notch.focusMainWindow()
        }
    }

    private func toolTile(_ name: String, subtitle: String, symbol: String, avatar: CompanionAvatar? = nil, action: @escaping () -> Void) -> some View {
        CompanionInteraction(action: action) {
            VStack(spacing: 12) {
                Group {
                    if let avatar { CompanionCharacter(size: 34, avatar: avatar, animates: false) }
                    else { Image(systemName: symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(CompanionStyle.accentInk) }
                }.frame(height: 34)
                Text(LocalizedStringKey(name)).font(.callout.weight(.semibold)).lineLimit(1)
                Text(LocalizedStringKey(subtitle)).font(.system(size: 9)).foregroundStyle(CompanionStyle.muted).lineLimit(1)
            }.frame(maxWidth: .infinity).padding(.vertical, 15).modifier(IslandControlSurface())
        }.accessibilityLabel("\(name). \(subtitle)")
    }

    private func reactToTouch() {
        reactions.touch()
    }

    private var homeHeadline: String {
        let en = activation.voiceLanguage.hasPrefix("en")
        if activation.isPreparing { return en ? "Getting ready…" : "Preparando…" }
        if activation.isListening { return en ? "I’m listening." : "Estou escutando." }
        if activation.isFinalizing { return en ? "Finishing your command…" : "Finalizando seu pedido…" }
        if notch.spatialAssistant.overlay.voiceSynthesizer.isPreparingAudio { return en ? "Preparing voice…" : "Preparando a voz…" }
        if notch.spatialAssistant.overlay.voiceSynthesizer.isSpeaking { return en ? "Speaking…" : "Falando…" }
        if activation.isExecutingVoiceCommand || activation.isPresentingVoiceProcessing { return en ? "On it." : "Cuidando disso." }
        if activation.isConversing { return activation.conversation.isPreparing ? (en ? "Getting ready…" : "Preparando…") : (en ? "I’m listening." : "Estou escutando.") }
        if let response = notch.spatialAssistant.response { return response.succeeded ? (en ? "Here you go." : "Aqui está.") : (en ? "Let’s try again." : "Vamos tentar de novo.") }
        if activation.voicePresented && !activation.commandAcknowledged { return en ? "Let’s try that again." : "Vamos tentar de novo." }
        if activation.commandAcknowledged { return en ? "Got it." : "Pronto." }
        switch reactions.mood {
        case .happy: return en ? "Hey, that tickles!" : "Ei, faz cócegas!"
        case .annoyed: return en ? "Okay, okay — I’m here!" : "Tá bom, tô aqui!"
        case .asleep: return en ? "Tiny nap. Be right back." : "Um cochilo rápido. Já volto."
        case .waking: return en ? "I’m awake! What’s next?" : "Acordei! Qual é a próxima?"
        case .startled: return en ? "Oh! You surprised me." : "Opa! Você me surpreendeu."
        case .understood: return en ? "Got it." : "Entendido."
        case .celebrating: return en ? "One thing done!" : "Mais uma tarefa pronta!"
        case .idle:
            if assistant.pomodoroPhase == .paused { return en ? "Paused. Take your time." : "Pausado. Sem pressa." }
            return assistant.hasActiveSession ? (assistant.interval == .focus ? (en ? "One thing at a time." : "Uma coisa de cada vez.") : (en ? "A little room to breathe." : "Um espaço para respirar.")) : (en ? "Ready when you are." : "Pronto quando você estiver.")
        }
    }

    private var homeMessageText: Text {
        // Translate fixed app statuses while keeping transcripts and replies as data.
        if activation.voicePresented && activation.transcript.isEmpty {
            return Text(LocalizedStringKey(homeMessage))
        }
        return Text(homeMessage)
    }

    private var homeMessage: String {
        let en = activation.voiceLanguage.hasPrefix("en")
        if activation.isConversing {
            if !activation.conversation.transcript.isEmpty { return "“\(activation.conversation.transcript)”" }
            return activation.voiceLanguage.hasPrefix("en") ? "Microphone on. Speak to interrupt; Stop ends the conversation." : "Microfone ligado. Fale para interromper; Encerrar desliga a conversa."
        }
        if notch.spatialAssistant.overlay.voiceSynthesizer.isPreparingAudio { return activation.voiceLanguage.hasPrefix("en") ? "Preparing your spoken reply…" : "Preparando sua resposta em voz…" }
        if notch.spatialAssistant.overlay.voiceSynthesizer.isSpeaking { return activation.voiceLanguage.hasPrefix("en") ? "Start another request to interrupt me." : "Comece outro pedido para interromper minha fala." }
        if activation.voicePresented { return activation.transcript.isEmpty ? activation.voiceStatus : "“\(activation.transcript)”" }
        if let response = notch.spatialAssistant.response { return String(response.text.prefix(150)) }
        if activation.commandAcknowledged { return activation.voiceStatus }
        switch reactions.mood {
        case .happy: return en ? "Nice to see you. Easy on the pokes." : "Bom te ver. Pega leve nas cócegas."
        case .annoyed: return en ? "Give me a second to catch my breath." : "Só um segundo para recuperar o fôlego."
        case .asleep: return en ? "Tap once to wake me up." : "Um toque e eu acordo."
        case .waking: return en ? "That was a very short nap." : "Esse cochilo foi rápido demais."
        default:
            if assistant.pomodoroPhase == .paused { return en ? "Resume whenever you’re ready." : "Continue quando você quiser." }
            if assistant.hasActiveSession {
                return en ? "\(assistant.pomodoroTimeLabel) left. \(assistant.interval == .focus ? "I’ll let you know when it’s time to rest." : "Enjoy your break — I’ll keep the time.")" : "Faltam \(assistant.pomodoroTimeLabel). \(assistant.interval == .focus ? "Eu aviso quando chegar a hora de descansar." : "Aproveite a pausa. Eu cuido do relógio.")"
            }
            return en ? "Open Timers when you want to focus. I’ll keep you company." : "Abra os Timers quando quiser focar. Eu fico por perto."
        }
    }

    private var reactionDescription: String {
        switch reactions.mood {
        case .idle: "Ready to say hello"
        case .happy: "Happy"
        case .annoyed: "A little grumpy"
        case .asleep: "Sleeping. Tap to wake"
        case .waking: "Waking up"
        case .startled: "Surprised"
        case .understood: "Command understood"
        case .celebrating: "Celebrating a completed session"
        }
    }

    private var setup: some View {
        TimerToolsView(onStart: { notch.showIsland() })
    }

    private var island: some View {
        Group {
            if activation.voicePresented {
                Button { notch.clickIsland() } label: {
                    HStack(spacing: 0) {
                        CompanionCharacter(size: 24, avatar: preferences.avatar, animates: animates, listening: activation.isListening, voicePhase: companionPhase(),
                                           mood: activation.commandAcknowledged ? .understood : .idle).frame(maxWidth: .infinity)
                        Color.clear.frame(width: notch.geometry.cutoutWidth + (notch.geometry.cutoutWidth > 0 ? 8 : 24))
                        VStack(spacing: 1) {
                            Image(systemName: activation.isListening ? "waveform" : activation.commandAcknowledged ? "checkmark" : "mic")
                            Text(LocalizedStringKey(activation.isListening ? "Listening" : activation.isPreparing ? "Preparing" : activation.isFinalizing ? "Finishing" : "Voice"))
                                .font(.system(size: 8))
                        }.font(.system(size: 11)).foregroundStyle(CompanionStyle.accentInk).frame(maxWidth: .infinity)
                    }.padding(.horizontal, 8).frame(height: notch.geometry.bodyHeight).contentShape(Rectangle())
                }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("Voice: \(activation.voiceStatus). Open companion.")
            } else if let work = aiActivity.analytics.work.first {
                Button { notch.clickIsland() } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 0) {
                            HStack(spacing: 3) {
                                CompanionCharacter(size: 21, avatar: .ada, animates: animates, focusing: true, mood: notch.isPointerHovering ? .happy : .idle)
                                ProviderMark(provider: work.provider, size: 20)
                            }.frame(maxWidth: .infinity)
                            Color.clear.frame(width: notch.geometry.cutoutWidth + (notch.geometry.cutoutWidth > 0 ? 8 : 24))
                            VStack(spacing: 1) {
                                Text(assistant.hasTimerActivity ? assistant.compactTimeLabel : work.elapsed(at: context.date)).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                                Text(assistant.hasTimerActivity ? work.provider.title : "Working").font(.system(size: 8)).foregroundStyle(CompanionStyle.accentInk)
                            }.frame(maxWidth: .infinity)
                        }.padding(.horizontal, 8).frame(height: notch.geometry.bodyHeight).contentShape(Rectangle())
                    }
                }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("\(work.provider.title) working on \(work.project). Open AI activity.")
            } else if assistant.hasTimerActivity { timerIsland }
            else {
                Button { notch.clickIsland() } label: {
                    HStack(spacing: 0) {
                        CompanionCharacter(size: 24, avatar: preferences.avatar, animates: animates, mood: notch.isPointerHovering ? .happy : .idle).frame(maxWidth: .infinity)
                        Color.clear.frame(width: notch.geometry.cutoutWidth + (notch.geometry.cutoutWidth > 0 ? 8 : 24))
                        Text("Open").font(.system(size: 11, weight: .medium)).foregroundStyle(CompanionStyle.accentInk).frame(maxWidth: .infinity)
                    }.padding(.horizontal, 8).frame(height: notch.geometry.bodyHeight).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open Sieghart")
            }
        }
    }

    @ViewBuilder private var timerIsland: some View {
        if assistant.activeTimerMode != .pomodoro { utilityIsland } else { pomodoroIsland }
    }

    private var utilityIsland: some View {
        Button { notch.clickIsland() } label: {
            HStack(spacing: 0) {
                CompanionCharacter(size: 24, avatar: preferences.avatar, animates: animates, mood: notch.isPointerHovering ? .happy : .idle).frame(maxWidth: .infinity)
                Color.clear.frame(width: notch.geometry.cutoutWidth + (notch.geometry.cutoutWidth > 0 ? 8 : 24))
                VStack(spacing: 1) {
                    Text(assistant.utilityClock.timeLabel).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(assistant.utilityClock.isRunning ? assistant.utilityClock.mode.title : "Paused").font(.system(size: 8)).foregroundStyle(CompanionStyle.accentInk)
                }.frame(maxWidth: .infinity)
            }.padding(.horizontal, 8).frame(height: notch.geometry.bodyHeight).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Open \(assistant.utilityClock.mode.title) controls")
    }

    private var pomodoroIsland: some View {
        Button { notch.clickIsland() } label: {
                let finishing = assistant.isRunning && assistant.remainingSeconds <= 30
                HStack(spacing: 0) {
                    Group {
                        if finishing {
                            VStack(spacing: 3) {
                                Text("Almost!").font(.system(size: 10, weight: .medium, design: .rounded))
                                islandProgress
                            }.foregroundStyle(CompanionStyle.accentInk)
                        } else {
                            CompanionCharacter(size: 26, avatar: preferences.avatar, animates: animates, focusing: assistant.isRunning && assistant.interval == .focus, mood: notch.isPointerHovering ? .happy : .idle)
                        }
                    }.frame(maxWidth: .infinity)
                    Color.clear.frame(width: notch.geometry.cutoutWidth + (notch.geometry.cutoutWidth > 0 ? 8 : 40))
                    HStack(spacing: 2) {
                        if finishing {
                            // On the timer side, the companion nudges the digits.
                            // Both poses remain outside the physical camera gap.
                            CompanionCharacter(size: 20, avatar: preferences.avatar, animates: animates, gaze: CGSize(width: 3, height: 0), mood: .startled, strolling: animates)
                        }
                        VStack(spacing: 3) {
                            Text(assistant.pomodoroTimeLabel)
                                .font(.system(size: finishing ? 10 : 12, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(finishing ? CompanionStyle.accent : CompanionStyle.ink)
                                .contentTransition(.numericText(countsDown: true))
                                .animation(animates ? .easeOut(duration: 0.2) : nil, value: assistant.pomodoroTimeLabel)
                            if !finishing { islandProgress }
                        }
                    }.frame(maxWidth: .infinity)
                }.padding(.horizontal, 8).frame(height: notch.geometry.bodyHeight).contentShape(Rectangle())
                    .animation(animates ? .easeInOut(duration: 0.35) : nil, value: finishing)
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .accessibilityLabel("\(assistant.activityTitle), \(assistant.pomodoroTimeLabel) remaining. Open timer controls.")
        .help("Open timer controls")
    }

    private var islandProgress: some View {
        Capsule().fill(assistant.isRunning ? CompanionStyle.accent : .orange)
            .frame(width: max(3, 48 * assistant.pomodoroProgress), height: 2)
    }

    private var celebration: some View {
        HStack(spacing: 22) {
            CompanionCharacter(size: 92, avatar: preferences.avatar, animates: animates, mood: .celebrating)
            VStack(alignment: .leading, spacing: 12) {
                Text(notch.latestCompletion?.interval == .focus ? "Focus complete!" : "Break complete!").font(.title3.weight(.semibold))
                Text(completionMessage).font(.callout).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                if assistant.hasActiveSession {
                    Text(assistant.pomodoroTimeLabel).font(.title2.weight(.medium)).monospacedDigit()
                    Button("Back to your break") { notch.hide() }.buttonStyle(CompanionButtonStyle(primary: true)).focusEffectDisabled()
                } else {
                    Button(notch.latestCompletion?.interval == .focus ? "Start break" : "Choose next focus") {
                        if notch.latestCompletion?.interval == .focus { assistant.startBreak(); notch.showIsland() }
                        else { notch.showFocusSetup() }
                    }.buttonStyle(CompanionButtonStyle(primary: true)).focusEffectDisabled()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            iconButton("xmark", label: "Dismiss completion") { notch.hide() }
        }
    }

    private var completionMessage: String {
        if let minutes = notch.latestCompletion?.automaticBreakMinutes { return "You did it. Your \(minutes)-minute break has started." }
        return notch.latestCompletion?.interval == .focus ? "One thing done. Take a breath — you earned a break." : "Rested and ready. Start your next session whenever you like."
    }

    private var timer: some View {
        TimerToolsView(onStart: { notch.showIsland() })
    }

    private var completion: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                face
                title(assistant.activityTitle, caption: assistant.interval == .focus ? "\(assistant.completedSessions) sessions done. Time for a break." : "Come back ready.")
                Spacer()
                iconButton("xmark", label: "Hide widget") { notch.hide() }
            }
            HStack(spacing: 8) {
                Button("Back to focus") { notch.showFocusSetup() }.buttonStyle(CompanionButtonStyle())
                Button {
                    if assistant.interval == .focus { assistant.startBreak() }
                    else { assistant.startFocusSession() }
                    notch.showCurrentTask()
                } label: {
                    Text(assistant.interval == .focus ? "Start \(assistant.nextBreakMinutes) min break" : "Start focus").frame(maxWidth: .infinity)
                }.buttonStyle(CompanionButtonStyle(primary: true))
            }
        }
    }

    private func title(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline).lineLimit(1)
            Text(caption).font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(2)
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32).background(.white.opacity(0.08), in: Circle())
        }.buttonStyle(IslandButtonStyle()).focusEffectDisabled().accessibilityLabel(label).help(label)
    }


}
