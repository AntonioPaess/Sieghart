import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Vision
import ScreenCaptureKit

/// Semantic reading result combining Accessibility (`AXUIElement`) metadata with Apple Vision OCR (`VNRecognizeTextRequest`).
struct ScreenSemanticReading: Equatable, Sendable {
    let elementRole: String
    let elementTitle: String
    let elementValue: String
    let ocrText: String
    let elementFrame: CGRect
    let cursorPoint: CGPoint
    let spokenExplanation: String
    var failure: ScreenInspectionFailure? = nil
    var capturedImage: CapturedScreenImage? = nil
    var screenFrame: CGRect? = nil
    var textRegions: [ScreenTextRegion] = []
    var selectedText = ""

    var readableText: String {
        if !selectedText.isEmpty { return selectedText }
        if ["AXTextArea", "AXTextField"].contains(elementRole), !elementValue.isEmpty { return elementValue }
        return ocrText.isEmpty ? elementValue : ocrText
    }

    func explanation(language: String) -> String {
        let en = language.hasPrefix("en")
        if let failure { return failure.message(english: en) }
        let text = readableText
        guard !text.isEmpty else { return en ? "I couldn't find readable text on this screen." : "Não encontrei texto legível nesta tela." }
        return en ? "On your screen: \(text)" : "Na sua tela está escrito: \(text)"
    }

    var combinedText: String {
        let parts = [elementTitle, elementValue, ocrText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var unique: [String] = []
        for part in parts where !unique.contains(part) {
            unique.append(part)
        }
        return unique.joined(separator: " · ")
    }
}

@MainActor
protocol ScreenSemanticInspecting: AnyObject {
    func inspectAtCursor(query: String) async -> ScreenSemanticReading
    func inspect(query: String, selection: ScreenSelection?) async -> ScreenSemanticReading
    func recognizeText(in cgImage: CGImage) throws -> String
}

extension ScreenSemanticInspecting {
    func inspect(query: String, selection: ScreenSelection?) async -> ScreenSemanticReading { await inspectAtCursor(query: query) }
}

struct ScreenTextRegion: Equatable, Sendable {
    let text: String
    let frame: CGRect
}

/// Hybrid screen semantic inspector (`AXUIElementCopyElementAtPosition` + `VNRecognizeTextRequest` local OCR).
@MainActor
final class ScreenSemanticInspector: ScreenSemanticInspecting {
    typealias Capture = @MainActor (NSScreen?) async throws -> CGImage
    private let queriesSystemAX: Bool
    private let capture: Capture?

    init(queriesSystemAX: Bool = true, capture: Capture? = nil) {
        self.queriesSystemAX = queriesSystemAX
        self.capture = capture ?? (queriesSystemAX ? Self.captureDisplay : nil)
    }

    /// Parses whether a spoken or typed request asks Sig to read or explain what is on the screen.
    nonisolated static func isScreenInspectionIntent(_ transcript: String) -> Bool {
        let normalized = transcript
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns = [
            "o que tem escrito",
            "o que esta escrito",
            "leia a minha tela",
            "leia minha tela",
            "ler minha tela",
            "explique o que e isso",
            "explica o que e isso",
            "o que e isso aqui",
            "what is written on my screen",
            "read my screen",
            "explain what is on my screen",
            "what is under my cursor",
            "traduz minha tela", "traduza minha tela", "traduz a minha tela", "traduza a minha tela",
            "traduz o texto", "traduza o texto", "translate my screen", "translate the text on",
            "consegue ver minha tela", "consegue ver a minha tela", "voce ve minha tela", "can you see my screen",
            "veja minha tela", "veja a minha tela", "vendo na minha tela", "na minha tela", "na tela agora", "nessa tela", "nesta tela", "on my screen", "look at my screen",
            "le esse texto", "leia esse texto", "read this text",
            "explica isso", "explique isso", "traduz isso", "traduza isso", "resuma isso", "resume isso",
            "explain this", "translate this", "summarize this", "selected area", "regiao selecionada",
            "me guie", "me guia", "passo a passo na tela", "guide me", "walk me through"
        ]
        return patterns.contains { normalized.contains($0) }
    }

    func inspectAtCursor(query: String) async -> ScreenSemanticReading {
        await inspect(query: query, selection: nil)
    }

