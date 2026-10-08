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
        .environment(\.islandGlass, !compact)
        .environment(\.islandReduceMotion, preferences.usesReducedMotion)
        .onHover { notch.setPointerInsidePanel($0) }
        .focusEffectDisabled()
        .onExitCommand { notch.hide() }
        .onChange(of: notch.utilityReaction) { _, _ in reactions.utility(notch.utilitySucceeded) }
        .onChange(of: preferences.avatar) { _, _ in reactions.reset() }
        .onChange(of: notch.presentation) { _, presentation in if presentation != .home { reactions.reset(); notch.finishWelcome() } }
    }

    private var surface: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.geometry.contentTop).allowsHitTesting(false)
            VStack(spacing: 14) {
                if !compact { pageHeader.modifier(WelcomeContentPhase(started: notch.presentation == .home ? notch.welcomeStartedAt : nil, animates: animates)) }
                switch notch.presentation {
                case .home: home
                case .focusSetup: pageScroll { setup }
                case .timer: timer
                case .completion: completion
                case .island: island
                case .celebration: celebration
                case .tools: tools
                case .clipboard: ClipboardHistoryView(clipboard: notch.clipboard, showsTitle: false, listHeight: 180, dismiss: { notch.hide() })
                case .system: pageScroll { SystemMonitorView(monitor: notch.monitor) }
                case .keepAwake: pageScroll { KeepAwakeView(controller: notch.keepAwake) }
                case .displayPower: pageScroll { DisplayPowerView(controller: notch.displayPower) }
                case .audio: pageScroll { AudioControlsView().environmentObject(notch.audio) }
                case .avatars: CompanionAvatarPicker(selection: $preferences.avatar, animates: animates, compact: true)
                case .aiLimits:
                    pageScroll { AIUsageView(showsHeader: false) }
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
            if staticPreview {
                HStack(spacing: 5) { Image(systemName: "ellipsis"); Image(systemName: "chevron.down").font(.caption2.weight(.bold)) }
            } else { Menu {
                Button("Companion") { notch.show() }
                Button("Timers") { notch.showTimer() }
                Button("AI agents") { notch.showAILimits() }
                Button("System") { notch.showSystem() }
                Button("Keep awake") { notch.showKeepAwake() }
                Button("Display & power") { notch.showDisplayPower() }
                Button("Audio") { notch.showAudio() }
                Button("Clipboard") { notch.showClipboard() }
                Button("Change companion") { notch.showAvatars() }
                Button("Tools") { notch.showTools() }
                Divider()
                Button("Close") { notch.hide() }
            } label: {
                HStack(spacing: 5) { Image(systemName: "ellipsis"); Image(systemName: "chevron.down").font(.caption2.weight(.bold)) }
            }.menuStyle(.borderlessButton).fixedSize().focusEffectDisabled().accessibilityLabel("Island pages") }
        }.frame(height: 24)
    }

    private var pageTitle: String {
        switch notch.presentation {
        case .home: "Companion"
        case .focusSetup, .timer: "Timers"
        case .aiLimits: "AI agents"
        case .tools: "Your tools"
        case .system: "System"
        case .keepAwake: "Keep awake"
        case .displayPower: "Display & power"
        case .audio: "Audio"
        case .clipboard: "Clipboard"
        case .avatars: "Choose your companion"
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
                CompanionCharacter(size: 32, avatar: preferences.avatar, animates: animates, mood: notch.utilityMood)
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
    private var face: some View {
        CompanionInteraction(action: { notch.show() }) {
            CompanionCharacter(avatar: preferences.avatar, animates: animates, focusing: assistant.isRunning && assistant.interval == .focus, listening: activation.isListening, mood: activation.commandAcknowledged ? .understood : .idle)
        }.accessibilityLabel("Show companion")
    }

    private var home: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                CompanionInteraction(action: reactToTouch) {
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animates)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12)
                        let greeting = notch.welcomeStartedAt.map { context.date.timeIntervalSince($0) < 4.2 } ?? false
                        let walking = !greeting && animates && reactions.mood == .idle && !activation.voicePresented && phase < 4
                        CompanionCharacter(size: 96, avatar: preferences.avatar, animates: animates, listening: activation.isListening, voicePhase: activation.companionVoicePhase, gaze: avatarPointer, mood: activation.commandAcknowledged ? .understood : activation.isVoiceBusy ? .idle : reactions.mood, strolling: walking, entrance: notch.welcomeStartedAt.map { CompanionEntranceMotion.sample(elapsed: context.date.timeIntervalSince($0), reducedMotion: !animates) })
                            .offset(x: walking ? sin(phase / 4 * .pi * 2) * 14 : 0)
                    }.frame(width: 124, height: 96)
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
                .modifier(WelcomeContentPhase(started: notch.welcomeStartedAt, animates: animates))
                VStack(alignment: .leading, spacing: 6) {
                    Text(activation.voicePresented ? "YOUR COMPANION · VOICE" : assistant.hasActiveSession ? assistant.activityTitle.uppercased() : "YOUR COMPANION")
                        .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(CompanionStyle.muted)
                    Text(homeHeadline).font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    Text(homeMessage).font(.callout).foregroundStyle(CompanionStyle.muted).lineLimit(2)
                    HStack(spacing: 12) {
                        Button { if activation.voicePresented { activation.cancelVoiceCommand(keepCompanionVisible: true) } else { activation.toggleListening() } } label: {
                            Label(activation.isVoiceBusy ? "Cancel" : activation.voicePresented ? "Back" : "Speak", systemImage: activation.isListening ? "waveform" : "mic")
                        }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel(activation.voicePresented ? "Cancel voice and return to companion" : "Speak to your companion")
                        if activation.isListening { Text("Finish speaking to run your command.") }
                        else if activation.voicePresented { Text(activation.voiceStatus).lineLimit(1) }
                        else { Label(assistant.hasActiveSession ? assistant.pomodoroTimeLabel : "\(assistant.focusMinutes) min focus", systemImage: "timer").monospacedDigit() }
                    }.font(.caption.weight(.medium)).foregroundStyle(CompanionStyle.accentInk)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(WelcomeContentPhase(started: notch.welcomeStartedAt, animates: animates))
            }
            .overlay {
                if animates, let start = notch.welcomeStartedAt {
                    CompanionIslandGreeting(avatar: preferences.avatar, started: start, onTouch: { notch.finishWelcome(); reactToTouch() })
                }
            }
        }
    }

    private var tools: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), spacing: 14) {
            toolTile("Companion", subtitle: preferences.avatar.name, symbol: "face.smiling", avatar: preferences.avatar) { notch.show() }
            toolTile("Audio", subtitle: "Apps & devices", symbol: "speaker.wave.2") { notch.showAudio() }
            toolTile("AI agents", subtitle: "Limits & activity", symbol: "sparkles") { notch.showAILimits() }
            toolTile("Timers", subtitle: "Three ways to time", symbol: "timer") { notch.showTimer() }
            toolTile("Clipboard", subtitle: "Copies, kept nearby", symbol: "doc.on.clipboard") { notch.showClipboard() }
            toolTile("Avatars", subtitle: "Find your companion", symbol: "person.crop.square") { notch.showAvatars() }
            toolTile("System", subtitle: "Live readings", symbol: "cpu") { notch.showSystem() }
            toolTile("Keep awake", subtitle: "On your terms", symbol: "cup.and.saucer") { notch.showKeepAwake() }
            toolTile("Display & power", subtitle: "Screen and sleep", symbol: "sun.max") { notch.showDisplayPower() }
            toolTile("Preferences", subtitle: "Your workspace", symbol: "gearshape") { notch.focusMainWindow() }
        }
    }

    private func toolTile(_ name: String, subtitle: String, symbol: String, avatar: CompanionAvatar? = nil, action: @escaping () -> Void) -> some View {
        CompanionInteraction(action: action) {
            VStack(spacing: 12) {
                Group {
                    if let avatar { CompanionCharacter(size: 34, avatar: avatar, animates: false) }
                    else { Image(systemName: symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(CompanionStyle.accentInk) }
                }.frame(height: 34)
                Text(name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 9)).foregroundStyle(CompanionStyle.muted).lineLimit(1)
            }.frame(maxWidth: .infinity).padding(.vertical, 15).modifier(IslandControlSurface())
        }.accessibilityLabel("\(name). \(subtitle)")
    }

    private func reactToTouch() {
        reactions.touch()
    }

    private var homeHeadline: String {
        if activation.isPreparing { return "Getting ready…" }
        if activation.isListening { return "I’m listening." }
        if activation.isFinalizing { return "Finishing your command…" }
        if activation.isExecutingVoiceCommand { return "On it." }
        if activation.voicePresented && !activation.commandAcknowledged { return "Let’s try that again." }
        if activation.commandAcknowledged { return "Got it." }
        switch reactions.mood {
        case .happy: return "Hey, that tickles!"
        case .annoyed: return "Okay, okay — I’m here!"
        case .asleep: return "Tiny nap. Be right back."
        case .waking: return "I’m awake! What’s next?"
        case .startled: return "Oh! You surprised me."
        case .understood: return "Got it."
        case .celebrating: return "One thing done!"
        case .idle:
            if assistant.pomodoroPhase == .paused { return "Paused. Take your time." }
            return assistant.hasActiveSession ? (assistant.interval == .focus ? "One thing at a time." : "A little room to breathe.") : "Ready when you are."
        }
    }

    private var homeMessage: String {
        if activation.voicePresented { return activation.transcript.isEmpty ? activation.voiceStatus : "“\(activation.transcript)”" }
        if activation.commandAcknowledged { return activation.voiceStatus }
        switch reactions.mood {
        case .happy: return "Nice to see you. Easy on the pokes."
        case .annoyed: return "Give me a second to catch my breath."
        case .asleep: return "Tap once to wake me up."
        case .waking: return "That was a very short nap."
        default:
            if assistant.pomodoroPhase == .paused { return "Resume whenever you’re ready." }
            return assistant.hasActiveSession ? "\(assistant.pomodoroTimeLabel) left. \(assistant.interval == .focus ? "I’ll let you know when it’s time to rest." : "Enjoy your break — I’ll keep the time.")" : "Open Timers when you want to focus. I’ll keep you company."
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
                        CompanionCharacter(size: 24, avatar: preferences.avatar, animates: animates, listening: activation.isListening, voicePhase: activation.companionVoicePhase,
                                           mood: activation.commandAcknowledged ? .understood : .idle).frame(maxWidth: .infinity)
                        Color.clear.frame(width: notch.geometry.cutoutWidth + (notch.geometry.cutoutWidth > 0 ? 8 : 24))
                        VStack(spacing: 1) {
                            Image(systemName: activation.isListening ? "waveform" : activation.commandAcknowledged ? "checkmark" : "mic")
                            Text(activation.isListening ? "Listening" : activation.isPreparing ? "Preparing" : activation.isFinalizing ? "Finishing" : "Voice")
                                .font(.system(size: 8))
                        }.font(.system(size: 11)).foregroundStyle(CompanionStyle.accentInk).frame(maxWidth: .infinity)
                    }.padding(.horizontal, 8).frame(height: notch.geometry.bodyHeight).contentShape(Rectangle())
                }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("Voice: \(activation.voiceStatus). Open companion.")
            } else if let work = aiActivity.analytics.work.first {
                Button { notch.clickIsland() } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 0) {
                            HStack(spacing: 3) {
                                CompanionCharacter(size: 21, avatar: preferences.avatar, animates: animates, focusing: true, mood: notch.isPointerHovering ? .happy : .idle)
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
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
                let time = animates ? context.date.timeIntervalSinceReferenceDate : 0
                let phase = time.truncatingRemainder(dividingBy: 60)
                let finishing = assistant.isRunning && assistant.remainingSeconds <= 30
                let walking = animates && assistant.isRunning && !finishing && phase < 4
                let nudge = finishing && animates ? max(0, sin(time * 3)) : 0
                HStack(spacing: 0) {
                    Group {
                        if finishing {
                            VStack(spacing: 3) {
                                Text("Almost!").font(.system(size: 10, weight: .medium, design: .rounded))
                                islandProgress
                            }.foregroundStyle(CompanionStyle.accentInk)
                        } else {
                            CompanionCharacter(size: 26, avatar: preferences.avatar, animates: animates, focusing: assistant.isRunning && assistant.interval == .focus, mood: notch.isPointerHovering ? .happy : .idle, strolling: walking)
                                .offset(x: walking ? sin(phase / 4 * .pi * 2) * 12 : 0)
                        }
                    }.frame(maxWidth: .infinity)
                    Color.clear.frame(width: notch.geometry.cutoutWidth + (notch.geometry.cutoutWidth > 0 ? 8 : 40))
                    HStack(spacing: 2) {
                        if finishing {
                            // On the timer side, the companion nudges the digits.
                            // Both poses remain outside the physical camera gap.
                            CompanionCharacter(size: 20, avatar: preferences.avatar, animates: animates, gaze: CGSize(width: 3, height: 0), mood: .startled, strolling: animates)
                                .rotationEffect(.degrees(nudge * 8))
                                .offset(x: nudge * 2)
                        }
                        VStack(spacing: 3) {
                            Text(assistant.pomodoroTimeLabel)
                                .font(.system(size: finishing ? 10 : 12, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(finishing ? CompanionStyle.accent : CompanionStyle.ink)
                                .contentTransition(.numericText(countsDown: true))
                                .offset(x: nudge * 2, y: -nudge)
                                .animation(animates ? .easeOut(duration: 0.2) : nil, value: assistant.pomodoroTimeLabel)
                            if !finishing { islandProgress }
                        }
                    }.frame(maxWidth: .infinity)
                }.padding(.horizontal, 8).frame(height: notch.geometry.bodyHeight).contentShape(Rectangle())
                    .animation(animates ? .easeInOut(duration: 0.35) : nil, value: finishing)
            }
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
