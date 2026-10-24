import AppKit
import Combine
import SwiftUI

struct ScreenSelection: Equatable, Sendable {
    let screenFrame: CGRect
    /// Top-left coordinates in points, local to screenFrame.
    let bounds: CGRect
    let trace: [CGPoint]
    var isValid: Bool {
        [screenFrame.minX, screenFrame.minY, screenFrame.width, screenFrame.height, bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite)
            && bounds.width >= 12 && bounds.height >= 12
            && CGRect(origin: .zero, size: screenFrame.size).contains(bounds)
    }
    func crop(_ image: CGImage) -> CGImage? {
        guard isValid, screenFrame.width > 0, screenFrame.height > 0 else { return nil }
        let sx = CGFloat(image.width) / screenFrame.width, sy = CGFloat(image.height) / screenFrame.height
        let rect = CGRect(x: bounds.minX*sx, y: bounds.minY*sy, width: bounds.width*sx, height: bounds.height*sy).integral
        return image.cropping(to: rect)
    }
}

/// One visible, cancellable input session owns the pointer and region. It never
/// captures pixels merely because the pointer moves; capture follows a request.
@MainActor final class ScreenInteractionController: ObservableObject {
    enum Phase: Equatable { case idle, listening, thinking, speaking }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var trace: [CGPoint] = []
    @Published private(set) var selectedBounds: CGRect?
    @Published private(set) var screenFrame = CGRect.zero
    @Published var language = "pt-BR"
    @Published private(set) var weatherReceipt: VoiceWeatherObservation?
    var onOpenWeather: (@MainActor (VoiceWeatherObservation) -> Void)?
    var onWeatherFinished: (@MainActor () -> Void)?
    private(set) var pendingSelection: ScreenSelection?
    var onCancel: (@MainActor () -> Void)?
    private let managesWindows: Bool
    private var pointerPanel: SpatialCanvasPanel?
    private var selectionPanel: SpatialCanvasPanel?
    private var tracking: Task<Void, Never>?
    private var escapeMonitor: Any?
    private var dragging = false
    private var responseEndTask: Task<Void, Never>?

    init(managesWindows: Bool) { self.managesWindows = managesWindows }

    func beginListening(language: String) {
        cancel()
        self.language = language
        phase = .listening
        guard managesWindows else { return }
        updatePointer()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.onCancel?() }
            return nil
        }
        tracking = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updatePointer()
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
            }
        }
    }

    func drag(to point: CGPoint, in frame: CGRect) {
        guard phase == .listening else { return }
        if !dragging { trace = []; selectedBounds = nil; screenFrame = frame; dragging = true }
        let clamped = CGPoint(x: min(frame.width, max(0, point.x)), y: min(frame.height, max(0, point.y)))
        if trace.count < 600, trace.last.map({ hypot($0.x-clamped.x, $0.y-clamped.y) > 2 }) ?? true { trace.append(clamped) }
        updateBounds()
    }

    func finishDrag() { dragging = false; commitSelection() }

    func finishListening() {
        if dragging { finishDrag() }
        selectionPanel?.orderOut(nil)
        removeEscapeMonitor()
        if phase == .listening { phase = .thinking }
    }

    func takeSelection() -> ScreenSelection? {
        let result = pendingSelection
        pendingSelection = nil
        return result
    }

    func setPhase(_ phase: Phase) {
        guard self.phase != phase else { return }
        responseEndTask?.cancel(); responseEndTask = nil
        self.phase = phase
        if phase == .idle { hideWindows(); return }
        if phase != .listening { selectionPanel?.orderOut(nil); removeEscapeMonitor() }
        if managesWindows, tracking == nil {
            tracking = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.updatePointer()
                    do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                }
            }
        }
    }

    func setWeatherReceipt(_ observation: VoiceWeatherObservation?) {
        weatherReceipt = observation
        if observation == nil, phase == .idle { hideWindows() }
    }
    func openWeather() {
        guard let observation = weatherReceipt else { return }
        responseEndTask?.cancel(); responseEndTask = nil
        weatherReceipt = nil; hideWindows(); onOpenWeather?(observation)
    }
    func dismissWeatherReceipt() { responseEndTask?.cancel(); weatherReceipt = nil; if phase == .idle { hideWindows() } }
    func finishResponse(receiptDuration: Duration = .seconds(8)) {
        guard weatherReceipt != nil else { setPhase(.idle); return }
        phase = .idle; tracking?.cancel(); tracking = nil
        selectionPanel?.orderOut(nil); removeEscapeMonitor()
        if managesWindows { updatePointer(); pointerPanel?.ignoresMouseEvents = false }
        onWeatherFinished?()
        responseEndTask?.cancel()
        responseEndTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: receiptDuration) } catch { return }
            guard let self, self.phase == .idle else { return }
            self.weatherReceipt = nil; self.hideWindows()
        }
    }

    func cancel() {
        responseEndTask?.cancel(); responseEndTask = nil
        phase = .idle; trace = []; selectedBounds = nil; pendingSelection = nil; dragging = false
        weatherReceipt = nil
        hideWindows()
    }

    private func updateBounds() {
        guard let first = trace.first else { return }
        let minX = trace.map(\.x).min() ?? first.x, maxX = trace.map(\.x).max() ?? first.x
        let minY = trace.map(\.y).min() ?? first.y, maxY = trace.map(\.y).max() ?? first.y
        selectedBounds = CGRect(x: minX, y: minY, width: maxX-minX, height: maxY-minY)
    }

    private func commitSelection() {
        guard let selectedBounds else { return }
        let selection = ScreenSelection(screenFrame: screenFrame, bounds: selectedBounds, trace: trace)
        pendingSelection = selection.isValid ? selection : nil
    }

    private func hideWindows() {
        tracking?.cancel(); tracking = nil
        pointerPanel?.orderOut(nil); selectionPanel?.orderOut(nil)
        removeEscapeMonitor()
    }
    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
    }
    private func updatePointer() {
        guard phase != .idle || weatherReceipt != nil else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        if pointerPanel == nil {
            let panel = SpatialCanvasPanel(screenFrame: .init(x: 0, y: 0, width: 184, height: 58))
            panel.contentView = NSHostingView(rootView: ListeningPointerView(model: self))
            panel.level = .popUpMenu
            pointerPanel = panel
        }
        let frame = screen.frame
        let width: CGFloat = weatherReceipt == nil ? 184 : 220, height: CGFloat = weatherReceipt == nil ? 58 : 84
        pointerPanel?.ignoresMouseEvents = phase != .idle
        pointerPanel?.setFrame(CGRect(x: min(frame.maxX-width-4, max(frame.minX+4, mouse.x+18)),
            y: min(frame.maxY-height-4, max(frame.minY+4, mouse.y-height-6)), width: width, height: height), display: true)
        pointerPanel?.orderFrontRegardless()
        if phase == .listening {
            if selectionPanel == nil {
                let panel = SpatialCanvasPanel(screenFrame: frame)
                panel.contentView = NSHostingView(rootView: ListeningSelectionView(model: self))
                panel.ignoresMouseEvents = false
                panel.level = .statusBar
                selectionPanel = panel
            }
            if !dragging, screenFrame != frame {
                screenFrame = frame; trace = []; selectedBounds = nil
                selectionPanel?.setFrame(frame, display: true)
            }
            selectionPanel?.orderFrontRegardless()
        }
    }
}

