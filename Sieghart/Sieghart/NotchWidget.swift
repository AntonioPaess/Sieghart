import AppKit
import Combine
import SwiftUI

enum NotchWidgetMode: Equatable {
    case character
    case calendar
}

struct NotchGeometry: Equatable {
    let width: CGFloat
    let neckWidth: CGFloat
    let neckHeight: CGFloat

    static let bodyHeight: CGFloat = 166
    static let cornerRadius: CGFloat = 28

    var shoulderHeight: CGFloat { neckHeight > 0 ? 24 : 0 }
    var contentTop: CGFloat { neckHeight + shoulderHeight }
    var height: CGFloat { contentTop + Self.bodyHeight }
    var size: CGSize { CGSize(width: width, height: height) }

    static let fallback = NotchGeometry(width: 300, neckWidth: 300, neckHeight: 0)

    init(width: CGFloat, neckWidth: CGFloat, neckHeight: CGFloat) {
        self.width = width
        self.neckWidth = neckWidth
        self.neckHeight = neckHeight
    }

    init(screen: NSScreen) {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else {
            self = .fallback
            return
        }

        let cutoutWidth = right.minX - left.maxX
        let panelWidth = min(max(300, cutoutWidth + 96), screen.frame.width - 24)
        width = panelWidth
        neckWidth = min(cutoutWidth + 2, panelWidth - 32)
        neckHeight = max(screen.safeAreaInsets.top, min(left.height, right.height))
    }
}

