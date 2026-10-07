import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", focus = "Timers", activation = "Activation", appearance = "Appearance", aiLimits = "AI agents", audio = "Audio"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .focus: "timer"
        case .activation: "keyboard"
        case .appearance: "slider.horizontal.3"
        case .aiLimits: "chart.bar.xaxis"
        case .audio: "speaker.wave.2"
        }
    }
}

struct ContentView: View {
    @Environment(\.islandPreview) private var preview
    @EnvironmentObject private var sensor: SensorViewModel
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var notch: NotchWidgetController
    @EnvironmentObject private var gestures: ImpactGestureCoordinator
    @EnvironmentObject private var activation: ActivationController
    @EnvironmentObject private var preferences: CompanionPreferences
    @State private var section: AppSection
    var scrollable: Bool

    init(initialSection: AppSection = .overview, scrollable: Bool = true) {
        _section = State(initialValue: initialSection)
        self.scrollable = scrollable
    }

    var body: some View {
        Group {
            if preferences.onboardingComplete { workspace }
            else { CompanionOnboardingView() }
        }
        .frame(minWidth: 840, minHeight: 660)
        .preferredColorScheme(.dark)
        .environment(\.workspaceGlass, true)
        .environment(\.islandReduceMotion, preferences.usesReducedMotion)
        .background { WorkspaceBackdrop() }
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            sidebar
            Group {
                if scrollable { ScrollView { page }.scrollIndicators(.hidden) }
                else { page }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 840, minHeight: 580)
        .tint(CompanionStyle.accent)
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
        .onChange(of: preferences.impactsEnabled) { _, enabled in
            if enabled { sensor.startIfNeeded() }
            else { sensor.stop(); gestures.cancelPendingImpacts() }
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label(section.rawValue, systemImage: section.symbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(CompanionStyle.muted)
                Spacer()
                Text("SIEGHART").font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(CompanionStyle.muted.opacity(0.65))
            }
            switch section {
            case .overview: overview
            case .focus: focusSettings
            case .activation: activationSettings
            case .appearance: appearanceSettings
            case .audio:
                heading("Sound, your way.", subtitle: "Your devices and audio apps in one quiet space.")
                AudioControlsView().companionCard()
            case .aiLimits:
                heading("Your AI, in view.", subtitle: "Limits, tokens and activity from the tools you use.")
                AIUsageView()
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                CompanionCharacter(size: 36, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sieghart").font(.headline)
                    Text("Your quiet companion").font(.system(size: 10)).foregroundStyle(CompanionStyle.muted)
                }
            }.padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 25)
            Text("YOUR SPACE").font(.system(size: 9, weight: .semibold)).tracking(1.6)
                .foregroundStyle(CompanionStyle.muted.opacity(0.7)).padding(.horizontal, 12).padding(.bottom, 4)
            ForEach(AppSection.allCases) { item in
                sidebarButton(item.rawValue, symbol: item.symbol, selected: section == item) { section = item }
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 12) {
                Label("Ready when you are", systemImage: "sparkle").font(.caption.weight(.medium))
                Text("A little space for your time, your tools and your companion.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
                Button("Review introduction") { preferences.onboardingComplete = false }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(CompanionStyle.accent)
            }.padding(15).modifier(WorkspaceSurface(radius: 17))
        }
        .padding(14)
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.025))
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.07)).frame(width: 0.7).allowsHitTesting(false) }
    }

    private func sidebarButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        CompanionInteraction(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 15)).frame(width: 18)
                    .foregroundStyle(selected ? CompanionStyle.accent : CompanionStyle.muted)
                Text(title)
                Spacer()
                if selected { Circle().fill(CompanionStyle.accent).frame(width: 4, height: 4) }
            }
                .font(.callout.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .foregroundStyle(selected ? Color.white : CompanionStyle.muted)
                .background(selected ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "")
    }

    @ViewBuilder private var overview: some View {
        heading("A little room for your day.", subtitle: "Your companion, your time, and your AI work — together.")
        HStack(spacing: 22) {
            CompanionCharacter(size: 100, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion, focusing: assistant.hasTimerActivity)
                .frame(width: 120, height: 130)
            VStack(alignment: .leading, spacing: 14) {
                Label(assistant.hasTimerActivity ? assistant.activeTimerMode.title.uppercased() : "READY WHEN YOU ARE", systemImage: assistant.hasTimerActivity ? assistant.activeTimerMode.symbol : "sparkle")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(CompanionStyle.accent)
                if assistant.hasTimerActivity {
                    Text(assistant.compactTimeLabel).font(.system(size: 52, weight: .medium, design: .rounded)).monospacedDigit()
                } else {
                    Text("Make room for one thing.").font(.title2.weight(.semibold))
                }
                Text(assistant.hasTimerActivity ? "Your clock is nearby. Open Timers to control it." : "Choose a timer, settle into focus, or just say hello.")
                    .font(.callout).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Open timers") { section = .focus }.buttonStyle(CompanionButtonStyle(primary: true))
                    Button("Show companion") { notch.show() }.buttonStyle(CompanionButtonStyle())
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.companionCard()
        HStack(alignment: .top, spacing: 16) {
            quickCard("Activation", symbol: "keyboard", value: activation.companionShortcut?.label ?? "Shortcut off", detail: "Your companion, one shortcut away.") { section = .activation }
            quickCard("Appearance", symbol: "face.smiling", value: preferences.avatar.name, detail: "Choose a personality and its rhythm.") { section = .appearance }
        }
        AIUsageSummary(onOpen: { section = .aiLimits })
        HStack {
            Label("A little progress adds up", systemImage: "leaf")
            Spacer()
            Text("\(assistant.completedSessions) focus sessions completed")
        }.font(.caption).foregroundStyle(CompanionStyle.muted)
    }

    @ViewBuilder private var focusSettings: some View {
        heading("Make time your own.", subtitle: "Count down, focus in rounds, or keep track of elapsed time.")
        TimerToolsView(onStart: { notch.showIsland() }).companionCard()
        Text("Selecting a mode leaves your clock alone. Start, pause or reset when you choose.").font(.caption).foregroundStyle(CompanionStyle.muted)
    }

    @ViewBuilder private var activationSettings: some View {
        heading("Bring Sieghart into view.", subtitle: "Choose the inputs that fit your day.")
        VStack(alignment: .leading, spacing: 18) {
            Label("Keyboard", systemImage: "keyboard").font(.headline)
            PreferenceRow("Companion shortcut", detail: "Record any key combination to reveal Sieghart.") { ShortcutRecorder(action: .companion) }
            Text(activation.shortcutStatus).font(.caption).foregroundStyle(CompanionStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            PreferenceRow("Voice shortcut", detail: "Record keys, or press and release only modifiers such as Option + Command.") { ShortcutRecorder(action: .voice) }
            Text(activation.voiceShortcutStatus).font(.caption).foregroundStyle(CompanionStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                if let date = activation.lastShortcutActivation {
                    Text("Last shortcut received at \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                Button("Restore shortcuts") { activation.recoverShortcuts() }.buttonStyle(.plain).focusEffectDisabled().font(.caption)
            }
            if activation.recordingShortcut != nil {
                Text("Press your combination. Release modifier-only keys to save. Escape cancels.").font(.caption).foregroundStyle(CompanionStyle.accent)
            }
            if activation.needsShortcutPermission {
                Button("Allow modifier shortcuts in other apps") { activation.enableModifierShortcuts() }.buttonStyle(CompanionButtonStyle()).focusEffectDisabled()
            }
        }.companionCard()
        VStack(alignment: .leading, spacing: 18) {
            Label("Island", systemImage: "rectangle.topthird.inset.filled").font(.headline)
            PreferenceRow("Island hover feedback", detail: "Your companion reacts on hover. Click to open the island.") {
                Toggle("Island hover feedback", isOn: $preferences.hoverEnabled).labelsHidden().toggleStyle(WorkspaceSwitchStyle())
            }
        }.companionCard()
        VStack(alignment: .leading, spacing: 18) {
            Label("Voice", systemImage: "waveform").font(.headline)
            PreferenceRow("Voice", detail: "Use your shortcut and speak naturally. Focus commands run when you finish.") {
                Button(activation.isListening || activation.isPreparing ? "Cancel" : "Speak") {
                    if activation.isListening || activation.isPreparing { activation.cancelVoiceCommand() }
                    else { activation.toggleListening() }
                }.buttonStyle(CompanionButtonStyle()).focusEffectDisabled()
            }
            PreferenceRow("Speech language", detail: "Choose the language you use for commands.") {
                if preview { Text(activation.voiceLanguage == "pt_BR" ? "Português" : "English").font(.callout).padding(9).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)) }
                else { Picker("Speech language", selection: $activation.voiceLanguage) {
                    Text("English").tag("en_US")
                    Text("Português").tag("pt_BR")
                }.labelsHidden().frame(width: 140) }
            }
            Text(activation.voiceStatus).font(.caption).foregroundStyle(CompanionStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
            if !activation.transcript.isEmpty {
                Text("“\(activation.transcript)”").frame(maxWidth: .infinity, alignment: .leading)
            }
        }.companionCard()
        VStack(alignment: .leading, spacing: 18) {
            Label("Impact gestures", systemImage: "hand.tap").font(.headline)
            PreferenceRow("Impact gestures", detail: "An optional physical way to open or control focus.") {
                Toggle("Impact gestures", isOn: $preferences.impactsEnabled).labelsHidden().toggleStyle(WorkspaceSwitchStyle())
            }
            if preferences.impactsEnabled {
                ImpactActionPicker(title: "One impact", selection: $gestures.singleImpactAction)
                ImpactActionPicker(title: "Two impacts", selection: $gestures.doubleImpactAction)
                ImpactActionPicker(title: "Three impacts", selection: $gestures.tripleImpactAction)
                Text(sensor.isRunning ? "Impact gestures are active" : "Impact gestures are unavailable on this Mac")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            }
        }.companionCard()
        Text("You can always open Sieghart from the menu bar.").font(.caption).foregroundStyle(CompanionStyle.muted)
    }

    @ViewBuilder private var appearanceSettings: some View {
        heading("A little more you.", subtitle: "Six personalities. Choose the companion that feels at home on your Mac.")
        HStack(spacing: 18) {
            CompanionCharacter(size: 86, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion)
            VStack(alignment: .leading, spacing: 4) {
                Text(preferences.avatar.name).font(.headline)
                Text(preferences.avatar.detail).font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            Spacer()
            Button("Preview") { notch.show() }.buttonStyle(CompanionButtonStyle())
        }
        .companionCard()
        CompanionAvatarPicker(selection: $preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion)
        Text("Your choice is saved automatically and follows you into the island, voice, and celebrations.")
            .font(.caption).foregroundStyle(CompanionStyle.muted)
        VStack(spacing: 20) {
            PreferenceRow("Widget size", detail: "Scale the expanded panels. The compact island keeps the camera's physical height.") {
                HStack(spacing: 3) {
                    ForEach(WidgetSize.allCases) { size in
                        Button { preferences.widgetSize = size } label: {
                            Text(size.rawValue).font(.caption.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                                .foregroundStyle(preferences.widgetSize == size ? .white : CompanionStyle.muted)
                                .background(preferences.widgetSize == size ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("\(size.rawValue) widget")
                            .accessibilityValue(preferences.widgetSize == size ? "Selected" : "")
                    }
                }.padding(3).frame(width: 224).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            }
            Divider()
            PreferenceRow("Compact active timer", detail: "Keep remaining time and controls close together.") {
                Toggle("Compact active timer", isOn: $preferences.compactTimer).labelsHidden().toggleStyle(WorkspaceSwitchStyle())
            }
            Divider()
            PreferenceRow("Character motion", detail: "Use restrained expressions during focus and voice.") {
                Toggle("Character motion", isOn: $preferences.characterMotion).labelsHidden().toggleStyle(WorkspaceSwitchStyle())
            }
            Divider()
            PreferenceRow("Reduce Motion", detail: "Limit animation. macOS Reduce Motion is always respected.") {
                Toggle("Reduce Motion", isOn: $preferences.reduceMotion).labelsHidden().toggleStyle(WorkspaceSwitchStyle())
            }
        }.companionCard()
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 29, weight: .semibold, design: .rounded))
            Text(subtitle).foregroundStyle(CompanionStyle.muted)
        }.padding(.bottom, 5)
    }

    private func quickCard(_ title: String, symbol: String, value: String, detail: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.callout.weight(.semibold))
            Text(value).font(.callout.weight(.medium)).foregroundStyle(CompanionStyle.accent)
            Text(detail).font(.caption).foregroundStyle(CompanionStyle.muted)
            Button("Customize", action: action).buttonStyle(CompanionButtonStyle())
        }.frame(maxWidth: .infinity, alignment: .leading).companionCard()
    }
}



private struct PreferenceRow<Control: View>: View {
    let title: String
    let detail: String
    let control: Control
    init(_ title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title; self.detail = detail; self.control = control()
    }
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            Spacer()
            control
        }
    }
}

private struct ImpactActionPicker: View {
    let title: String
    @Binding var selection: ImpactAction
    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(ImpactAction.allCases) { action in Text(action.title).tag(action) }
        }.pickerStyle(.menu)
    }
}
