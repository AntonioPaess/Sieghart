import AppKit
import Combine
import SwiftUI

struct NotchGeometry: Equatable {
    let width: CGFloat
    let cutoutWidth: CGFloat
    let cutoutHeight: CGFloat

    let bodyHeight: CGFloat
    static let cornerRadius: CGFloat = 24

    var contentTop: CGFloat { cutoutHeight + 6 }
    var height: CGFloat { contentTop + bodyHeight }
    var size: CGSize { CGSize(width: width, height: height) }

    static let fallback = NotchGeometry(width: 480, cutoutWidth: 180, cutoutHeight: 0)

    init(width: CGFloat, cutoutWidth: CGFloat, cutoutHeight: CGFloat, bodyHeight: CGFloat = 164) {
        self.bodyHeight = bodyHeight
        self.width = width
        self.cutoutWidth = cutoutWidth
        self.cutoutHeight = cutoutHeight
    }

    init(screen: NSScreen, setup: Bool = false, bodyHeight: CGFloat = 164) {
        self.bodyHeight = bodyHeight
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else {
            width = setup ? 520 : 480
            cutoutWidth = 180
            cutoutHeight = 0
            return
        }

        let measuredCutoutWidth = right.minX - left.maxX
        width = min(max(setup ? 520 : 480, measuredCutoutWidth + 188), screen.frame.width - 32)
        cutoutWidth = min(measuredCutoutWidth + 2, width - 32)
        cutoutHeight = max(screen.safeAreaInsets.top, min(left.height, right.height))
    }
}

enum NotchPresentation {
    case home, focusSetup, timer, completion, voice
}