@MainActor
final class NotchWidgetController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var mode: NotchWidgetMode = .character
    @Published private(set) var geometry: NotchGeometry = .fallback

    private let assistant: AssistantViewModel
    private let calendar: CalendarViewModel
    private var panel: NSPanel?
    private var hoverPanel: HoverZonePanel?
    private var isPointerInsidePanel = false
    private var isImpactRevealed = false
    private var hideTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var pomodoroObservation: AnyCancellable?
    private var screenChangeObserver: AnyCancellable?
    private let overlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.mainMenu.rawValue + 3
    )

    init(assistant: AssistantViewModel, calendar: CalendarViewModel) {
        self.assistant = assistant
        self.calendar = calendar
        if let screen = Self.selectedScreen() { geometry = NotchGeometry(screen: screen) }
        configureHoverZone()
        screenChangeObserver = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screenDidChange() }
        pomodoroObservation = assistant.$pomodoroPhase
            .sink { [weak self] phase in
                self?.handlePomodoroPhaseChange(phase)
            }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        mode = .character
        reveal(stickyUntilImpact: assistant.pomodoroPhase == .focusing)
    }

    func showCalendar() {
        mode = .calendar
        // A sensor gesture may reveal Calendar, but only an explicit button
        // press may initiate the system permission request.
        calendar.prepare()
        reveal(stickyUntilImpact: true)
    }

    func handleImpact() {
        if isVisible {
            hide()
        } else {
            reveal(stickyUntilImpact: true)
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
        mode = .character
        guard let panel, panel.isVisible else { return }
        collapseTask?.cancel()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            return
        }

        let collapsed = collapsedFrame(for: panel.frame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(collapsed, display: true)
            panel.animator().alphaValue = 0
        }
        collapseTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !self.isVisible else { return }
            panel?.orderOut(nil)
        }
    }

    private func handlePomodoroPhaseChange(_ phase: PomodoroPhase) {
        switch phase {
        case .focusing:
            mode = .character
            reveal(stickyUntilImpact: true)
        case .idle, .paused, .completed:
            guard isVisible, isImpactRevealed else { return }
            isImpactRevealed = false
            if !isPointerInsidePanel {
                scheduleHide()
            }
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
        let expanded = panel.frame
        let wasVisible = panel.isVisible
        isVisible = true
        if !wasVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(collapsedFrame(for: expanded), display: false)
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(expanded, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func collapsedFrame(for expanded: NSRect) -> NSRect {
        let height = max(geometry.neckHeight, 1)
        return NSRect(x: expanded.minX, y: expanded.maxY - height, width: expanded.width, height: height)
    }

    private func makePanelIfNeeded() {
        guard panel == nil else { return }

        let widgetPanel = NSPanel(
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
        widgetPanel.contentView = NSHostingView(
            rootView: NotchWidgetView()
                .environmentObject(self)
                .environmentObject(assistant)
                .environmentObject(calendar)
        )

        panel = widgetPanel
    }

    private func positionPanel() {
        guard let panel else { return }
        guard let screen = notchScreen else { return }

        let size = geometry.size
        let centerX = notchCenterX(on: screen)
        panel.setFrame(
            NSRect(
                x: centerX - (size.width / 2),
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    private func configureHoverZone() {
        let hover = HoverZonePanel(
            contentRect: NSRect(x: 0, y: 0, width: geometry.neckWidth + 12, height: max(geometry.neckHeight, 30)),
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
                guard let self else { return }
                self.reveal(stickyUntilImpact: self.assistant.pomodoroPhase == .focusing)
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
        hover.orderFrontRegardless()
    }

    private func positionHoverPanel() {
        guard let hoverPanel else { return }
        guard let screen = notchScreen else { return }

        let size = CGSize(width: geometry.neckWidth + 12, height: max(geometry.neckHeight, 30))
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
        if let screen = notchScreen { geometry = NotchGeometry(screen: screen) }
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
    @EnvironmentObject private var calendar: CalendarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let blinkPhase = time.truncatingRemainder(dividingBy: 5.0)
            let isBlinking = blinkPhase < 0.16
            let breathing = reduceMotion ? 0 : sin(time * 1.4) * 0.012
            let focusMotion = reduceMotion ? 0 : sin(time * 2.2)
            let isFocusing = assistant.pomodoroPhase == .focusing
            let showsPomodoro = isFocusing || assistant.pomodoroPhase == .paused

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: notch.geometry.contentTop)
                    .allowsHitTesting(false)

                ZStack {
                    if notch.mode == .calendar {
                        CalendarWidgetView(calendar: calendar, time: time, width: notch.geometry.width)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                        )
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                notch.focusMainWindow()
                            } label: {
                                NotchFaceView(
                                    isFocusing: isFocusing,
                                    isBlinking: isBlinking,
                                    focusMotion: focusMotion
                                )
                                .scaleEffect(1 + breathing)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open Sieghart")

                            if showsPomodoro {
                                VStack(spacing: 7) {
                                    PomodoroOrbView(
                                        timeLabel: assistant.pomodoroTimeLabel,
                                        progress: assistant.pomodoroProgress,
                                        isPaused: assistant.pomodoroPhase == .paused,
                                        pulse: reduceMotion ? 0 : sin(time * 2.0) * 0.018
                                    )

                                    Button("Finish") {
                                        assistant.finishPomodoroFromWidget()
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.white.opacity(0.86))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.white.opacity(0.12), in: Capsule())
                                    .accessibilityLabel("Finish Pomodoro")
                                }
                            }
                        }
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                        )
                    }
                }
                .frame(width: notch.geometry.width, height: NotchGeometry.bodyHeight)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: notch.mode)
            }
        }
        .frame(width: notch.geometry.width, height: notch.geometry.height)
        .background(.black, in: NotchPanelShape(geometry: notch.geometry))
        .clipShape(NotchPanelShape(geometry: notch.geometry))
        .contentShape(NotchPanelShape(geometry: notch.geometry))
        .onHover { notch.setPointerInsidePanel($0) }
    }
}

private struct NotchPanelShape: Shape {
    let geometry: NotchGeometry

    func path(in rect: CGRect) -> Path {
        let radius = min(NotchGeometry.cornerRadius, min(rect.width, rect.height) / 2)
        let leftNeck = rect.midX - geometry.neckWidth / 2
        let rightNeck = rect.midX + geometry.neckWidth / 2
        let shoulderBottom = rect.minY + geometry.contentTop
        let neckBottom = rect.minY + geometry.neckHeight
        var path = Path()
        path.move(to: CGPoint(x: leftNeck, y: rect.minY))
        path.addLine(to: CGPoint(x: rightNeck, y: rect.minY))
        if geometry.shoulderHeight > 0 {
            path.addLine(to: CGPoint(x: rightNeck, y: neckBottom))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: shoulderBottom),
                control1: CGPoint(x: rightNeck, y: shoulderBottom),
                control2: CGPoint(x: rect.maxX, y: neckBottom)
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        if geometry.shoulderHeight > 0 {
            path.addLine(to: CGPoint(x: rect.minX, y: shoulderBottom))
            path.addCurve(
                to: CGPoint(x: leftNeck, y: neckBottom),
                control1: CGPoint(x: rect.minX, y: neckBottom),
                control2: CGPoint(x: leftNeck, y: shoulderBottom)
            )
        }
        path.closeSubpath()
        return path
    }
}

