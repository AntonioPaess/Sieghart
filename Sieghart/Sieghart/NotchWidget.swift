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
    // The camera gap is part of the activation target, just like both wings.
    // Expanded targets occupy the header only, leaving the controls accessible.
    var activationSize: CGSize { CGSize(width: width, height: compact ? height : max(6, cutoutHeight)) }
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
    case home, focusSetup, timer, completion, voice, island, celebration, aiLimits, tools, audio, avatars
}

@MainActor
final class NotchWidgetController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var isPointerHovering = false
    @Published private(set) var geometry: NotchGeometry = .fallback

    @Published private(set) var presentation: NotchPresentation = .home

    @Published private(set) var latestCompletion: SessionCompletion?
    private var shownCompletionID: UUID?
    private let managesWindows: Bool
    private let announcementDelay: Duration
    static let pointerExitDelay: Duration = .milliseconds(800)
    static let keyboardRevealDelay: Duration = .seconds(4)
    private let pointerExitDelay: Duration
    private let keyboardRevealDelay: Duration
    private var revealGraceDeadline: ContinuousClock.Instant?
    private var completionTask: Task<Void, Never>?
    private var completionObservation: AnyCancellable?
    private let preferences: CompanionPreferences
    private let assistant: AssistantViewModel
    var activation: ActivationController?
    var codexUsage: CodexUsageModel?
    var aiUsage: AIUsageModel?
    let audio: AudioController
    private var activityObservation: AnyCancellable?
    private var panel: NSPanel?
    private var canvas: IslandWindowCanvas<AnyView>?
    private var hoverPanel: HoverZonePanel?
    private var isPointerInsidePanel = false
    private var isPointerInsideHoverZone = false
    private var pointerInsideInteractiveArea: Bool {
        guard managesWindows else { return isPointerInsidePanel || isPointerInsideHoverZone }
        let point = NSEvent.mouseLocation
        return trackingIslandMenu || (hoverPanel?.frame.contains(point) ?? false) || (isVisible && (panel?.frame.contains(point) ?? false))
    }
    private var lastPointerInside = false
    private var pointerPresenceTask: Task<Void, Never>?
    private var cameraClickMonitor: Any?
    private var hideTask: Task<Void, Never>?
    private var pomodoroObservation: AnyCancellable?
    private var clockObservation: AnyCancellable?
    private var preferencesObservation: AnyCancellable?
    private var screenChangeObserver: AnyCancellable?
    private var workspaceObservation: AnyCancellable?
    private var menuObservation: AnyCancellable?
    private var trackingIslandMenu = false
    private let overlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.mainMenu.rawValue + 3
    )

    init(assistant: AssistantViewModel, preferences: CompanionPreferences, audio: AudioController? = nil, managesWindows: Bool = true, announcementDelay: Duration = .seconds(5), pointerExitDelay: Duration = NotchWidgetController.pointerExitDelay, keyboardRevealDelay: Duration = NotchWidgetController.keyboardRevealDelay) {
        self.assistant = assistant
        self.audio = audio ?? AudioController()
        self.preferences = preferences
        self.managesWindows = managesWindows
        self.announcementDelay = announcementDelay
        self.pointerExitDelay = pointerExitDelay
        self.keyboardRevealDelay = keyboardRevealDelay
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
            menuObservation = Publishers.Merge(
                NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification),
                NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            ).sink { [weak self] note in
                guard let self else { return }
                if note.name == NSMenu.didBeginTrackingNotification {
                    guard self.isVisible, self.presentation != .island, self.pointerInsideInteractiveArea else { return }
                    self.trackingIslandMenu = true
                } else if self.trackingIslandMenu { self.trackingIslandMenu = false }
                self.updatePointerPresence()
            }
            preferencesObservation = preferences.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.hoverPanel?.orderFrontRegardless()
                    self.screenDidChange()
                }
        }
        // A saved completion is context, never a new announcement on launch.
        latestCompletion = assistant.completionNotice
        shownCompletionID = assistant.completionNotice?.id
        completionObservation = assistant.$completionNotice.compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] notice in self?.presentCompletion(notice) }
        pomodoroObservation = assistant.$pomodoroPhase
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handlePomodoroPhaseChange(phase)
            }
        clockObservation = assistant.utilityClock.$phase.dropFirst().receive(on: RunLoop.main).sink { [weak self] phase in
            guard let self, phase == self.assistant.utilityClock.phase else { return }
            // A clock tick never changes the user's open page.
            if phase == .completed && self.presentation == .island {
                self.assistant.selectTimerMode(.timer)
                self.presentation = .timer
                self.reveal(approachGrace: false)
                self.scheduleHide(delay: self.announcementDelay)
            } else if !self.isVisible && self.assistant.hasTimerActivity { self.showIsland() }
            else if self.presentation == .island && !self.assistant.hasTimerActivity && (self.aiUsage?.analytics.work.isEmpty ?? true) { self.dismissPanel() }
        }
    }

    func toggle() {
        isVisible && presentation != .island ? hide() : show()
    }

    func clickIsland() {
        if isVisible && presentation != .island { hide() }
        else { showCurrentTask() }
    }

    // Every normal reveal returns to the companion. Timer tools are explicit.
    func show() {
        presentation = activation?.isListening == true || activation?.isPreparing == true ? .voice : .home
        reveal()
    }

    func showCurrentTask() {
        if !(aiUsage?.analytics.work.isEmpty ?? true) { presentation = .aiLimits }
        else if assistant.hasTimerActivity { assistant.selectTimerMode(assistant.activeTimerMode); presentation = .timer }
        else { presentation = .home }
        reveal()
    }

    func showIsland() {
        guard assistant.hasTimerActivity || !(aiUsage?.analytics.work.isEmpty ?? true) else { dismissPanel(); return }
        presentation = .island
        reveal()
    }

    func restoreSessionPresence() { if assistant.hasTimerActivity || !(aiUsage?.analytics.work.isEmpty ?? true) { showIsland() } }

    func observeAIActivity() {
        activityObservation = aiUsage?.$analytics.receive(on: RunLoop.main).sink { [weak self] analytics in
            guard let self else { return }
            if !analytics.work.isEmpty && !self.isVisible { self.showIsland() }
            else if analytics.work.isEmpty && !self.assistant.hasTimerActivity && self.presentation == .island { self.dismissPanel() }
        }
    }

    func showTimer() {
        if assistant.hasTimerActivity { assistant.selectTimerMode(assistant.activeTimerMode) }
        presentation = .timer; reveal()
    }

    func showFocusSetup() {
        assistant.selectTimerMode(.pomodoro)
        presentation = .focusSetup
        reveal()
    }

    func showTools() {
        presentation = .tools
        reveal()
    }

    func showAILimits() {
        presentation = .aiLimits
        reveal()
    }

    func showAudio() { presentation = .audio; reveal() }
    func showAvatars() { presentation = .avatars; reveal() }

    func showVoice() {
        presentation = .voice
        reveal()
    }

    func handleImpact() {
        if isVisible && presentation != .island {
            hide()
        } else {
            show()
        }
    }

    func setPointerInsidePanel(_ isInside: Bool) {
        isPointerInsidePanel = isInside
        updatePointerPresence()
    }

    func setPointerInsideHoverZone(_ isInside: Bool) {
        isPointerInsideHoverZone = isInside
        if isInside { showHoverFeedback() }
        updatePointerPresence()
    }

    private func updatePointerPresence() {
        let inside = pointerInsideInteractiveArea
        isPointerHovering = inside && preferences.hoverEnabled
        lastPointerInside = inside
        if inside { revealGraceDeadline = nil; hideTask?.cancel() }
        else if isVisible { scheduleHide(delay: pointerExitDelay) }
    }

    private func showHoverFeedback() {
        guard preferences.hoverEnabled else { return }
        isPointerHovering = true
        hideTask?.cancel()
        if !isVisible { presentation = .island; reveal() }
    }

    func hide() {
        completionTask?.cancel()
        if activation?.isListening == true || activation?.isPreparing == true { activation?.cancelVoiceCommand(); return }
        if assistant.hasTimerActivity || !(aiUsage?.analytics.work.isEmpty ?? true) { showIsland() }
        else { dismissPanel() }
    }

    private func dismissPanel() {
        hideTask?.cancel()
        hideTask = nil
        isVisible = false
        trackingIslandMenu = false
        revealGraceDeadline = nil
        pointerPresenceTask?.cancel(); pointerPresenceTask = nil
        guard let panel, panel.isVisible else { return }
        guard let canvas, let screen = notchScreen, !preferences.usesReducedMotion else { panel.orderOut(nil); return }
        let compact = NotchGeometry(screen: screen, compact: true)
        canvas.prepare(target: compact.canvasGeometry, reserved: panel.frame.size, animated: true, closing: true) { [weak self, weak panel] in
            guard self?.isVisible == false else { return }
            panel?.orderOut(nil)
        }
    }

    private func handlePomodoroPhaseChange(_ phase: PomodoroPhase) {
        guard phase == assistant.pomodoroPhase else { return }
        if presentation == .voice || presentation == .celebration || presentation == .aiLimits || presentation == .tools || presentation == .audio || presentation == .avatars { return }
        switch phase {
        case .focusing, .paused:
            if !isVisible || presentation == .island { showIsland() }
        case .completed: break // The completion event includes the interval that just ended.
        case .idle:
            if isVisible && presentation != .focusSetup && presentation != .timer { show() }
        }
    }

    private func presentCompletion(_ notice: SessionCompletion) {
        latestCompletion = notice
        guard notice.id != shownCompletionID else { return }
        guard activation?.isListening != true, activation?.isPreparing != true else { return }
        shownCompletionID = notice.id
        presentation = .celebration
        reveal()
        completionTask?.cancel()
        completionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.announcementDelay)
            guard !Task.isCancelled, self.presentation == .celebration, self.latestCompletion?.id == notice.id else { return }
            if !self.pointerInsideInteractiveArea { self.hide() }
        }
    }

    func focusMainWindow() {
        guard let mainWindow = NSApp.windows.first(where: { $0 !== panel && $0.title == "Sieghart" }) else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
    }

    private func reveal(approachGrace: Bool = true) {
        hideTask?.cancel()
        hideTask = nil
        revealGraceDeadline = nil
        isVisible = true
        screenDidChange()
        if approachGrace && !pointerInsideInteractiveArea && presentation != .island && presentation != .voice && presentation != .celebration {
            revealGraceDeadline = .now.advanced(by: keyboardRevealDelay)
            scheduleHide(delay: keyboardRevealDelay)
        }
        guard managesWindows else { return }
        makePanelIfNeeded()

        guard let panel else { return }
        guard notchScreen != nil else { return }
        positionPanel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // Keep the activation strip available when expanded, without covering
        // any controls below the camera. A second strip click tucks it away.
        hoverPanel?.orderFrontRegardless()
        trackPointerPresence()
    }

    private func makePanelIfNeeded() {
        guard panel == nil else { return }
        guard let activation, let codexUsage, let aiUsage else { return }

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
        let hosting = IslandWindowCanvas(
            rootView: AnyView(NotchWidgetView()
                .environment(\.nativeIslandCanvas, true)
                .environmentObject(self)
                .environmentObject(assistant)
                .environmentObject(activation)
                .environmentObject(preferences)
                .environmentObject(codexUsage)
                .environmentObject(aiUsage))
        )

        // The controller owns the panel geometry. SwiftUI must not keep the
        // initial home min/max bounds when switching to a larger tool view.
        hosting.frame = NSRect(origin: .zero, size: geometry.size)
        widgetPanel.contentView = hosting
        widgetPanel.contentMinSize = .zero
        widgetPanel.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        panel = widgetPanel
        canvas = hosting
    }

    private func positionPanel() {
        guard let panel, let canvas else { return }
        guard let screen = notchScreen else { return }
        guard canvas.currentSurface != geometry.size || canvas.isDeparting else { return }
        let margin: CGFloat = geometry.compact ? 0 : 144
        let bottom: CGFloat = geometry.compact ? 0 : 64
        let size = CGSize(width: max(canvas.currentSurface.width, geometry.width) + margin, height: max(canvas.currentSurface.height, geometry.height) + bottom)
        let centerX = notchCenterX(on: screen)
        let frame = NSRect(x: centerX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        canvas.prepare(target: geometry.canvasGeometry, reserved: size, animated: !preferences.usesReducedMotion, closing: false) { [weak self] in self?.settlePanel() }
    }

    private func settlePanel() {
        guard let panel, let canvas, let screen = notchScreen, isVisible else { return }
        let size = CGSize(width: geometry.width + (geometry.compact ? 0 : 144), height: geometry.height + (geometry.compact ? 0 : 64))
        panel.setFrame(NSRect(x: notchCenterX(on: screen) - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        canvas.prepare(target: geometry.canvasGeometry, reserved: size, animated: false, closing: false, settled: {})
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
        hover.alphaValue = 1
        hover.hasShadow = false
        configureOverlay(hover)

        let view = HoverZoneView()
        view.onEnter = { [weak self] in
            self?.setPointerInsideHoverZone(true)
        }
        view.onExit = { [weak self] in
            self?.setPointerInsideHoverZone(false)
        }
        view.onClick = { [weak self] in
            self?.clickIsland()
        }
        hover.contentView = view
        hoverPanel = hover
        positionHoverPanel()
        hover.orderFrontRegardless()
        // The WindowServer can route an event over the physical camera gap to
        // another app. Observe that click only within our activation rectangle.
        // Global monitors exclude our own events, so native clicks fire once.
        cameraClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.hoverPanel?.frame.contains(NSEvent.mouseLocation) == true else { return }
                self.clickIsland()
            }
        }
    }

    private func positionHoverPanel() {
        guard let hoverPanel else { return }
        guard let screen = notchScreen else { return }

        let compact = NotchGeometry(screen: screen, compact: true)
        let size = isVisible ? geometry.activationSize : compact.size
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
        // Cross-app overlay classification and full-screen capability are
        // separate option groups in AppKit. Both panels need both policies.
        panel.collectionBehavior = [
            .canJoinAllApplications, .canJoinAllSpaces,
            .fullScreenAuxiliary, .fullScreenDisallowsTiling, .stationary, .ignoresCycle
        ]
        panel.ignoresMouseEvents = false
    }

    private func refreshWorkspacePresence() {
        // A Space transition doesn't change the timer or reopen a dismissed
        // companion. Restore ordering only for surfaces that should be visible.
        screenDidChange()
        if isVisible { panel?.orderFrontRegardless() }
        hoverPanel?.orderFrontRegardless()
    }

    private func screenDidChange() {
        let height: CGFloat
        switch presentation {
        case .home: height = 240
        case .focusSetup: height = 330
        case .timer: height = 330
        case .completion: height = 212
        case .voice: height = 260
        case .island: height = 42
        case .celebration: height = 270
        case .tools: height = 350
        case .audio: height = 460
        case .avatars: height = 340
        case .aiLimits: height = min(470, (notchScreen?.visibleFrame.height ?? 700) - 80)
        }
        let width: CGFloat
        switch presentation {
        case .island: width = 240
        case .aiLimits: width = 800
        case .tools, .audio: width = 760
        case .focusSetup, .timer: width = 720
        default: width = 620
        }
        if managesWindows, let screen = notchScreen {
            let measured = NotchGeometry(screen: screen, bodyHeight: height, compact: presentation == .island)
            geometry = presentation == .island ? measured : NotchGeometry(width: min(width, screen.frame.width - 176), cutoutWidth: measured.cutoutWidth, cutoutHeight: measured.cutoutHeight, bodyHeight: height)
        } else { geometry = NotchGeometry(width: width, cutoutWidth: 0, cutoutHeight: 0, bodyHeight: height, compact: presentation == .island) }
        if presentation != .island {
            let factor = preferences.widgetSize.scale
            geometry = NotchGeometry(width: min(geometry.width * factor, (notchScreen?.frame.width ?? 1400) - 176), cutoutWidth: geometry.cutoutWidth, cutoutHeight: geometry.cutoutHeight, bodyHeight: min(geometry.bodyHeight * factor, (notchScreen?.visibleFrame.height ?? 900) - 40))
        }
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

    private func trackPointerPresence() {
        guard pointerPresenceTask == nil else { return }
        lastPointerInside = pointerInsideInteractiveArea
        pointerPresenceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.isVisible else { return }
                // Read a single pointer point; no global movement hook or input
                // stream. This also covers a camera click without tracking events.
                if self.pointerInsideInteractiveArea != self.lastPointerInside { self.updatePointerPresence() }
            }
        }
    }

    private func scheduleHide(delay: Duration) {
        hideTask?.cancel()
        let grace = revealGraceDeadline.map { ContinuousClock.now.duration(to: $0) } ?? .zero
        let delay = max(delay, grace)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if !self.pointerInsideInteractiveArea {
                self.hide()
            }
        }
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class HoverZonePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class HoverZoneView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }

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

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
    @EnvironmentObject private var aiActivity: AIUsageModel
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
        .foregroundStyle(.white)
        .tint(CompanionStyle.accent)
        .preferredColorScheme(.dark)
        .environment(\.islandGlass, !compact)
        .environment(\.islandReduceMotion, preferences.usesReducedMotion)
        .onHover { notch.setPointerInsidePanel($0) }
        .focusEffectDisabled()
        .onExitCommand { notch.hide() }
        .onChange(of: preferences.avatar) { _, _ in reactions.reset() }
        .onChange(of: notch.presentation) { _, presentation in if presentation != .home { reactions.reset() } }
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
                case .voice: voice
                case .island: island
                case .celebration: celebration
                case .tools: tools
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
            if !nativeCanvas { IslandBackdrop(compact: compact, stripHeight: notch.geometry.cutoutHeight) }
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
                Button("Audio") { notch.showAudio() }
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
        case .audio: "Audio"
        case .avatars: "Choose your companion"
        case .voice: "Voice"
        case .completion, .celebration: "Session complete"
        case .island: ""
        }
    }

    private var quickAccess: some View {
        let width = notch.geometry.width + 144
        return ZStack(alignment: .topLeading) {
            floatingButton("square.grid.2x2", label: "Controls") { notch.showTools() }
                .position(x: 28, y: notch.geometry.contentTop + 52)
            floatingButton("timer", label: "Timer, Pomodoro and stopwatch") { notch.showTimer() }.position(x: 28, y: notch.geometry.contentTop + 106)
            floatingButton("gearshape", label: "Preferences") { notch.focusMainWindow() }
                .position(x: width - 28, y: notch.geometry.contentTop + 52)
            floatingButton("speaker.wave.2", label: "Audio mixer") { notch.showAudio() }
                .position(x: width - 28, y: notch.geometry.contentTop + 106)
            Button { notch.show() } label: {
                CompanionCharacter(size: 32, avatar: preferences.avatar, animates: animates)
                    .frame(width: 44, height: 44).background(.black.opacity(0.6), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.75) }
            }.buttonStyle(IslandButtonStyle()).focusEffectDisabled().accessibilityLabel("Your companion")
                .position(x: width / 2, y: notch.geometry.height + 32)
        }.frame(width: width, height: notch.geometry.height + 64)
    }

    private func floatingButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
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
        }
    }

    private var tools: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            toolTile("Companion", subtitle: preferences.avatar.name, symbol: "face.smiling", avatar: preferences.avatar) { notch.show() }
            toolTile("Audio", subtitle: "Apps & devices", symbol: "speaker.wave.2") { notch.showAudio() }
            toolTile("AI agents", subtitle: "Limits & activity", symbol: "sparkles") { notch.showAILimits() }
            toolTile("Timers", subtitle: "Three ways to time", symbol: "timer") { notch.showTimer() }
            toolTile("Voice", subtitle: activation.voiceShortcut?.label ?? "Speak a command", symbol: "mic") { activation.toggleListening() }
            toolTile("Avatars", subtitle: "Find your companion", symbol: "person.crop.square") { notch.showAvatars() }
            toolTile("Preferences", subtitle: "Your workspace", symbol: "gearshape") { notch.focusMainWindow() }
        }
    }

    private func toolTile(_ name: String, subtitle: String, symbol: String, avatar: CompanionAvatar? = nil, action: @escaping () -> Void) -> some View {
        CompanionInteraction(action: action) {
            VStack(spacing: 12) {
                Group {
                    if let avatar { CompanionCharacter(size: 34, avatar: avatar, animates: false) }
                    else { Image(systemName: symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(CompanionStyle.accent) }
                }.frame(height: 34)
                Text(name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 9)).foregroundStyle(CompanionStyle.muted).lineLimit(1)
            }.frame(maxWidth: .infinity).padding(.vertical, 19).modifier(IslandControlSurface())
        }.accessibilityLabel("\(name). \(subtitle)")
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
            if let work = aiActivity.analytics.work.first {
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
                                Text(assistant.hasTimerActivity ? work.provider.title : "Working").font(.system(size: 8)).foregroundStyle(CompanionStyle.accent)
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
                        Text("Open").font(.system(size: 11, weight: .medium)).foregroundStyle(CompanionStyle.accent).frame(maxWidth: .infinity)
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
                    Text(assistant.utilityClock.isRunning ? assistant.utilityClock.mode.title : "Paused").font(.system(size: 8)).foregroundStyle(CompanionStyle.accent)
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
                            }.foregroundStyle(CompanionStyle.accent)
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
                                .foregroundStyle(finishing ? CompanionStyle.accent : .white)
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
                .frame(width: 32, height: 32).background(.white.opacity(0.08), in: Circle())
        }.buttonStyle(IslandButtonStyle()).focusEffectDisabled().accessibilityLabel(label).help(label)
    }


}

private extension NotchGeometry {
    var canvasGeometry: IslandCanvasGeometry { IslandCanvasGeometry(size: size, cutoutWidth: cutoutWidth, cutoutHeight: cutoutHeight, compact: compact) }
}
