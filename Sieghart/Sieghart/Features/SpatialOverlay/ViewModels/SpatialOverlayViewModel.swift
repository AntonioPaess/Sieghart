import AppKit
import Combine
import SwiftUI

/// Coordinates the full-screen transparent `SpatialCanvasOverlay` (`NSPanel`),
/// vector path animations (`Trim` 0.0 -> 1.0 + glow + `.easeOut` fade),
/// and semantic screen inspection highlights (`AnnotationHighlightView` + `BlueCursorView`).
@MainActor
final class SpatialOverlayViewModel: ObservableObject {
    static let strokeDuration: TimeInterval = 1.05
    @Published private(set) var generatedCanvas: GeneratedCanvas?
    @Published private(set) var activeDrawing: SpatialVectorDrawing?
    @Published private(set) var activeHighlight: ScreenAnnotationHighlight?
    @Published private(set) var strokeProgress: CGFloat = 0.0
    @Published private(set) var overlayOpacity: Double = 0.0
    @Published private(set) var isPresentingOverlay = false
    @Published private(set) var lastStatusMessage = ""
    @Published private(set) var isPinned = false
    var uiLanguage = "pt-BR"
    @Published var guidanceStatus: String?
    var confirmGuidance: (@MainActor () -> Void)?
    var refreshGuidance: (@MainActor () -> Void)?
    var onDismiss: (@MainActor () -> Void)?

    let voiceSynthesizer: any SigVoiceSynthesizing
    let inspector: any ScreenSemanticInspecting
    private let managesWindow: Bool
    private var panel: SpatialCanvasPanel?
    private var controlsPanel: SpatialCanvasPanel?
    private var targetScreenFrame: CGRect?
    private var speechObservation: AnyCancellable?
    private var fadeTask: Task<Void, Never>?