    func inspect(query: String, selection: ScreenSelection?) async -> ScreenSemanticReading {
        let mouseAppKit = NSEvent.mouseLocation
        let selectedScreen = selection.flatMap { chosen in NSScreen.screens.first { $0.frame == chosen.screenFrame } }
        if let selection, !selection.isValid || selectedScreen == nil {
            return ScreenSemanticReading(elementRole: "Selected region", elementTitle: "", elementValue: "", ocrText: "", elementFrame: selection.bounds,
                cursorPoint: .zero, spokenExplanation: "", failure: .unavailable, screenFrame: selection.screenFrame)
        }
        let screen = selectedScreen ?? NSScreen.screens.first { $0.frame.contains(mouseAppKit) } ?? NSScreen.main
        let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selection = selection.flatMap { $0.isValid && $0.screenFrame == screenFrame ? $0 : nil }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
        // Convert AppKit bottom-left coordinates to top-left screen coordinates for AXUIElement & SwiftUI overlay.
        let cursorTopLeft = CGPoint(
            x: max(20, min(screenFrame.width - 20, mouseAppKit.x - screenFrame.minX)),
            y: max(40, min(screenFrame.height - 40, screenFrame.maxY - mouseAppKit.y))
        )

        var role = "AXWindow"
        var title = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Janela Ativa"
        var value = ""
        var selectedText = ""
        var frame = CGRect(
            x: max(40, cursorTopLeft.x - 180),
            y: max(60, cursorTopLeft.y - 70),
            width: 360,
            height: 140
        )

        // A selected region is its own context. The pointer may already be
        // outside it when recognition finishes; do not read that other element.
        if selection == nil && queriesSystemAX && AXIsProcessTrusted() {
            let systemWide = AXUIElementCreateSystemWide()
            var elementRef: AXUIElement?
            let status = AXUIElementCopyElementAtPosition(
                systemWide,
                Float(mouseAppKit.x),
                Float(desktopTop - mouseAppKit.y),
                &elementRef
            )
            if status == .success, let element = elementRef {
                if let axRole = Self.stringAttribute(kAXRoleAttribute as CFString, of: element), !axRole.isEmpty {
                    role = axRole
                }
                if let axTitle = Self.stringAttribute(kAXTitleAttribute as CFString, of: element)
                    ?? Self.stringAttribute(kAXDescriptionAttribute as CFString, of: element),
                   !axTitle.isEmpty {
                    title = axTitle
                }
                if let axValue = Self.stringAttribute(kAXValueAttribute as CFString, of: element), !axValue.isEmpty {
                    value = String(axValue.prefix(12000))
                }
                selectedText = String((Self.stringAttribute(kAXSelectedTextAttribute as CFString, of: element) ?? "").prefix(12000))
                if let axRect = Self.frameAttribute(of: element), axRect.width > 8, axRect.height > 8 {
                    frame = axRect.offsetBy(dx: -screenFrame.minX, dy: -(desktopTop - screenFrame.maxY))
                }
            }
        }

        if selection == nil, queriesSystemAX, AXIsProcessTrusted(), selectedText.isEmpty,
           let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
               let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
                let focused = focusedRef as! AXUIElement
                let focusedRole = Self.stringAttribute(kAXRoleAttribute as CFString, of: focused) ?? ""
                if ["AXTextArea", "AXTextField"].contains(focusedRole) {
                    let selectionText = Self.stringAttribute(kAXSelectedTextAttribute as CFString, of: focused) ?? ""
                    let source = Self.stringAttribute(kAXValueAttribute as CFString, of: focused) ?? ""
                    if !selectionText.isEmpty || (!source.isEmpty && ["classe", "class", "codigo", "code", "selecionado", "selected"].contains(where: { query.localizedCaseInsensitiveContains($0) })) {
                        role = focusedRole; value = String(source.prefix(12000)); selectedText = String(selectionText.prefix(12000))
                        if let focusedFrame = Self.frameAttribute(of: focused) { frame = focusedFrame.offsetBy(dx: -screenFrame.minX, dy: -(desktopTop - screenFrame.maxY)) }
                    }
                }
            }
        }