@MainActor
final class NotchWidgetController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var geometry: NotchGeometry = .fallback

    @Published private(set) var presentation: NotchPresentation = .home

    private let preferences: CompanionPreferences
    private let assistant: AssistantViewModel
    var activation: ActivationController?
    private var panel: NSPanel?
    private var hoverPanel: HoverZonePanel?
    private var isPointerInsidePanel = false
    private var isImpactRevealed = false
    private var hideTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var pomodoroObservation: AnyCancellable?
    private var preferencesObservation: AnyCancellable?
    private var screenChangeObserver: AnyCancellable?
    private let overlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.mainMenu.rawValue + 3
    )

    init(assistant: AssistantViewModel, preferences: CompanionPreferences) {
        self.assistant = assistant
        self.preferences = preferences
        if let screen = Self.selectedScreen() { geometry = NotchGeometry(screen: screen) }
        configureHoverZone()
        screenChangeObserver = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screenDidChange() }
        preferencesObservation = preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.preferences.hoverEnabled { self.hoverPanel?.orderFrontRegardless() }
                else { self.hoverPanel?.orderOut(nil) }
                self.screenDidChange()
            }
        pomodoroObservation = assistant.$pomodoroPhase
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handlePomodoroPhaseChange(phase)
            }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // Every normal reveal returns to the companion. Timer tools are explicit.
    func show() {
        presentation = activation?.isListening == true || activation?.awaitingVoiceConfirmation == true ? .voice : .home
        reveal(stickyUntilImpact: presentation == .voice)
    }

    func showCurrentTask() {
        if assistant.hasActiveSession { presentation = .timer }
        else if assistant.pomodoroPhase == .completed { presentation = .completion }
        else { presentation = .home }
        reveal(stickyUntilImpact: presentation != .home)
    }

    func showFocusSetup() {
        presentation = .focusSetup
        reveal(stickyUntilImpact: true)
    }

    func showVoice() {
        presentation = .voice
        reveal(stickyUntilImpact: true)
    }

    func handleImpact() {
        if isVisible {
            hide()
        } else {
            show()
            isImpactRevealed = true
        }
    }

    func setPointerInsidePanel(_ isInside: Bool) {
        isPointerInsidePanel = isInside
        if isInside {
            hideTask?.cancel()
            hideTask = nil
        } else if isVisible && !isImpactRevealed {
            scheduleHide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        isVisible = false
        isImpactRevealed = false
        guard let panel, panel.isVisible else { return }
        collapseTask?.cancel()
        if preferences.usesReducedMotion {
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }
        collapseTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !self.isVisible else { return }
            panel?.orderOut(nil)
        }
    }

    private func handlePomodoroPhaseChange(_ phase: PomodoroPhase) {
        guard phase == assistant.pomodoroPhase else { return }
        if activation?.isListening == true || activation?.awaitingVoiceConfirmation == true { return }
        switch phase {
        case .focusing, .paused:
            presentation = .timer
            reveal(stickyUntilImpact: true)
        case .completed:
            presentation = .home
            reveal(stickyUntilImpact: false)
        case .idle:
            if presentation != .focusSetup { presentation = .home }
            screenDidChange()
        }
    }

    func focusMainWindow() {
        guard let mainWindow = NSApp.windows.first(where: { $0 !== panel && $0.title == "Sieghart" }) else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
    }

    private func reveal(stickyUntilImpact: Bool) {
        hideTask?.cancel()
        hideTask = nil
        collapseTask?.cancel()
        collapseTask = nil
        isImpactRevealed = stickyUntilImpact
        makePanelIfNeeded()
        screenDidChange()

        guard let panel else { return }
        guard let screen = notchScreen else { return }
        let size = geometry.size
        let expanded = NSRect(x: notchCenterX(on: screen) - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        let wasVisible = panel.isVisible
        isVisible = true
        // Resize the native panel immediately. Animating a window smaller than
        // its fixed SwiftUI content centers and crops that content mid-reveal.
        panel.setFrame(expanded, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: expanded.size)
        if !wasVisible { panel.alphaValue = preferences.usesReducedMotion ? 1 : 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = preferences.usesReducedMotion ? 0 : 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func makePanelIfNeeded() {
        guard panel == nil else { return }
        guard let activation else { return }

        let widgetPanel = NotchPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: geometry.width,
                height: geometry.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        widgetPanel.isOpaque = false
        widgetPanel.backgroundColor = .clear
        // The panel must visually merge with the physical notch. A shadow and a
        // translucent fill make the content underneath look like it is showing
        // through the widget.
        widgetPanel.hasShadow = false
        // The notch is composited with the menu bar. A level above the main
        // menu keeps the widget in the same visual plane as the notch instead
        // of leaving it underneath the menu bar surface.
        widgetPanel.level = overlayLevel
        widgetPanel.hidesOnDeactivate = false
        widgetPanel.isMovableByWindowBackground = false
        widgetPanel.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        let hosting = NSHostingView(
            rootView: NotchWidgetView()
                .environmentObject(self)
                .environmentObject(assistant)
                .environmentObject(activation)
                .environmentObject(preferences)
        )

        // The controller owns the panel geometry. SwiftUI must not keep the
        // initial home min/max bounds when switching to a larger tool view.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: geometry.size)
        widgetPanel.contentView = hosting
        widgetPanel.contentMinSize = .zero
        widgetPanel.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        panel = widgetPanel
    }

    private func positionPanel() {
        guard let panel else { return }
        guard let screen = notchScreen else { return }

        let size = geometry.size
        let centerX = notchCenterX(on: screen)
        let frame = NSRect(x: centerX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
    }

    private func configureHoverZone() {
        let hover = HoverZonePanel(
            contentRect: NSRect(x: 0, y: 0, width: geometry.cutoutWidth + 12, height: max(geometry.cutoutHeight, 30)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hover.isOpaque = false
        hover.backgroundColor = .clear
        hover.alphaValue = 0.01
        hover.hasShadow = false
        hover.level = overlayLevel
        hover.hidesOnDeactivate = false
        hover.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        let view = HoverZoneView()
        view.onEnter = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.preferences.hoverEnabled else { return }
                if !self.isVisible { self.show() }
            }
        }
        view.onExit = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isImpactRevealed, !self.isPointerInsidePanel else { return }
                self.scheduleHide()
            }
        }
        hover.contentView = view
        hoverPanel = hover
        positionHoverPanel()
        if preferences.hoverEnabled { hover.orderFrontRegardless() }
    }

    private func positionHoverPanel() {
        guard let hoverPanel else { return }
        guard let screen = notchScreen else { return }

        let size = CGSize(width: geometry.cutoutWidth + 12, height: max(geometry.cutoutHeight, 30))
        let centerX = notchCenterX(on: screen)
        hoverPanel.setFrame(
            NSRect(
                x: centerX - (size.width / 2),
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    private static func selectedScreen() -> NSScreen? {
        NSScreen.screens.first(where: { screen in
            screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private var notchScreen: NSScreen? { Self.selectedScreen() }

    private func screenDidChange() {
        let height: CGFloat
        switch presentation {
        case .home: height = 164
        case .focusSetup: height = 390
        case .timer: height = preferences.compactTimer ? 138 : 190
        case .completion: height = 148
        case .voice: height = 208
        }
        if let screen = notchScreen { geometry = NotchGeometry(screen: screen, setup: presentation == .focusSetup, bodyHeight: height) }
        positionHoverPanel()
        positionPanel()
    }

    private func notchCenterX(on screen: NSScreen) -> CGFloat {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              rightArea.minX > leftArea.maxX
        else {
            return screen.frame.midX
        }

        return leftArea.maxX + ((rightArea.minX - leftArea.maxX) / 2)
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            if !self.isPointerInsidePanel && !self.isImpactRevealed {
                self.hide()
            }
        }
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class HoverZonePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HoverZoneView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }
}

private struct NotchWidgetView: View {
    @EnvironmentObject private var notch: NotchWidgetController
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var activation: ActivationController
    @EnvironmentObject private var preferences: CompanionPreferences
    @State private var minutes = 25.0
    @State private var shortBreak = 5
    @State private var longBreak = 15
    @State private var rounds = 4
    @State private var autoBreak = true
    @State private var avatarReactionUntil = Date.distantPast
    @State private var avatarPointer = CGSize.zero

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.geometry.contentTop).allowsHitTesting(false)
            VStack(spacing: 0) {
                switch notch.presentation {
                case .home: home
                case .focusSetup:
                    ScrollView(.vertical) { setup }.scrollIndicators(.hidden)
                case .timer: timer
                case .completion: completion
                case .voice: voice
                }
            }
            .padding(20)
            .frame(width: notch.geometry.width, height: notch.geometry.bodyHeight, alignment: .top)
        }
        .frame(width: notch.geometry.width, height: notch.geometry.height, alignment: .top)
        .background(.black, in: NotchPanelShape())
        .clipShape(NotchPanelShape())
        .contentShape(NotchPanelShape())
        .foregroundStyle(.white)
        .tint(CompanionStyle.accent)
        .preferredColorScheme(.dark)
        .onHover { notch.setPointerInsidePanel($0) }
        .onAppear { loadSettings() }
        .onChange(of: notch.presentation) { _, presentation in if presentation == .focusSetup { loadSettings() } }
        .onExitCommand { notch.hide() }
    }

    private var face: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !preferences.characterMotion || preferences.usesReducedMotion || !notch.isVisible)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let animates = preferences.characterMotion && !preferences.usesReducedMotion
            Button { notch.focusMainWindow() } label: {
                CompanionFace(blinking: animates && time.truncatingRemainder(dividingBy: 5) < 0.16, focusing: assistant.isRunning && assistant.interval == .focus)
                    .scaleEffect(animates ? 1 + sin(time * 1.4) * 0.012 : 1)
            }.buttonStyle(.plain).accessibilityLabel("Open Sieghart")
        }.frame(width: 42, height: 42)
    }

    private var home: some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 0.08, paused: !preferences.characterMotion || preferences.usesReducedMotion || !notch.isVisible)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let reacts = context.date < avatarReactionUntil
                let moves = preferences.characterMotion && !preferences.usesReducedMotion
                Button { avatarReactionUntil = Date().addingTimeInterval(1.4) } label: {
                    CompanionFace(blinking: moves && time.truncatingRemainder(dividingBy: 5) < 0.16, joyful: reacts)
                        .scaleEffect((74.0 / 42) * (moves ? 1 + sin(time * 1.4) * 0.018 : 1))
                        .rotationEffect(.degrees(moves && reacts ? sin(time * 9) * 7 : 0))
                        .offset(moves ? avatarPointer : .zero)
                        .frame(width: 74, height: 74)
                        .overlay(alignment: .topTrailing) {
                            if reacts { Image(systemName: "sparkles").foregroundStyle(CompanionStyle.accent).offset(x: 14, y: -4) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Interact with Sieghart")
                .help("Say hello to Sieghart")
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): avatarPointer = CGSize(width: (location.x - 37) / 15, height: (location.y - 37) / 15)
                    case .ended: avatarPointer = .zero
                    }
                }
            }.frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Button("Focus") { notch.showFocusSetup() }.buttonStyle(CompanionButtonStyle(primary: true))
                if assistant.hasActiveSession {
                    Button { notch.showCurrentTask() } label: {
                        Label(assistant.pomodoroTimeLabel, systemImage: "timer").monospacedDigit()
                    }.buttonStyle(.plain).font(.callout).help("Open current timer")
                } else if assistant.pomodoroPhase == .completed && assistant.interval == .focus {
                    Button("Break") { notch.showCurrentTask() }.buttonStyle(.plain).font(.callout)
                }
                Spacer()
                iconButton("mic.fill", label: "Speak a command") { activation.toggleListening() }
                iconButton("gearshape", label: "Open preferences") { notch.focusMainWindow() }
                iconButton("xmark", label: "Hide widget") { notch.hide() }
            }
        }
    }

    private var setup: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                face
                title("Focus session", caption: "Choose time & rhythm.")
                Spacer()
                Text(String(format: "%02d:00", Int(minutes))).font(.system(size: 32, weight: .medium)).monospacedDigit()
                iconButton("xmark", label: "Back to Sieghart") { notch.show() }
            }
            VStack(spacing: 6) {
                HStack {
                    Text("Focus length")
                    Spacer()
                    Text("\(Int(minutes)) minutes")
                }.font(.caption).foregroundStyle(CompanionStyle.muted)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<31) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Double(index) <= (minutes - 5) / 55 * 30 ? CompanionStyle.accent : CompanionStyle.separator)
                            .frame(height: index % 5 == 0 ? 24 : 12)
                    }
                }.frame(height: 24).accessibilityHidden(true)
                Slider(value: $minutes, in: 5...60, step: 5).accessibilityLabel("Focus duration in minutes")
                    .accessibilityValue("\(Int(minutes)) minutes")
                HStack {
                    ForEach([5, 15, 25, 35, 45, 60], id: \.self) { value in
                        if value != 5 { Spacer() }
                        Text(value == 60 ? "60 min" : "\(value)")
                    }
                }.font(.caption2).foregroundStyle(CompanionStyle.muted)
            }
            HStack(spacing: 14) {
                settingPicker("Short break", selection: $shortBreak, choices: AssistantViewModel.shortBreakLengths, suffix: "min")
                settingPicker("Long break", selection: $longBreak, choices: AssistantViewModel.longBreakLengths, suffix: "min")
                settingPicker("Rounds", selection: $rounds, choices: AssistantViewModel.roundCounts, suffix: "sessions")
            }
            Toggle("Start breaks automatically", isOn: $autoBreak)
                .font(.caption).foregroundStyle(CompanionStyle.muted).toggleStyle(.switch).controlSize(.small)
            HStack(spacing: 8) {
                Button("Back") { notch.show() }.buttonStyle(CompanionButtonStyle())
                Button {
                    assistant.startFocusSession(minutes: Int(minutes), shortBreak: shortBreak, longBreak: longBreak, rounds: rounds, autoBreak: autoBreak)
                    notch.showCurrentTask()
                } label: {
                    Text(assistant.hasActiveSession ? "Start new focus" : "Start focus").frame(maxWidth: .infinity)
                }.buttonStyle(CompanionButtonStyle(primary: true))
            }
        }
    }

    private var timer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                face
                title(assistant.activityTitle, caption: assistant.sessionCaption).frame(width: 88, alignment: .leading)
                Spacer(minLength: 0)
                if preferences.compactTimer {
                    Text(assistant.pomodoroTimeLabel).font(.system(size: 32, weight: .medium)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                iconButton(assistant.isRunning ? "pause.fill" : "play.fill", label: assistant.isRunning ? "Pause timer" : "Resume timer") { assistant.togglePomodoro() }
                iconButton("stop.fill", label: "Finish session") { assistant.finishPomodoroFromWidget() }
            }
            if !preferences.compactTimer {
                Text(assistant.pomodoroTimeLabel).font(.system(size: 48, weight: .medium)).monospacedDigit()
            }
            GeometryReader { geometry in
                Capsule().fill(CompanionStyle.separator)
                    .overlay(alignment: .leading) {
                        Capsule().fill(CompanionStyle.accent).frame(width: geometry.size.width * assistant.pomodoroProgress)
                    }
            }.frame(height: 3).accessibilityLabel("Time remaining").accessibilityValue("\(Int(assistant.pomodoroProgress * 100)) percent")
            HStack(spacing: 8) {
                Text(assistant.pomodoroPhase == .paused ? "Resume whenever you’re ready." : assistant.interval == .focus ? "Stay with one thing." : "Take a breath. Come back ready.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
                Spacer(minLength: 0)
                Button("Adjust") { notch.showFocusSetup() }.font(.caption).buttonStyle(.plain).foregroundStyle(CompanionStyle.muted)
                iconButton("xmark", label: "Hide widget") { notch.hide() }
            }
        }
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

    private var voice: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                face
                title(activation.isListening ? "Listening…" : activation.awaitingVoiceConfirmation ? "I heard you" : "Voice", caption: activation.voiceStatus)
                Spacer()
                iconButton("xmark", label: "Cancel voice command") { activation.cancelVoiceCommand() }
            }
            Text(activation.transcript.isEmpty ? "Try “start focus” or “pause timer”." : "“\(activation.transcript)”")
                .font(activation.transcript.isEmpty ? .callout : .title3).lineLimit(2)
                .foregroundStyle(activation.transcript.isEmpty ? CompanionStyle.muted : .white)
            HStack(spacing: 8) {
                Button("Cancel") { activation.cancelVoiceCommand() }.buttonStyle(CompanionButtonStyle())
                if activation.awaitingVoiceConfirmation {
                    Button("Run command") { activation.confirmVoiceCommand() }.buttonStyle(CompanionButtonStyle(primary: true))
                } else if activation.isListening {
                    Button("Done speaking") { activation.finishListening() }.buttonStyle(CompanionButtonStyle(primary: true))
                }
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
                .frame(width: 32, height: 32).background(CompanionStyle.surface, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }

    private func settingPicker(_ title: String, selection: Binding<Int>, choices: [Int], suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption2).foregroundStyle(CompanionStyle.muted)
            Picker(title, selection: selection) {
                ForEach(choices, id: \.self) { value in Text("\(value) \(suffix)").tag(value) }
            }.labelsHidden().pickerStyle(.menu).controlSize(.small)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadSettings() {
        minutes = Double(assistant.focusMinutes)
        shortBreak = assistant.shortBreakMinutes
        longBreak = assistant.longBreakMinutes
        rounds = assistant.sessionsPerCycle
        autoBreak = assistant.autoStartBreaks
    }
}

private struct NotchPanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(NotchGeometry.cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
