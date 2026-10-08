import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWidgetViewModel: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var isPointerHovering = false
    @Published private(set) var geometry: NotchGeometry = .fallback

    @Published private(set) var presentation: NotchPresentation = .home

    @Published private(set) var welcomeStartedAt: Date?
    private var welcomeTask: Task<Void, Never>?
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
    var codexUsage: CodexUsageViewModel?
    var aiUsage: AIUsageViewModel?
    let clipboard: ClipboardViewModel
    let middleClick: MiddleClickController
    let audio: AudioViewModel
    let monitor: SystemMonitorViewModel
    let keepAwake: KeepAwakeViewModel
    let displayPower: DisplayPowerViewModel
    @Published private(set) var utilityReaction = UUID()
    private(set) var utilitySucceeded = true
    @Published private(set) var utilityMood = CompanionMood.idle
    private var utilityMoodReset: Task<Void, Never>?
    private var lastMonitorWarning: Date?
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
    private var voiceCollapsed = false
    private var pomodoroObservation: AnyCancellable?
    private var clockObservation: AnyCancellable?
    private var preferencesObservation: AnyCancellable?
    private var screenChangeObserver: AnyCancellable?
    private var workspaceObservation: AnyCancellable?
    private var menuObservation: AnyCancellable?
    private var trackingIslandMenu = false
    private var sessionIsActive = true
    private var sessionObservation: AnyCancellable?
    private var overlayLevel: NSWindow.Level { NotchOverlayPolicy.level(fullScreen: foregroundCoversNotchScreen) }

    private var foregroundCoversNotchScreen: Bool {
        guard let screen = notchScreen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let foreground = NSWorkspace.shared.frontmostApplication,
              foreground.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let display = CGDisplayBounds(displayID.uint32Value)
        // Window bounds are metadata; no screen image or window contents are read.
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == foreground.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] else { return false }
            return NotchOverlayPolicy.coversDisplay(CGRect(x: x.doubleValue, y: y.doubleValue, width: w.doubleValue, height: h.doubleValue), display: display)
        }
    }

    init(assistant: AssistantViewModel, preferences: CompanionPreferences, audio: AudioViewModel? = nil, monitor: SystemMonitorViewModel? = nil, keepAwake: KeepAwakeViewModel? = nil, displayPower: DisplayPowerViewModel? = nil, clipboard: ClipboardViewModel? = nil, managesWindows: Bool = true, announcementDelay: Duration = .seconds(5), pointerExitDelay: Duration = NotchWidgetViewModel.pointerExitDelay, keyboardRevealDelay: Duration = NotchWidgetViewModel.keyboardRevealDelay) {
        self.assistant = assistant
        self.middleClick = MiddleClickController()
        self.audio = audio ?? AudioViewModel()
        self.monitor = monitor ?? SystemMonitorViewModel()
        self.keepAwake = keepAwake ?? KeepAwakeViewModel()
        self.displayPower = displayPower ?? DisplayPowerViewModel()
        self.clipboard = clipboard ?? ClipboardViewModel(monitorsSystem: managesWindows)
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
            sessionObservation = Publishers.MergeMany([
                NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification,
                NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification
            ].map { workspace.publisher(for: $0) })
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self else { return }
                if note.name == NSWorkspace.sessionDidResignActiveNotification || note.name == NSWorkspace.willSleepNotification {
                    self.sessionIsActive = false
                    self.activation?.cancelVoiceCommand()
                    self.panel?.orderOut(nil)
                    self.hoverPanel?.orderOut(nil)
                } else {
                    self.sessionIsActive = true
                    self.refreshWorkspacePresence()
                }
            }
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
                    guard let self, self.sessionIsActive else { return }
                    self.hoverPanel?.orderFrontRegardless()
                    self.screenDidChange()
                }
        }
        self.monitor.onReading = { [weak self] reading in
            guard let self else { return }
            let sustained = self.monitor.history.suffix(3).filter { ($0.cpu ?? 0) > 0.9 }.count == 3
            let lowBattery = !reading.onAC && (reading.battery ?? 1) < 0.1
            if (sustained || lowBattery || reading.memoryPressure == "Critical"), self.lastMonitorWarning.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
                self.lastMonitorWarning = Date(); self.reactToUtility(false)
            }
        }
        self.audio.onReaction = { [weak self] success in self?.reactToUtility(success) }
        self.keepAwake.onReaction = { [weak self] success in self?.reactToUtility(success) }
        self.displayPower.onReaction = { [weak self] success in self?.reactToUtility(success) }
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
            else if self.presentation == .island && !self.assistant.hasTimerActivity && self.activation?.voicePresented != true && (self.aiUsage?.analytics.work.isEmpty ?? true) { self.dismissPanel() }
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
        voiceCollapsed = false
        finishWelcome()
        presentation = .home
        reveal()
    }

    func showWelcome() {
        finishWelcome()
        let start = Date().addingTimeInterval(0.35)
        welcomeStartedAt = start; presentation = .home; reveal()
        revealGraceDeadline = ContinuousClock.now + .seconds(5)
        scheduleHide(delay: .seconds(5))
        welcomeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(4500))
            guard !Task.isCancelled, self?.welcomeStartedAt == start else { return }
            self?.welcomeStartedAt = nil
        }
    }
    func finishWelcome() { welcomeTask?.cancel(); welcomeTask = nil; welcomeStartedAt = nil }

    func showCurrentTask() {
        if activation?.isVoiceBusy == true || (voiceCollapsed && activation?.voicePresented == true) { showVoice(resetCollapse: true); return }
        if !(aiUsage?.analytics.work.isEmpty ?? true) { presentation = .aiLimits }
        else if assistant.hasTimerActivity { assistant.selectTimerMode(assistant.activeTimerMode); presentation = .timer }
        else { presentation = .home }
        reveal()
    }

    func showIsland() {
        guard assistant.hasTimerActivity || !(aiUsage?.analytics.work.isEmpty ?? true) || activation?.voicePresented == true else { dismissPanel(); return }
        presentation = .island
        reveal()
    }

    func restoreSessionPresence() { if assistant.hasTimerActivity || !(aiUsage?.analytics.work.isEmpty ?? true) { showIsland() } }

    func observeAIActivity() {
        activityObservation = aiUsage?.$analytics.receive(on: RunLoop.main).sink { [weak self] analytics in
            guard let self else { return }
            if !analytics.work.isEmpty && !self.isVisible { self.showIsland() }
            else if analytics.work.isEmpty && !self.assistant.hasTimerActivity && self.activation?.voicePresented != true && self.presentation == .island { self.dismissPanel() }
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

    func showClipboard() { clipboard.preparePasteTarget(); presentation = .clipboard; reveal() }
    func toggleClipboard() { if isVisible && presentation == .clipboard { hide() } else { showClipboard() } }

    func reactToUtility(_ success: Bool) {
        utilitySucceeded = success; utilityReaction = UUID(); utilityMood = success ? .understood : .startled
        utilityMoodReset?.cancel()
        utilityMoodReset = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled else { return }; self?.utilityMood = .idle
        }
    }
    func startUtilities() { keepAwake.startLifecycle(); displayPower.startLifecycle(); audio.startLifecycle() }
    func stopUtilities() { keepAwake.shutdown(); displayPower.shutdown(); audio.shutdown() }
    func showSystem() { presentation = .system; reveal() }
    func showKeepAwake() { presentation = .keepAwake; reveal() }
    func showDisplayPower() { presentation = .displayPower; reveal() }
    func showAudio() { presentation = .audio; reveal() }
    func showAvatars() { presentation = .avatars; reveal() }

    func showVoice(resetCollapse: Bool = false) {
        finishWelcome()
        if resetCollapse || activation?.isVoiceBusy == true { voiceCollapsed = false }
        presentation = voiceCollapsed ? .island : .home
        reveal(approachGrace: !voiceCollapsed)
    }

    func voiceActivityDidChange() {
        if activation?.isVoiceBusy == true { showVoice(resetCollapse: true) }
        else if isVisible && !pointerInsideInteractiveArea {
            revealGraceDeadline = .now.advanced(by: keyboardRevealDelay)
            scheduleHide(delay: keyboardRevealDelay)
        }
    }

    func collapseAfterPointerExit() {
        // Explicit Cancel/Close still works. Automatic pointer departure never
        // hides the transcript or controls during preparation/capture/draining.
        guard activation?.isVoiceBusy != true else { return }
        guard activation?.voicePresented == true else { hide(); return }
        guard !voiceCollapsed || presentation != .island else { return }
        voiceCollapsed = true
        presentation = .island
        reveal(approachGrace: false)
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
        voiceCollapsed = false
        completionTask?.cancel()
        if activation?.voicePresented == true || activation?.isVoiceBusy == true { activation?.cancelVoiceCommand(); return }
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
        if activation?.isVoiceBusy == true || presentation == .celebration || presentation == .aiLimits || presentation == .tools || presentation == .audio || presentation == .avatars { return }
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
        guard activation?.isVoiceBusy != true else { return }
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
        guard sessionIsActive else { return }
        hideTask?.cancel()
        hideTask = nil
        revealGraceDeadline = nil
        isVisible = true
        screenDidChange()
        if approachGrace && !pointerInsideInteractiveArea && presentation != .island && presentation != .celebration {
            revealGraceDeadline = .now.advanced(by: keyboardRevealDelay)
            scheduleHide(delay: keyboardRevealDelay)
        }
        guard managesWindows else { return }
        makePanelIfNeeded()

        guard let panel else { return }
        guard notchScreen != nil else { return }
        configureOverlay(panel)
        if let hoverPanel { configureOverlay(hoverPanel) }
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
        // Use a higher overlay level only while the foreground app covers the
        // display. Session resignation removes both overlays before locking.
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
        panel.appearance = preferences.appearance.nativeAppearance
        canvas.updateAppearance(compact: geometry.compact, stripHeight: geometry.cutoutHeight, appearance: preferences.appearance, glassEnabled: preferences.islandGlass)
        guard canvas.currentSurface != geometry.size || canvas.isDeparting else { return }
        let margin: CGFloat = geometry.compact ? 0 : 144
        let bottom: CGFloat = geometry.compact ? 0 : 64
        let size = CGSize(width: max(canvas.currentSurface.width, geometry.width) + margin, height: max(canvas.currentSurface.height, geometry.height) + bottom)
        let centerX = notchCenterX(on: screen)
        let frame = NSRect(x: centerX - size.width / 2, y: screen.frame.maxY - size.height + 1 / screen.backingScaleFactor, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        canvas.prepare(target: geometry.canvasGeometry, reserved: size, animated: !preferences.usesReducedMotion, closing: false, appearance: preferences.appearance, glassEnabled: preferences.islandGlass, welcome: welcomeStartedAt.map { Date().timeIntervalSince($0) < 1 } == true) { [weak self] in self?.settlePanel() }
    }

    private func settlePanel() {
        guard let panel, let canvas, let screen = notchScreen, isVisible else { return }
        let size = CGSize(width: geometry.width + (geometry.compact ? 0 : 144), height: geometry.height + (geometry.compact ? 0 : 64))
        panel.setFrame(NSRect(x: notchCenterX(on: screen) - size.width / 2, y: screen.frame.maxY - size.height + 1 / screen.backingScaleFactor, width: size.width, height: size.height), display: true)
        canvas.prepare(target: geometry.canvasGeometry, reserved: size, animated: false, closing: false, appearance: preferences.appearance, glassEnabled: preferences.islandGlass, settled: {})
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
        guard sessionIsActive else { return }
        // A Space transition doesn't change the timer or reopen a dismissed
        // companion. Restore ordering only for surfaces that should be visible.
        screenDidChange()
        if let panel { configureOverlay(panel) }
        if let hoverPanel { configureOverlay(hoverPanel) }
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
        case .island: height = 42
        case .celebration: height = 270
        case .tools: height = 350
        case .clipboard: height = 480
        case .system: height = 440
        case .keepAwake: height = 400
        case .displayPower: height = 420
        case .audio: height = 460
        case .avatars: height = 340
        case .aiLimits: height = min(470, (notchScreen?.visibleFrame.height ?? 700) - 80)
        }
        let width: CGFloat
        switch presentation {
        case .island: width = 240
        case .aiLimits: width = 800
        case .tools, .audio, .clipboard, .system, .displayPower: width = 760
        case .keepAwake: width = 700
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
        guard activation?.isVoiceBusy != true else { hideTask = nil; return }
        let grace = revealGraceDeadline.map { ContinuousClock.now.duration(to: $0) } ?? .zero
        let delay = max(delay, grace)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if !self.pointerInsideInteractiveArea {
                self.collapseAfterPointerExit()
            }
        }
    }
}
