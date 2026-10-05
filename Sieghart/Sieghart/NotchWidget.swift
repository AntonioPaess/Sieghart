import AppKit
import Combine
import SwiftUI

struct NotchGeometry: Equatable {
    let width: CGFloat
    let cutoutWidth: CGFloat
    let cutoutHeight: CGFloat
    let bodyHeight: CGFloat
    var compact = false
    static let cornerRadius: CGFloat = 24
    var contentTop: CGFloat { compact ? 0 : cutoutHeight + 6 }
    var height: CGFloat { contentTop + bodyHeight }
    var size: CGSize { CGSize(width: width, height: height) }
    static let fallback = NotchGeometry(width: 480, cutoutWidth: 180, cutoutHeight: 0)

    init(width: CGFloat, cutoutWidth: CGFloat, cutoutHeight: CGFloat, bodyHeight: CGFloat = 192, compact: Bool = false) {
        self.width = width; self.cutoutWidth = cutoutWidth; self.cutoutHeight = cutoutHeight
        // The compact island grows sideways around the camera, never below
        // its physical cutout. Displays without a notch use a 36-point pill.
        self.bodyHeight = compact ? (cutoutHeight > 0 ? cutoutHeight : 36) : bodyHeight
        self.compact = compact
    }

    init(screen: NSScreen, setup: Bool = false, bodyHeight: CGFloat = 192, compact: Bool = false) {
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let measuredWidth = left != nil && right != nil ? max(0, right!.minX - left!.maxX) : 0
        let measuredHeight = measuredWidth > 0 ? max(screen.safeAreaInsets.top, min(left!.height, right!.height)) : 0
        self.init(width: compact ? (measuredWidth > 0 ? measuredWidth + 148 : 240) : min(max(setup ? 520 : 480, measuredWidth + 188), screen.frame.width - 32), cutoutWidth: compact ? measuredWidth : max(measuredWidth, 180), cutoutHeight: measuredHeight, bodyHeight: bodyHeight, compact: compact)
    }
}

enum NotchPresentation: Equatable {
    case home, focusSetup, timer, completion, voice, island, celebration
}

