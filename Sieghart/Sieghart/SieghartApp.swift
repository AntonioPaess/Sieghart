import SwiftUI

@main
struct SieghartApp: App {
    @StateObject private var sensor: SensorViewModel
    @StateObject private var assistant: AssistantViewModel
    @StateObject private var notch: NotchWidgetController
    @StateObject private var gestures: ImpactGestureCoordinator
    @StateObject private var activation: ActivationController
    @StateObject private var preferences: CompanionPreferences

    init() {
        let preferences = CompanionPreferences()
        let assistant = AssistantViewModel()
        let sensor = SensorViewModel()
        let notch = NotchWidgetController(assistant: assistant, preferences: preferences)
        let gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        let activation = ActivationController(assistant: assistant, notch: notch)
        notch.activation = activation
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
        }
        .defaultSize(width: 1000, height: 680)
        .windowToolbarStyle(.unifiedCompact)

        MenuBarExtra("Sieghart", systemImage: "sparkles") {
            MenuBarView()
                .environmentObject(assistant)
                .environmentObject(notch)
                .environmentObject(activation)
        }
        .menuBarExtraStyle(.window)
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", activation = "Activation", appearance = "Appearance"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .activation: "keyboard"
        case .appearance: "slider.horizontal.3"
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
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .overview: overview
                    case .activation: activationSettings
                    case .appearance: appearanceSettings
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
                CompanionFace().scaleEffect(0.72).frame(width: 30, height: 30)
                Text("Sieghart").font(.title3.weight(.semibold))
            }
            .padding(.bottom, 20)
            sidebarButton("Overview", symbol: "square.grid.2x2", selected: section == .overview) { section = .overview }
            sidebarButton("Focus", symbol: "timer", selected: false) { notch.showFocusSetup() }
            sidebarButton("Activation", symbol: "keyboard", selected: section == .activation) { section = .activation }
            sidebarButton("Appearance", symbol: "slider.horizontal.3", selected: section == .appearance) { section = .appearance }
            Spacer()
            Text("Your Mac companion").font(.caption).foregroundStyle(CompanionStyle.muted)
        }
        .padding(20)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(CompanionStyle.surface)
    }

    private func sidebarButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .foregroundStyle(selected ? Color.white : CompanionStyle.muted)
                .background(selected ? CompanionStyle.separator : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
                    Text("Choose duration and break settings directly in the widget.")
                        .font(.callout).foregroundStyle(CompanionStyle.muted)
                }
            }
            HStack(spacing: 8) {
                Button("Open focus widget") { notch.showFocusSetup() }.buttonStyle(CompanionButtonStyle(primary: true))
                if assistant.hasActiveSession {
                    Button(assistant.pomodoroButtonLabel) { assistant.togglePomodoro() }.buttonStyle(CompanionButtonStyle())
                } else {
                    Button("Show Sieghart") { notch.show() }.buttonStyle(CompanionButtonStyle())
                }
            }
        }
        .companionCard()
        HStack(alignment: .top, spacing: 16) {
            quickCard("Activation", value: activation.selectedKey == "Off" ? "Shortcut off" : "Control + Option + \(activation.selectedKey)", detail: "Choose how Sieghart appears.") { section = .activation }
            quickCard("Appearance", value: preferences.compactTimer ? "Compact while you focus" : "More room while you focus", detail: "Tune reveal and character motion.") { section = .appearance }
        }
        HStack {
            Text("Completed")
            Spacer()
            Text("\(assistant.completedSessions) sessions")
        }
        .font(.callout).foregroundStyle(CompanionStyle.muted)
    }

    @ViewBuilder private var activationSettings: some View {
        heading("Bring Sieghart into view.", subtitle: "Choose the inputs that fit your day.")
        VStack(spacing: 18) {
            PreferenceRow("Keyboard shortcut", detail: "Works while another app is in front.") {
                HStack {
                    Text("Control + Option +").font(.caption)
                    Picker("Shortcut key", selection: $activation.selectedKey) {
                        ForEach(ActivationController.keys, id: \.label) { key in Text(key.label).tag(key.label) }
                    }.labelsHidden().frame(width: 80)
                }
            }
            Text(activation.shortcutStatus).font(.caption).foregroundStyle(CompanionStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            PreferenceRow("Hover at the notch", detail: "A quiet peek when your pointer reaches the notch.") {
                Toggle("Hover at the notch", isOn: $preferences.hoverEnabled).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            PreferenceRow("Voice", detail: "Press to speak. The microphone stays off while idle.") {
                Button(activation.isListening ? "Stop" : "Speak") { activation.toggleListening() }.buttonStyle(CompanionButtonStyle())
            }
            Text(activation.voiceStatus).font(.caption).foregroundStyle(CompanionStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
            if !activation.transcript.isEmpty {
                Text("“\(activation.transcript)”").frame(maxWidth: .infinity, alignment: .leading)
            }
            if activation.awaitingVoiceConfirmation {
                HStack {
                    Button("Cancel") { activation.cancelVoiceCommand() }.buttonStyle(CompanionButtonStyle())
                    Button("Run command") { activation.confirmVoiceCommand() }.buttonStyle(CompanionButtonStyle(primary: true))
                }
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
        heading("Quiet, until you need it.", subtitle: "A compact companion that belongs at the top of your screen.")
        HStack(spacing: 18) {
            CompanionFace()
            VStack(alignment: .leading, spacing: 4) {
                Text("Sieghart").font(.headline)
                Text("Small character. Clear task. One surface.").font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            Spacer()
            Button("Preview") { notch.show() }.buttonStyle(CompanionButtonStyle())
        }
        .padding(24).background(.black, in: RoundedRectangle(cornerRadius: 17))
        VStack(spacing: 20) {
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

private extension View {
    func companionCard() -> some View {
        padding(24).background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 17))
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

private struct MenuBarView: View {
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var notch: NotchWidgetController
    @EnvironmentObject private var activation: ActivationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sieghart", systemImage: "sparkles").font(.headline)
            Label("\(assistant.activityTitle) · \(assistant.pomodoroTimeLabel)", systemImage: "timer")
            Divider()
            Button("Choose focus session") { notch.showFocusSetup() }
            if assistant.hasActiveSession { Button(assistant.pomodoroButtonLabel) { assistant.togglePomodoro() } }
            Button(notch.isVisible ? "Hide widget" : "Show widget") { notch.toggle() }
            Button(activation.isListening ? "Stop listening" : "Speak a command") { activation.toggleListening() }
            Button("Open Sieghart") { openWindow(id: "main"); notch.focusMainWindow() }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(16).frame(minWidth: 260)
        .tint(CompanionStyle.accent).preferredColorScheme(.dark)
    }
}