        var capturedImage: CapturedScreenImage?
        var textRegions: [ScreenTextRegion] = []
        var ocrResult = ""
        var failure: ScreenInspectionFailure?
        if let capture {
            do {
                let fullImage = try await capture(screen)
                let image: CGImage
                if let selection {
                    guard let cropped = selection.crop(fullImage) else { throw ScreenInspectionFailure.captureFailed }
                    image = cropped
                } else { image = fullImage }
                if let selection { frame = selection.bounds }
                capturedImage = CapturedScreenImage(cgImage: image)
                try Task.checkCancellation()
                let owned = ScreenOCRImage(image: image)
                let recognized = try await Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    return try Self.readRegions(in: owned.image)
                }.value
                ocrResult = String(recognized.map(\.text).joined(separator: "\n").prefix(6000))
                let area = selection?.bounds ?? CGRect(origin: .zero, size: screenFrame.size)
                textRegions = recognized.map { region in
                    .init(text: region.text, frame: CGRect(x: area.minX + region.frame.minX*area.width,
                        y: area.minY + region.frame.minY*area.height, width: region.frame.width*area.width, height: region.frame.height*area.height))
                }
                try Task.checkCancellation()
            } catch is CancellationError { failure = .cancelled }
            catch let error as ScreenInspectionFailure { failure = error }
            catch { failure = .captureFailed }
        } else { failure = .unavailable }
        let text = ocrResult.isEmpty ? value : ocrResult
        let explanation = failure?.message(english: false) ?? (text.isEmpty
            ? "Não encontrei texto legível nesta tela."
            : "Na sua tela está escrito: \(text)")

        return ScreenSemanticReading(
            elementRole: role,
            elementTitle: title,
            elementValue: value,
            ocrText: ocrResult,
            elementFrame: frame,
            cursorPoint: cursorTopLeft,
            spokenExplanation: explanation,
            failure: failure,
            capturedImage: capturedImage,
            screenFrame: screenFrame,
            textRegions: textRegions, selectedText: selectedText
        )
    }

    /// Recognizes actual captured pixels locally; images are never persisted.
    nonisolated func recognizeText(in cgImage: CGImage) throws -> String {
        try Self.readText(in: cgImage)
    }

    nonisolated private static func readText(in cgImage: CGImage) throws -> String {
        String(try readRegions(in: cgImage).map(\.text).joined(separator: "\n").prefix(6000))
    }

    nonisolated private static func readRegions(in cgImage: CGImage) throws -> [ScreenTextRegion] {
        // UI text should not wait for the accurate model's orientation assets
        // to compile. Use Vision's fast local recognizer first; retain accurate
        // recognition for text/languages it cannot read. Both use actual pixels.
        do {
            let regions = try recognizeRegions(in: cgImage, level: .fast)
            if !regions.isEmpty { return regions }
        }
        catch {
            try Task.checkCancellation()
        }
        return try recognizeRegions(in: cgImage, level: .accurate)
    }

    nonisolated private static func recognizeRegions(in cgImage: CGImage, level: VNRequestTextRecognitionLevel) throws -> [ScreenTextRegion] {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        // Avoid Neural Engine assets that can be unavailable on a macOS build.
        let stages = try request.supportedComputeStageDevices
        for (stage, devices) in stages {
            if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return (request.results ?? []).prefix(150).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return .init(text: text, frame: CGRect(x: box.minX, y: 1-box.maxY, width: box.width, height: box.height))
        }
    }

    /// One frame, only after an explicit screen request. Exclude our overlays
    /// so the answer and character do not obscure the user's original content.
    private static func captureDisplay(_ screen: NSScreen?) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenInspectionFailure.permission }
        try Task.checkCancellation()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let display = content.displays.first(where: { $0.displayID == number?.uint32Value }) else {
            throw ScreenInspectionFailure.unavailable
        }
        let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = min(2, screen?.backingScaleFactor ?? 1)
        config.width = min(5120, Int(CGFloat(display.width) * scale))
        config.height = min(3200, Int(CGFloat(display.height) * scale))
        config.showsCursor = false
        config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var rawValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &rawValue)
        guard status == .success, let str = rawValue as? String else { return nil }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func frameAttribute(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef,
              let sizeValue = sizeRef,
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }
}

// CGImage is immutable and retained while Vision runs on its worker task.
private struct ScreenOCRImage: @unchecked Sendable { let image: CGImage }

enum ScreenInspectionFailure: Error, Equatable, Sendable {
    case permission, unavailable, captureFailed, cancelled
    func message(english: Bool) -> String {
        switch self {
        case .permission: return english
            ? "Allow Sieghart in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
            : "Permita o Sieghart em Ajustes do Sistema → Privacidade e Segurança → Gravação de Tela e Áudio do Sistema e tente novamente."
        case .unavailable: return english ? "Screen capture is unavailable right now." : "A captura da tela não está disponível agora."
        case .captureFailed: return english ? "I couldn't capture your screen. Check screen recording permission and try again." : "Não consegui capturar sua tela. Confira a permissão de gravação da tela e tente novamente."
        case .cancelled: return english ? "Screen reading cancelled." : "Leitura da tela cancelada."
        }
    }
}

/// Immutable, retained pixels can cross to the local model worker. This type
/// never writes an image file or sends it to a cloud service.
struct CapturedScreenImage: @unchecked Sendable, Equatable {
    let cgImage: CGImage
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.cgImage === rhs.cgImage }
}