@MainActor
final class NotchWidgetController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var geometry: NotchGeometry = .fallback

    @Published private(set) var presentation: NotchPresentation = .home

    @Published private(set) var latestCompletion: SessionCompletion?
    private var shownCompletionID: UUID?
    private let managesWindows: Bool
    private let announcementDelay: Duration
    private var expandTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var completionObservation: AnyCancellable?
    private let preferences: CompanionPreferences
    private let assistant: AssistantViewModel
    var activation: ActivationController?
    private var panel: NSPanel?
    private var hoverPanel: HoverZonePanel?
    private var isPointerInsidePanel = false
    private var isImpactRevealed = false
    private var hideTask: Task<Void, Never>?
    private var pomodoroObservation: AnyCancellable?
    private var preferencesObservation: AnyCancellable?
    private var screenChangeObserver: AnyCancellable?
    private var workspaceObservation: AnyCancellable?
    private let overlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.mainMenu.rawValue + 3
    )

    init(assistant: AssistantViewModel, preferences: CompanionPreferences, managesWindows: Bool = true, announcementDelay: Duration = .seconds(5)) {
        self.assistant = assistant
        self.preferences = preferences
        self.managesWindows = managesWindows
        self.announcementDelay = announcementDelay
        if managesWindows {
            if let screen = Self.selectedScreen() { geometry = NotchGeometry(screen: screen) }
            configureHoverZone()
            screenChangeObserver = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.screenDidChange() }
            let workspace = NSWorkspace.shared.notificationCenter
            workspaceObservation = Publishers.Merge(
                workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
                workspace.publisher(for: NSWorkspace.didActivateApplicationNotification)
            )
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshWorkspacePresence() }
            preferencesObservation = preferences.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    if self.preferences.hoverEnabled { self.hoverPanel?.orderFrontRegardless() }
                    else { self.hoverPanel?.orderOut(nil) }
                    self.screenDidChange()
                }
        }
        completionObservation = assistant.$completionNotice.compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] notice in self?.presentCompletion(notice) }
        pomodoroObservation = assistant.$pomodoroPhase
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handlePomodoroPhaseChange(phase)
            }
    }

    func toggle() {
        isVisible && presentation != .island ? hide() : show()
    }

    // Every normal reveal returns to the companion. Timer tools are explicit.
    func show() {
        presentation = activation?.isListening == true || activation?.isPreparing == true ? .voice : .home
        reveal(stickyUntilImpact: presentation == .voice)
    }

    func showCurrentTask() {
        if assistant.hasActiveSession { presentation = .timer }
        else if assistant.pomodoroPhase == .completed { presentation = .completion }
        else { presentation = .home }
        reveal(stickyUntilImpact: presentation == .completion)
    }

    func showIsland() {
        guard assistant.hasActiveSession else { dismissPanel(); return }
        presentation = .island
        reveal(stickyUntilImpact: false)
    }

    func restoreSessionPresence() { if assistant.hasActiveSession { showIsland() } }

    func showFocusSetup() {
        presentation = .focusSetup
        reveal(stickyUntilImpact: true)
    }

    func showVoice() {
        presentation = .voice
        reveal(stickyUntilImpact: true)
    }

    func handleImpact() {
        if isVisible && presentation != .island {
            hide()
        } else {
            show()
            isImpactRevealed = true
        }
    }

    func setPointerInsidePanel(_ isInside: Bool) {
        isPointerInsidePanel = isInside
        expandTask?.cancel()
        if isInside {
            hideTask?.cancel()
            if presentation == .island {
                expandTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled, let self, self.isPointerInsidePanel, self.presentation == .island else { return }
                    self.showCurrentTask()
                }
            }
        } else if isVisible && (presentation == .home || presentation == .timer || presentation == .celebration) {
            scheduleHide()
        }
    }

    func hide() {
        expandTask?.cancel()
        completionTask?.cancel()
        if activation?.isListening == true || activation?.isPreparing == true { activation?.cancelVoiceCommand(); return }
        if let latestCompletion, latestCompletion.id != shownCompletionID { presentCompletion(latestCompletion); return }
        if assistant.hasActiveSession { showIsland() }
        else { dismissPanel() }
    }

    private func dismissPanel() {
        hideTask?.cancel()
        hideTask = nil
        isVisible = false
        isImpactRevealed = false
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func handlePomodoroPhaseChange(_ phase: PomodoroPhase) {
        guard phase == assistant.pomodoroPhase else { return }
        if presentation == .voice || presentation == .celebration { return }
        switch phase {
        case .focusing, .paused: showIsland()
        case .completed: break // The completion event includes the interval that just ended.
        case .idle:
            if presentation != .focusSetup { show() }
        }
    }

    private func presentCompletion(_ notice: SessionCompletion) {
        latestCompletion = notice
        guard activation?.isListening != true, activation?.isPreparing != true else { return }
        shownCompletionID = notice.id
        presentation = .celebration
        reveal(stickyUntilImpact: false)
        completionTask?.cancel()
        completionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.announcementDelay)
            guard !Task.isCancelled, self.presentation == .celebration, self.latestCompletion?.id == notice.id else { return }
            if !self.isPointerInsidePanel { self.hide() }
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
        isImpactRevealed = stickyUntilImpact
        isVisible = true
        screenDidChange()
        if presentation == .home || presentation == .timer {
            if !isPointerInsidePanel { scheduleHide() }
        }
        guard managesWindows else { return }
        makePanelIfNeeded()

        guard let panel else { return }
        guard let screen = notchScreen else { return }
        let size = geometry.size
        let expanded = NSRect(x: notchCenterX(on: screen) - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        isVisible = true
        // Resize the native panel immediately. Animating a window smaller than
        // its fixed SwiftUI content centers and crops that content mid-reveal.
        panel.setFrame(expanded, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: expanded.size)
        // Keep the black backplate opaque. Fading the entire window mixes in
        // the bright app underneath and makes the notch appear gray.
        panel.alphaValue = 1
        panel.orderFrontRegardless()
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
        widgetPanel.colorSpace = .sRGB
        // The panel must visually merge with the physical notch. A shadow and a
        // translucent fill make the content underneath look like it is showing
        // through the widget.
        widgetPanel.hasShadow = false
        // The notch is composited with the menu bar. A level above the main
        // menu keeps the widget in the same visual plane as the notch instead
        // of leaving it underneath the menu bar surface.
        configureOverlay(widgetPanel)
        widgetPanel.isMovableByWindowBackground = false
        let hosting = NSHostingView(
            rootView: NotchWidgetView()
                .environmentObject(self)
                .environmentObject(assistant)
                .environmentObject(activation)
                .environmentObject(preferences)
        )

        // The controller owns the panel geometry. SwiftUI must not keep the
        // initial home min/max bounds when switching to a larger tool view.
        hosting.focusRingType = .none
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
        configureOverlay(hover)

        let view = HoverZoneView()
        view.onEnter = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.preferences.hoverEnabled else { return }
                if self.presentation == .island { self.showCurrentTask() }
                else if !self.isVisible { self.show() }
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

    private func configureOverlay(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.level = overlayLevel
        panel.hidesOnDeactivate = false
        // canJoinAllApplications is the cross-app full-screen policy on our
        // macOS 14.6+ target. A specific fullScreenAuxiliary policy overrides
        // that classification; let the overlay join other apps directly.
        panel.collectionBehavior = [
            .canJoinAllApplications, .canJoinAllSpaces,
            .fullScreenDisallowsTiling, .stationary, .ignoresCycle
        ]
    }

    private func refreshWorkspacePresence() {
        // A Space transition doesn't change the timer or reopen a dismissed
        // companion. Restore ordering only for surfaces that should be visible.
        screenDidChange()
        if preferences.hoverEnabled { hoverPanel?.orderFrontRegardless() }
        if isVisible { panel?.orderFrontRegardless() }
    }

    private func screenDidChange() {
        let height: CGFloat
        switch presentation {
        case .home: height = 192
        case .focusSetup: height = 390
        case .timer: height = preferences.compactTimer ? 150 : 220
        case .completion: height = 148
        case .voice: height = 208
        case .island: height = 42
        case .celebration: height = 212
        }
        if managesWindows, let screen = notchScreen { geometry = NotchGeometry(screen: screen, setup: presentation == .focusSetup, bodyHeight: height, compact: presentation == .island) }
        else { geometry = NotchGeometry(width: presentation == .island ? 240 : presentation == .focusSetup ? 520 : 480, cutoutWidth: 0, cutoutHeight: 0, bodyHeight: height, compact: presentation == .island) }
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
            let delay: Duration = self?.presentation == .celebration ? self?.announcementDelay ?? .seconds(5) : .milliseconds(1100)
            try? await Task.sleep(for: delay)
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

struct NotchWidgetView: View {
    @EnvironmentObject private var notch: NotchWidgetController
    @EnvironmentObject private var assistant: AssistantViewModel
    @EnvironmentObject private var activation: ActivationController
    @EnvironmentObject private var preferences: CompanionPreferences
    @StateObject private var reactions = CompanionReactions()
    @State private var avatarPointer = CGSize.zero

    init(reactions: CompanionReactions = CompanionReactions()) {
        _reactions = StateObject(wrappedValue: reactions)
    }

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
                case .island: island
                case .celebration: celebration
                }
            }
            .id(notch.presentation)
            .transition(.opacity)
            .animation(preferences.usesReducedMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: notch.presentation)
            .padding(notch.presentation == .island ? 0 : 20)
            .frame(width: notch.geometry.width, height: notch.geometry.bodyHeight, alignment: .top)
        }
        .frame(width: notch.geometry.width, height: notch.geometry.height, alignment: .top)
        .background(CompanionStyle.notchBlack, in: NotchPanelShape())
        .clipShape(NotchPanelShape())
        .contentShape(NotchPanelShape())
        .foregroundStyle(.white)
        .tint(CompanionStyle.accent)
        .preferredColorScheme(.dark)
        .onHover { notch.setPointerInsidePanel($0) }
        .focusEffectDisabled()
        .onExitCommand { notch.hide() }
        .onChange(of: preferences.avatar) { _, _ in reactions.reset() }
        .onChange(of: notch.presentation) { _, presentation in if presentation != .home { reactions.reset() } }
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
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12)
                        let walking = animates && reactions.mood == .idle && !activation.commandAcknowledged && phase < 4
                        CompanionCharacter(size: 96, avatar: preferences.avatar, animates: animates, gaze: avatarPointer, mood: activation.commandAcknowledged ? .understood : reactions.mood, strolling: walking)
                            .offset(x: walking ? sin(phase / 4 * .pi * 2) * 14 : 0)
                    }.frame(width: 124, height: 96)
                }
                .accessibilityLabel("Interact with Sieghart")
                .accessibilityValue(reactionDescription)
                .help("Say hello. Repeated taps make Sieghart grumpy, then sleepy. Tap again to wake.")
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): avatarPointer = animates ? CGSize(width: min(3, max(-3, (location.x - 62) / 16)), height: min(2, max(-2, (location.y - 48) / 24))) : .zero
                    case .ended: avatarPointer = .zero
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(assistant.hasActiveSession ? assistant.activityTitle.uppercased() : "YOUR COMPANION")
                        .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(CompanionStyle.muted)
                    Text(homeHeadline).font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    Text(homeMessage).font(.callout).foregroundStyle(CompanionStyle.muted).lineLimit(2)
                    HStack(spacing: 12) {
                        Label(assistant.hasActiveSession ? assistant.pomodoroTimeLabel : "\(assistant.focusMinutes) min focus", systemImage: "timer").monospacedDigit()
                        Text("\(assistant.completedSessions) done")
                    }.font(.caption.weight(.medium)).foregroundStyle(CompanionStyle.accent)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button("Focus") { notch.showFocusSetup() }.buttonStyle(CompanionButtonStyle(primary: true)).focusEffectDisabled()
                if assistant.hasActiveSession {
                    Button { notch.showCurrentTask() } label: { Label("Controls", systemImage: "timer") }
                        .buttonStyle(.plain).focusEffectDisabled().font(.callout).help("Open current timer")
                } else if assistant.pomodoroPhase == .completed && assistant.interval == .focus {
                    Button("Break") { notch.showCurrentTask() }.buttonStyle(.plain).focusEffectDisabled().font(.callout)
                }
                Spacer()
                iconButton("mic.fill", label: "Speak a command") { activation.toggleListening() }
                iconButton("gearshape", label: "Open preferences") { notch.focusMainWindow() }
                iconButton("xmark", label: "Tuck away widget") { notch.hide() }
            }
        }
    }

    private func reactToTouch() {
        reactions.touch()
    }

    private var homeHeadline: String {
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
        if activation.commandAcknowledged { return activation.voiceStatus }
        switch reactions.mood {
        case .happy: return "Nice to see you. Easy on the pokes."
        case .annoyed: return "Give me a second to catch my breath."
        case .asleep: return "Tap once to wake me up."
        case .waking: return "That was a very short nap."
        default:
            if assistant.pomodoroPhase == .paused { return "Resume whenever you’re ready." }
            return assistant.hasActiveSession ? "\(assistant.pomodoroTimeLabel) left. \(assistant.interval == .focus ? "I’ll let you know when it’s time to rest." : "Enjoy your break — I’ll keep the time.")" : "Your \(assistant.focusMinutes)-minute focus session is one tap away."
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
        VStack(spacing: 20) {
            HStack(spacing: 10) {
                face
                title("Focus session", caption: "Choose time & rhythm.")
                Spacer()
                iconButton("xmark", label: "Back to Sieghart") { notch.show() }
            }
            FocusSessionEditor(onStart: { notch.showIsland() }, onCancel: { notch.show() })
        }
    }

    private var island: some View {
        Button { notch.showCurrentTask() } label: {
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
                            }.foregroundStyle(CompanionStyle.accent)
                        } else {
                            CompanionCharacter(size: 26, avatar: preferences.avatar, animates: animates, focusing: assistant.isRunning && assistant.interval == .focus, strolling: walking)
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
                                .foregroundStyle(finishing ? CompanionStyle.accent : .white)
                                .contentTransition(.numericText(countsDown: true))
                                .offset(x: nudge * 2, y: -nudge)
                                .animation(animates ? .easeOut(duration: 0.2) : nil, value: assistant.pomodoroTimeLabel)
                            if !finishing { islandProgress }
                        }
                    }.frame(maxWidth: .infinity)
                }.padding(.horizontal, 8).frame(height: notch.geometry.bodyHeight)
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
                iconButton("xmark", label: "Tuck away widget") { notch.hide() }
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
                title(activation.commandAcknowledged ? "Got it." : activation.isListening ? "Listening…" : activation.isPreparing ? "Getting ready…" : "Voice", caption: activation.voiceStatus)
                Spacer()
                iconButton("xmark", label: "Cancel voice command") { activation.cancelVoiceCommand() }
            }
            Text(activation.transcript.isEmpty ? "Try “start focus” or “pause timer”." : "“\(activation.transcript)”")
                .font(activation.transcript.isEmpty ? .callout : .title3).lineLimit(2)
                .foregroundStyle(activation.transcript.isEmpty ? CompanionStyle.muted : .white)
            HStack(spacing: 8) {
                Button("Cancel") { activation.cancelVoiceCommand() }.buttonStyle(CompanionButtonStyle())
                if activation.isListening { Text("Finish speaking to run your command.").font(.caption).foregroundStyle(CompanionStyle.muted) }
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
        }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel(label).help(label)
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
