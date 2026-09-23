import AppKit
import Combine
import SwiftUI

enum NotchWidgetMode: Equatable {
    case character
    case calendar
}

private enum NotchLayout {
    static let width: CGFloat = 300
    static let height: CGFloat = 196
    static let cornerRadius: CGFloat = 28
}

@MainActor
final class NotchWidgetController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var mode: NotchWidgetMode = .character

    private let assistant: AssistantViewModel
    private let calendar: CalendarViewModel
    private var panel: NSPanel?
    private var hoverPanel: HoverZonePanel?
    private var isPointerInsidePanel = false
    private var isImpactRevealed = false
    private var hideTask: Task<Void, Never>?
    private var pomodoroObservation: AnyCancellable?

    private let widgetSize = CGSize(
        width: NotchLayout.width,
        height: NotchLayout.height
    )
    private let overlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.mainMenu.rawValue + 3
    )

    init(assistant: AssistantViewModel, calendar: CalendarViewModel) {
        self.assistant = assistant
        self.calendar = calendar
        configureHoverZone()
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
        calendar.requestAccessAndRefresh()
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
        panel?.orderOut(nil)
        isVisible = false
        isImpactRevealed = false
        mode = .character
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
        isImpactRevealed = stickyUntilImpact
        makePanelIfNeeded()
        positionPanel()

        guard let panel else { return }

        // The panel is already positioned at the top edge of the display. A
        // short opacity animation combined with the SwiftUI scale animation
        // makes it grow out of the notch instead of appearing as a separate
        // window below it.
        let shouldAnimate = !panel.isVisible
        if shouldAnimate {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
        isVisible = true
    }

    private func makePanelIfNeeded() {
        guard panel == nil else { return }

        let widgetPanel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: widgetSize.width,
                height: widgetSize.height
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

        let size = widgetSize
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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 44),
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

        let size = hoverPanel.frame.size
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

    private var notchScreen: NSScreen? {
        NSScreen.screens.first(where: { screen in
            screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }) ?? NSScreen.main ?? NSScreen.screens.first
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let blinkPhase = time.truncatingRemainder(dividingBy: 5.0)
            let isBlinking = blinkPhase < 0.16
            let breathing = sin(time * 1.4) * 0.012
            let focusMotion = sin(time * 2.2)
            let isFocusing = assistant.pomodoroPhase == .focusing
            let showsPomodoro = isFocusing || assistant.pomodoroPhase == .paused

            ZStack {
                if notch.mode == .calendar {
                    CalendarWidgetView(calendar: calendar, time: time)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            )
                        )
                } else {
                    HStack(spacing: 12) {
                        NotchFaceView(
                            isFocusing: isFocusing,
                            isBlinking: isBlinking,
                            focusMotion: focusMotion
                        )
                        .scaleEffect(1 + breathing)

                        if showsPomodoro {
                            VStack(spacing: 7) {
                                PomodoroOrbView(
                                    timeLabel: assistant.pomodoroTimeLabel,
                                    progress: assistant.pomodoroProgress,
                                    isPaused: assistant.pomodoroPhase == .paused,
                                    pulse: sin(time * 2.0) * 0.018
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
            .frame(width: NotchLayout.width, height: NotchLayout.height)
            .animation(.easeInOut(duration: 0.35), value: notch.mode)
        }
        .frame(width: NotchLayout.width, height: NotchLayout.height)
        .background(.black, in: NotchPanelShape(cornerRadius: NotchLayout.cornerRadius))
        .clipShape(NotchPanelShape(cornerRadius: NotchLayout.cornerRadius))
        .contentShape(NotchPanelShape(cornerRadius: NotchLayout.cornerRadius))
        .scaleEffect(notch.isVisible ? 1 : 0.94, anchor: .top)
        .opacity(notch.isVisible ? 1 : 0)
        .animation(
            .spring(response: 0.34, dampingFraction: 0.86),
            value: notch.isVisible
        )
        .onHover { notch.setPointerInsidePanel($0) }
        .onTapGesture {
            notch.focusMainWindow()
        }
        .accessibilityLabel("Sieghart character and Pomodoro status")
    }
}

private struct NotchPanelShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
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
    let calendar: CalendarViewModel
    let time: TimeInterval

    var body: some View {
        let pulse = 1 + sin(time * 1.6) * 0.025

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .scaleEffect(pulse)
                    .foregroundStyle(.cyan)
                Text("Calendar")
                    .font(.headline)
                Spacer()
                if calendar.nextEvent?.hasLink == true {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                }
            }

            if calendar.upcomingEvents.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(calendar.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if calendar.accessState != .fullAccess {
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
            }
        }
        .padding(.horizontal, 22)
        .frame(
            width: NotchLayout.width,
            height: NotchLayout.height,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(calendar.nextEvent.map { "Calendar, \($0.title), \($0.relativeStart)" } ?? "Calendar, \(calendar.status)")
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