    init(
        voiceSynthesizer: (any SigVoiceSynthesizing)? = nil,
        inspector: (any ScreenSemanticInspecting)? = nil,
        managesWindow: Bool = true
    ) {
        self.voiceSynthesizer = voiceSynthesizer ?? SigVoiceSynthesizer(playsHardwareAudio: managesWindow)
        self.inspector = inspector ?? ScreenSemanticInspector(queriesSystemAX: managesWindow)
        self.managesWindow = managesWindow
        if let voice = self.voiceSynthesizer as? SigVoiceSynthesizer {
            speechObservation = voice.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }

    /// Triggers a spatial vector drawing on screen with animated stroke trim (`0.0 -> 1.0`), glow, and `.easeOut` auto-fade.
    func draw(shape: SpatialVectorShape, prompt: String, holdDuration: TimeInterval = 3.2, speaksAcknowledgement: Bool = true, language: String = "pt-BR") {
        uiLanguage = language; isPinned = false
        targetScreenFrame = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.frame
        fadeTask?.cancel()
        activeHighlight = nil
        generatedCanvas = nil
        let screenSize = targetScreenFrame?.size ?? NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
        let boxSize: CGFloat = 320
        let rect = CGRect(
            x: (screenSize.width - boxSize) * 0.5,
            y: (screenSize.height - boxSize) * 0.44,
            width: boxSize,
            height: boxSize
        )
        let drawing = SpatialVectorDrawing(
            shape: shape,
            prompt: prompt,
            canvasRect: rect,
            holdDuration: holdDuration
        )
        activeDrawing = drawing
        strokeProgress = 0.0
        overlayOpacity = 1.0
        isPresentingOverlay = true
        lastStatusMessage = shape.acknowledgement(language: language)

        ensurePanelVisible()
        if speaksAcknowledgement { voiceSynthesizer.speak(shape.acknowledgement(language: language), language: language) }

        withAnimation(.easeInOut(duration: Self.strokeDuration)) {
            strokeProgress = 1.0
        }

        scheduleAutoFade(after: holdDuration, matchingDrawingID: drawing.id, matchingHighlightID: nil)
    }

    /// Keep the same drawing visible while its spoken explanation is delivered.
    func holdDrawing(id: UUID, for duration: TimeInterval) {
        guard activeDrawing?.id == id else { return }
        scheduleAutoFade(after: duration, matchingDrawingID: id, matchingHighlightID: nil)
    }

    /// Inspects the screen semantically (`AXUIElement` + Vision OCR), renders `AnnotationHighlightView` & `BlueCursorView`,
    /// and speaks a concise explanation using Sig's voice.
    @discardableResult
    func inspectScreen(query: String, selection: ScreenSelection? = nil, holdDuration: TimeInterval = 3.8, speaksReading: Bool = true, language: String = "pt-BR") async -> ScreenSemanticReading {
        fadeTask?.cancel()
        activeDrawing = nil
        generatedCanvas = nil
        let reading = await inspector.inspect(query: query, selection: selection)
        guard !Task.isCancelled else { return reading }
        guard reading.failure == nil else {
            lastStatusMessage = reading.explanation(language: language)
            if speaksReading { voiceSynthesizer.speak(lastStatusMessage, language: language) }
            return reading
        }
        let highlight = ScreenAnnotationHighlight(
            frame: reading.elementFrame,
            cursorPoint: reading.cursorPoint,
            elementRole: reading.elementRole,
            elementTitle: reading.elementTitle,
            recognizedText: reading.ocrText,
            summary: reading.explanation(language: language)
        )
        activeHighlight = highlight
        targetScreenFrame = reading.screenFrame
        uiLanguage = language; isPinned = false
        strokeProgress = 1.0
        overlayOpacity = 1.0
        isPresentingOverlay = true
        lastStatusMessage = reading.explanation(language: language)

        ensurePanelVisible()
        if speaksReading { voiceSynthesizer.speak(reading.explanation(language: language), language: language) }
        scheduleAutoFade(after: holdDuration, matchingDrawingID: nil, matchingHighlightID: highlight.id)
        return reading
    }

    func present(_ document: GeneratedCanvas, language: String = "pt-BR") throws {
        let checked = try document.validated()
        uiLanguage = language; isPinned = false
        targetScreenFrame = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.frame
        fadeTask?.cancel()
        activeDrawing = nil; activeHighlight = nil
        generatedCanvas = checked
        strokeProgress = 0; overlayOpacity = 1; isPresentingOverlay = true
        lastStatusMessage = checked.title
        ensurePanelVisible()
        withAnimation(.easeOut(duration: Self.strokeDuration)) { strokeProgress = 1 }
        scheduleAutoFade(after: 180, matchingDrawingID: nil, matchingHighlightID: nil, matchingDocumentID: checked.id)
    }

    func togglePinned() {
        isPinned.toggle()
        if isPinned { fadeTask?.cancel(); fadeTask = nil }
        else { scheduleAutoFade(after: 30, matchingDrawingID: activeDrawing?.id, matchingHighlightID: activeHighlight?.id, matchingDocumentID: generatedCanvas?.id) }
    }

    func exportContent() {
        guard let document = generatedCanvas else { return }
        if let library = SpatialAssistantCoordinator.activeInstance?.artifacts {
            library.saveCanvas(document)
            if let item = library.items.first(where: { $0.sourceID == "canvas.\(document.id)" }) { library.export(item) }
        }
    }

    func copyContent() {
        guard let text = generatedCanvas?.copyText, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func highlightGuidance(_ region: ScreenTextRegion, screenFrame: CGRect, title: String, language: String) {
        fadeTask?.cancel(); activeDrawing = nil; generatedCanvas = nil
        targetScreenFrame = screenFrame; uiLanguage = language; isPinned = true
        activeHighlight = .init(frame: region.frame.insetBy(dx: -5, dy: -5), cursorPoint: .init(x: region.frame.maxX+14, y: region.frame.midY), elementRole: "Text target", elementTitle: title, recognizedText: region.text, summary: guidanceStatus ?? "")
        strokeProgress = 1; overlayOpacity = 1; isPresentingOverlay = true
        ensurePanelVisible()
    }
    func hideGuidanceHighlight() { activeHighlight = nil; isPresentingOverlay = true; overlayOpacity = 1; ensurePanelVisible() }
    func endGuidance() {
        if guidanceStatus != nil {
            activeHighlight = nil; isPinned = false; isPresentingOverlay = false
            panel?.orderOut(nil); controlsPanel?.orderOut(nil)
        }
        guidanceStatus = nil; confirmGuidance = nil; refreshGuidance = nil
    }

    func holdGeneratedCanvas(id: UUID, for seconds: TimeInterval) {
        guard generatedCanvas?.id == id else { return }
        scheduleAutoFade(after: seconds, matchingDrawingID: nil, matchingHighlightID: nil, matchingDocumentID: id)
    }

    /// Immediately dismisses any active spatial drawing or screen annotation (callable from Dynamic Island close button).
    func dismiss() {
        onDismiss?()
        fadeTask?.cancel()
        fadeTask = nil
        withAnimation(.easeOut(duration: 0.25)) {
            overlayOpacity = 0.0
        }
        activeDrawing = nil
        activeHighlight = nil
        generatedCanvas = nil
        strokeProgress = 0.0
        isPresentingOverlay = false
        panel?.orderOut(nil)
        controlsPanel?.orderOut(nil)
        isPinned = false
    }

    private func scheduleAutoFade(
        after holdDuration: TimeInterval,
        matchingDrawingID: UUID?,
        matchingHighlightID: UUID?,
        matchingDocumentID: UUID? = nil
    ) {
        guard !isPinned else { return }
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(max(0.2, holdDuration) * 1000)))
            guard !Task.isCancelled, let self else { return }
            if let matchingDrawingID, self.activeDrawing?.id != matchingDrawingID { return }
            if let matchingHighlightID, self.activeHighlight?.id != matchingHighlightID { return }
            if let matchingDocumentID, self.generatedCanvas?.id != matchingDocumentID { return }
            withAnimation(.easeOut(duration: 0.45)) {
                self.overlayOpacity = 0.0
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            if let matchingDrawingID, self.activeDrawing?.id != matchingDrawingID { return }
            if let matchingHighlightID, self.activeHighlight?.id != matchingHighlightID { return }
            if let matchingDocumentID, self.generatedCanvas?.id != matchingDocumentID { return }
            self.activeDrawing = nil
            self.activeHighlight = nil
            self.generatedCanvas = nil
            self.strokeProgress = 0.0
            self.isPresentingOverlay = false
            self.panel?.orderOut(nil)
            self.controlsPanel?.orderOut(nil)
        }
    }

