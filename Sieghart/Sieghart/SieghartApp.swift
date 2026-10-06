import SwiftUI

@main
struct SieghartApp: App {
    @StateObject private var sensor: SensorViewModel
    @StateObject private var assistant: AssistantViewModel
    @StateObject private var notch: NotchWidgetController
    @StateObject private var gestures: ImpactGestureCoordinator
    @StateObject private var activation: ActivationController
    @StateObject private var preferences: CompanionPreferences
    @StateObject private var codexUsage: CodexUsageModel
    @StateObject private var aiUsage: AIUsageModel

    init() {
        let preferences = CompanionPreferences()
        let codexUsage = CodexUsageModel()
        let aiUsage = AIUsageModel()
        let assistant = AssistantViewModel()
        let sensor = SensorViewModel()
        let notch = NotchWidgetController(assistant: assistant, preferences: preferences)
        let gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        let activation = ActivationController(assistant: assistant, notch: notch)
        notch.activation = activation
        notch.codexUsage = codexUsage
        notch.aiUsage = aiUsage
        aiUsage.startMonitoring(codex: codexUsage)
        notch.observeAIActivity()
        notch.restoreSessionPresence()
        sensor.onImpact = { impact in
            guard preferences.impactsEnabled else { return }
            assistant.registerImpact(impact)
            gestures.receive(impact)
        }
        if preferences.impactsEnabled { sensor.startIfNeeded() }
        _sensor = StateObject(wrappedValue: sensor)
        _assistant = StateObject(wrappedValue: assistant)
        _notch = StateObject(wrappedValue: notch)
        _gestures = StateObject(wrappedValue: gestures)
        _activation = StateObject(wrappedValue: activation)
        _preferences = StateObject(wrappedValue: preferences)
        _codexUsage = StateObject(wrappedValue: codexUsage)
        _aiUsage = StateObject(wrappedValue: aiUsage)
    }