private struct PomodoroOrbView: View {
    let timeLabel: String
    let progress: Double
    let isPaused: Bool
    let pulse: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.28),
                            (isPaused ? Color.gray : Color.purple).opacity(0.72),
                            .black.opacity(0.88)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 62
                    )
                )

            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isPaused ? .white.opacity(0.62) : .mint,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(3)

            Text(timeLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 78, height: 78)
        .scaleEffect(1 + pulse)
        .shadow(color: (isPaused ? Color.gray : Color.purple).opacity(0.45), radius: 12)
        .accessibilityLabel("Pomodoro \(timeLabel) remaining")
    }
}

private struct CalendarWidgetView: View {
    @EnvironmentObject private var notch: NotchWidgetController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let calendar: CalendarViewModel
    let time: TimeInterval
    let width: CGFloat

    var body: some View {
        let pulse = reduceMotion ? 1 : 1 + sin(time * 1.6) * 0.025

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    notch.show()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to character")
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .scaleEffect(pulse)
                    .foregroundStyle(.cyan)
                Text("Calendar")
                    .font(.headline)
                Spacer()
                Button {
                    calendar.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(calendar.accessState != .fullAccess || calendar.isLoading)
                .accessibilityLabel("Refresh calendar")
                if calendar.nextEvent?.hasLink == true {
                    Button {
                        calendar.openNextEventLink()
                    } label: {
                        Label("Join", systemImage: "link")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)
                    .accessibilityLabel("Open next event meeting link")
                }
            }

            if calendar.upcomingEvents.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(calendar.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if !calendar.isLoading {
                        Button(calendar.accessButtonLabel) {
                            calendar.requestAccessAndRefresh()
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.cyan.opacity(0.13), in: Capsule())
                        .disabled(calendar.isRequestingAccess)
                    }
                }
            } else {
                ForEach(Array(calendar.upcomingEvents.prefix(3))) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(event.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.cyan)
                            .frame(width: 54, alignment: .leading)
                        Text(event.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                }
                Text(calendar.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 22)
        .frame(width: width, height: NotchGeometry.bodyHeight, alignment: .leading)
    }
}

private struct NotchFaceView: View {
    let isFocusing: Bool
    let isBlinking: Bool
    let focusMotion: Double

    var body: some View {
        ZStack {
            if isFocusing {
                HStack(spacing: 84) {
                    FocusArm(isLeft: true, motion: focusMotion)
                    FocusArm(isLeft: false, motion: focusMotion)
                }
                .offset(y: 20)
            }

            VStack(spacing: 12) {
                HStack(spacing: 34) {
                    FaceEye(isBlinking: isBlinking)
                    FaceEye(isBlinking: isBlinking)
                }

                Smile(depth: isFocusing ? 0.72 : 0.62)
                    .stroke(.white.opacity(0.90), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 64, height: 30)
            }
        }
        .frame(width: 160, height: 130)
        .accessibilityHidden(true)
    }
}

private struct FocusArm: View {
    let isLeft: Bool
    let motion: Double

    var body: some View {
        VStack(spacing: 2) {
            Capsule()
                .fill(.white.opacity(0.82))
                .frame(width: 8, height: 30)
            Circle()
                .fill(.white)
                .frame(width: 15, height: 15)
        }
        .rotationEffect(.degrees((isLeft ? -1 : 1) * (18 + motion * 4)))
        .offset(y: -motion * 4)
    }
}

private struct FaceEye: View {
    let isBlinking: Bool

    var body: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(.white.opacity(0.82))
                .frame(width: 18, height: 4)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white)
                .frame(width: 24, height: isBlinking ? 4 : 38)
        }
    }
}

private struct Smile: Shape {
    let depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX + 4, y: rect.midY - 2)
        let end = CGPoint(x: rect.maxX - 4, y: rect.midY - 2)
        let control = CGPoint(x: rect.midX, y: rect.minY + rect.height * depth)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}