    private func ensurePanelVisible() {
        guard managesWindow else { return }
        let screenFrame = targetScreenFrame ?? NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        if panel == nil {
            let newPanel = SpatialCanvasPanel(screenFrame: screenFrame)
            let hosting = NSHostingView(rootView: SpatialCanvasOverlay(viewModel: self))
            hosting.frame = NSRect(origin: .zero, size: screenFrame.size)
            newPanel.contentView = hosting
            panel = newPanel
        }
        panel?.setFrame(screenFrame, display: true)
        panel?.ignoresMouseEvents = true
        panel?.orderFrontRegardless()
        if controlsPanel == nil {
            let controls = SpatialCanvasPanel(screenFrame: CGRect(x: 0, y: 0, width: 300, height: 54))
            controls.contentView = NSHostingView(rootView: SpatialCanvasControls(model: self))
            controls.ignoresMouseEvents = false
            controls.level = .statusBar
            controlsPanel = controls
        }
        let size = guidanceStatus == nil ? CGSize(width: 300, height: 54) : CGSize(width: 560, height: 104)
        controlsPanel?.setFrame(CGRect(x: screenFrame.midX - size.width/2, y: screenFrame.minY + 28, width: size.width, height: size.height), display: true)
        controlsPanel?.orderFrontRegardless()
    }
}