    var body: some Scene {
        WindowGroup("Sieghart", id: "main") {
            ContentView()
                .environmentObject(sensor)
                .environmentObject(assistant)
                .environmentObject(notch)
                .environmentObject(gestures)
                .environmentObject(activation)
                .environmentObject(preferences)
                .environmentObject(codexUsage)
                .environmentObject(aiUsage)
        }
        .defaultSize(width: 1000, height: 680)
        .windowToolbarStyle(.unifiedCompact)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(assistant)
                .environmentObject(notch)
                .environmentObject(activation)
                .environmentObject(preferences)
                .environmentObject(codexUsage)
                .environmentObject(aiUsage)
        } label: {
            if let image = CompanionSprites.menuBarImage(for: preferences.avatar) {
                Image(nsImage: image).accessibilityLabel("Sieghart — \(preferences.avatar.name)")
            } else {
                Image(systemName: "face.smiling").accessibilityLabel("Sieghart")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", focus = "Timers", activation = "Activation", appearance = "Appearance", aiLimits = "AI limits"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .focus: "timer"
        case .activation: "keyboard"
        case .appearance: "slider.horizontal.3"
        case .aiLimits: "chart.bar.xaxis"
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var sensor: SensorViewModel
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var notch: NotchWidgetController
    @EnvironmentObject private var gestures: ImpactGestureCoordinator
    @EnvironmentObject private var activation: ActivationController
    @EnvironmentObject private var preferences: CompanionPreferences
    @State private var section: AppSection = .overview

    var body: some View {
        Group {
            if preferences.onboardingComplete { workspace }
            else { CompanionOnboardingView() }
        }
        .frame(minWidth: 840, minHeight: 660)
        .preferredColorScheme(.dark)
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .overview: overview
                    case .focus: focusSettings
                    case .activation: activationSettings
                    case .appearance: appearanceSettings
                    case .aiLimits:
                        heading("Your AI limits", subtitle: "Know what’s left, when it resets, and what you spend.")
                        AIUsageView()
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 840, minHeight: 580)
        .background(CompanionStyle.background)
        .tint(CompanionStyle.accent)
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
        .toolbar {
            Button { section = .activation } label: { Image(systemName: "gearshape") }
                .help("Activation preferences")
        }
        .onChange(of: preferences.impactsEnabled) { _, enabled in
            if enabled { sensor.startIfNeeded() }
            else { sensor.stop(); gestures.cancelPendingImpacts() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CompanionFace(avatar: preferences.avatar).scaleEffect(0.72).frame(width: 30, height: 30)
                Text("Sieghart").font(.title3.weight(.semibold))
            }
            .padding(.bottom, 20)
            sidebarButton("Overview", symbol: "square.grid.2x2", selected: section == .overview) { section = .overview }
            sidebarButton("Timers", symbol: "timer", selected: section == .focus) { section = .focus }
            sidebarButton("Activation", symbol: "keyboard", selected: section == .activation) { section = .activation }
            sidebarButton("Appearance", symbol: "slider.horizontal.3", selected: section == .appearance) { section = .appearance }
            sidebarButton("AI limits", symbol: "chart.bar.xaxis", selected: section == .aiLimits) { section = .aiLimits }
            Spacer()
            Button("Review introduction") { preferences.onboardingComplete = false }.buttonStyle(.plain).font(.caption).foregroundStyle(CompanionStyle.muted)
            Text("Your Mac companion").font(.caption).foregroundStyle(CompanionStyle.muted)
        }
        .padding(20)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(CompanionStyle.surface)
    }

    private func sidebarButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        CompanionInteraction(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .foregroundStyle(selected ? Color.white : CompanionStyle.muted)
                .background(selected ? CompanionStyle.separator : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "")
    }

    @ViewBuilder private var overview: some View {
        heading("A calmer way to focus.", subtitle: "Your next session is one shortcut away.")
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(assistant.hasActiveSession ? assistant.activityTitle.uppercased() : "FOCUS")
                Spacer()
                Text(assistant.sessionCaption)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(CompanionStyle.muted)
            HStack(spacing: 28) {
                Text(assistant.hasActiveSession ? assistant.pomodoroTimeLabel : String(format: "%02d:00", assistant.focusMinutes))
                    .font(.system(size: 64, weight: .medium)).monospacedDigit()
                    .minimumScaleFactor(0.7)
                VStack(alignment: .leading, spacing: 7) {
                    Text(assistant.hasActiveSession ? assistant.activityTitle : "Make room for one thing.")
                        .font(.title3.weight(.semibold))
                    Text("Choose your rhythm in Timers or use the notch for quick access.")
                        .font(.callout).foregroundStyle(CompanionStyle.muted)
                }
            }
            HStack(spacing: 8) {
                Button("Open timers") { section = .focus }.buttonStyle(CompanionButtonStyle(primary: true))
                if assistant.hasActiveSession {
                    Button(assistant.pomodoroButtonLabel) { assistant.togglePomodoro() }.buttonStyle(CompanionButtonStyle())
                } else {
                    Button("Show Sieghart") { notch.show() }.buttonStyle(CompanionButtonStyle())
                }
            }
        }
        .companionCard()
        HStack(alignment: .top, spacing: 16) {
            quickCard("Activation", value: activation.companionShortcut?.label ?? "Shortcut off", detail: "Choose how Sieghart appears.") { section = .activation }
            quickCard("Appearance", value: preferences.avatar.name, detail: "Choose your companion and tune its motion.") { section = .appearance }
        }
        AIUsageSummary(onOpen: { section = .aiLimits })
        HStack {
            Text("Completed")
            Spacer()
            Text("\(assistant.completedSessions) sessions")
        }
        .font(.callout).foregroundStyle(CompanionStyle.muted)
    }

    @ViewBuilder private var focusSettings: some View {
        heading("Make time your own.", subtitle: "Count down, focus in rounds, or keep track of elapsed time.")
        TimerToolsView(onStart: { notch.showIsland() }).companionCard()
        Text("Selecting a mode leaves your clock alone. Start, pause or reset when you choose.").font(.caption).foregroundStyle(CompanionStyle.muted)
    }