private struct ListeningPointerView: View {
    @ObservedObject var model: ScreenInteractionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var title: String {
        let en = model.language.hasPrefix("en")
        switch model.phase {
        case .listening: return en ? "Listening" : "Escutando"
        case .thinking: return en ? "Thinking" : "Pensando"
        case .speaking: return en ? "Speaking" : "Falando"
        case .idle: return "Sieg"
        }
    }
    var body: some View {
        if let weather = model.weatherReceipt {
            Button { model.openWeather() } label: {
                HStack(spacing: 8) {
                    CompanionWeatherCharacter(mood: .resolve(weather), animates: !reduceMotion).frame(width: 65, height: 66)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(weather.temperature.rounded()))°").font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(weather.location.components(separatedBy: ",").first ?? weather.location).font(.system(size: 10)).lineLimit(1)
                    }
                    Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.secondary)
                }.padding(.horizontal, 10).padding(.vertical, 4).frame(width: 220, height: 84)
                    .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.13)))
            }.buttonStyle(.plain).foregroundStyle(.white)
                .onHover { inside in if inside && model.phase == .idle { model.openWeather() } }
        } else {
        HStack(spacing: 6) {
            CompanionCharacter(size: 38, avatar: .sig, animates: !reduceMotion, listening: model.phase == .listening, voicePhase: model.phase == .thinking ? .thinking : model.phase == .listening ? .listening : .inactive)
                .frame(width: 42, height: 40)
            Image(systemName: model.phase == .thinking ? "sparkle" : "waveform")
                .symbolEffect(.variableColor, options: .repeating, isActive: !reduceMotion && model.phase != .idle)
                .foregroundStyle(Color(red: 0.76, green: 0.69, blue: 1))
            Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).fixedSize()
        }.foregroundStyle(.white).padding(10).background(.black.opacity(0.86), in: Capsule())
            .overlay(Capsule().stroke(.purple.opacity(0.65), lineWidth: 1))
            .accessibilityLabel(title)
        }
    }
}

private struct ListeningSelectionView: View {
    @ObservedObject var model: ScreenInteractionController
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001).contentShape(Rectangle())
                if let bounds = model.selectedBounds {
                    RoundedRectangle(cornerRadius: 8).fill(.purple.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.purple.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6,4])))
                        .frame(width: bounds.width, height: bounds.height).position(x: bounds.midX, y: bounds.midY)
                }
                if model.trace.count > 2 {
                    Path { p in
                        p.addLines(model.trace)
                    }.stroke(.cyan.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                Text(model.language.hasPrefix("en") ? "Drag around a region · Release the shortcut to send · Esc to cancel" : "Marque uma região · Solte o atalho para enviar · Esc para cancelar")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10).background(.black.opacity(0.84), in: Capsule())
                    .position(x: proxy.size.width/2, y: proxy.size.height-34)
            }.gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if model.trace.isEmpty { model.drag(to: value.startLocation, in: model.screenFrame) }
                model.drag(to: value.location, in: model.screenFrame)
            }.onEnded { _ in model.finishDrag() })
        }
    }
}