    @ViewBuilder private var activationSettings: some View {
        heading("Bring Sieghart into view.", subtitle: "Choose the inputs that fit your day.")
        VStack(spacing: 18) {
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
            Divider()
            PreferenceRow("Island hover feedback", detail: "Highlight the compact island on hover. Click to open it.") {
                Toggle("Island hover feedback", isOn: $preferences.hoverEnabled).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            PreferenceRow("Voice", detail: "Use your shortcut and speak naturally. Focus commands run when you finish.") {
                Button(activation.isListening || activation.isPreparing ? "Cancel" : "Speak") {
                    if activation.isListening || activation.isPreparing { activation.cancelVoiceCommand() }
                    else { activation.toggleListening() }
                }.buttonStyle(CompanionButtonStyle()).focusEffectDisabled()
            }
            PreferenceRow("Speech language", detail: "Choose the language you use for commands.") {
                Picker("Speech language", selection: $activation.voiceLanguage) {
                    Text("English").tag("en_US")
                    Text("Português").tag("pt_BR")
                }.labelsHidden().frame(width: 140)
            }
            Text(activation.voiceStatus).font(.caption).foregroundStyle(CompanionStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
            if !activation.transcript.isEmpty {
                Text("“\(activation.transcript)”").frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            PreferenceRow("Impact gestures", detail: "An optional physical way to open or control focus.") {
                Toggle("Impact gestures", isOn: $preferences.impactsEnabled).labelsHidden().toggleStyle(.switch)
            }
            if preferences.impactsEnabled {
                ImpactActionPicker(title: "One impact", selection: $gestures.singleImpactAction)
                ImpactActionPicker(title: "Two impacts", selection: $gestures.doubleImpactAction)
                ImpactActionPicker(title: "Three impacts", selection: $gestures.tripleImpactAction)
                Text(sensor.isRunning ? "Impact gestures are active" : "Impact gestures are unavailable on this Mac")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            }
        }
        .companionCard()
        Text("You can always open Sieghart from the menu bar.").font(.caption).foregroundStyle(CompanionStyle.muted)
    }

    @ViewBuilder private var appearanceSettings: some View {
        heading("A little more you.", subtitle: "Six personalities. Choose the companion that feels at home on your Mac.")
        HStack(spacing: 18) {
            CompanionCharacter(size: 80, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion)
            VStack(alignment: .leading, spacing: 4) {
                Text(preferences.avatar.name).font(.headline)
                Text(preferences.avatar.detail).font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            Spacer()
            Button("Preview") { notch.show() }.buttonStyle(CompanionButtonStyle())
        }
        .padding(24).background(.black, in: RoundedRectangle(cornerRadius: 17))
        CompanionAvatarPicker(selection: $preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion)
        Text("Your choice is saved automatically and follows you into the island, voice, and celebrations.")
            .font(.caption).foregroundStyle(CompanionStyle.muted)
        VStack(spacing: 20) {
            PreferenceRow("Widget size", detail: "Scale the expanded panels. The compact island keeps the camera's physical height.") {
                Picker("Widget size", selection: $preferences.widgetSize) {
                    ForEach(WidgetSize.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 240)
            }
            Divider()
            PreferenceRow("Compact active timer", detail: "Keep remaining time and controls close together.") {
                Toggle("Compact active timer", isOn: $preferences.compactTimer).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            PreferenceRow("Character motion", detail: "Use restrained expressions during focus and voice.") {
                Toggle("Character motion", isOn: $preferences.characterMotion).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            PreferenceRow("Reduce Motion", detail: "Limit animation. macOS Reduce Motion is always respected.") {
                Toggle("Reduce Motion", isOn: $preferences.reduceMotion).labelsHidden().toggleStyle(.switch)
            }
        }.companionCard()
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle).foregroundStyle(CompanionStyle.muted)
        }.padding(.bottom, 5)
    }

    private func quickCard(_ title: String, value: String, detail: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
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
