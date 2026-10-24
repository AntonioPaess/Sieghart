import CoreGraphics
import Foundation
import Testing

private actor GeneratedCanvasFixture: SpatialContentGenerating {
    var requests: [CanvasRequest] = []
    let document: GeneratedCanvas
    let holds: Bool
    var pending: CheckedContinuation<GeneratedCanvas, any Error>?
    init(document: GeneratedCanvas, holds: Bool = false) { self.document = document; self.holds = holds }
    func canvas(for request: CanvasRequest, language: String) async throws -> GeneratedCanvas {
        requests.append(request)
        if holds { return try await withCheckedThrowingContinuation { pending = $0 } }
        return document
    }
    func describeScreen(_ image: CapturedScreenImage, text: String, question: String, language: String) async throws -> String { throw SpatialContentError.noVision }
    func finish() { pending?.resume(returning: document); pending = nil }
    var entered: Bool { !requests.isEmpty }
}

@MainActor private final class CanvasScreenFixture: ScreenSemanticInspecting {
    let reading: ScreenSemanticReading
    var requests: [String] = []
    init(failure: ScreenInspectionFailure? = nil) {
        reading = .init(elementRole: "AXTextArea", elementTitle: "Selected source", elementValue: "",
            ocrText: "final class TripPreviewCoordinator { func showPreview() {} }", elementFrame: .zero,
            cursorPoint: .zero, spokenExplanation: "", failure: failure)
    }
    func inspectAtCursor(query: String) async -> ScreenSemanticReading { requests.append(query); return reading }
    func recognizeText(in cgImage: CGImage) throws -> String { reading.ocrText }
}

extension LogicTests {
    @Suite(.tags(.logic, .interactions)) struct GeneratedCanvasLogicTests {
        @Test("G30.02 · Generic screen content requests preserve subject and code intent", arguments: [
            ("Escreva o código do Two Sum na minha tela e me explique", true),
            ("Desenha uma casa com uma árvore", false),
            ("Crie um diagrama do ciclo da água", false),
            ("Show the binary search code on my screen", true)
        ])
        func requestRouting(_ request: String, _ code: Bool) throws {
            let parsed = try #require(CanvasRequest.parse(request))
            #expect(parsed.prompt == request && parsed.wantsCode == code)
        }
        @Test("G30.02 · Search, negation and instructions about drawing do not create a canvas", arguments: [
            "Pesquise como desenhar uma casa", "Não desenhe uma casa", "How to draw a tree?", "Como desenhar um cachorro?"
        ])
        func inertTopics(_ request: String) { #expect(CanvasRequest.parse(request) == nil) }

        @Test("G30.02 · Generated graphics validate finite bounded coordinates and real geometry")
        @MainActor func graphicsValidation() throws {
            let line = CanvasElement(kind: .polyline, points: [.init(x: 0.1, y: 0.2), .init(x: 0.5, y: 0.8), .init(x: 0.9, y: 0.2)], text: "", ink: .gold, filled: false)
            let document = GeneratedCanvas(title: "Fixture", spokenSummary: "A generated diagram.", code: "", codeLanguage: "", elements: [line])
            #expect(try document.validated() == document)
            let path = GeneratedCanvasView.path(for: line, in: .init(x: 0, y: 0, width: 100, height: 100))
            #expect(!path.isEmpty && abs(path.boundingRect.width - 80) < 0.01)
            let invalid = CanvasElement(kind: .polyline, points: [.init(x: .nan, y: 0.2), .init(x: 2, y: 0.8)], text: "", ink: .cyan, filled: false)
            #expect(throws: SpatialContentError.self) {
                try GeneratedCanvas(title: "Invalid", spokenSummary: "Invalid.", code: "", codeLanguage: "", elements: [invalid]).validated()
            }
            #expect(throws: SpatialContentError.self) {
                try GeneratedCanvas(title: "Empty", spokenSummary: "Empty.", code: "", codeLanguage: "", elements: []).validated()
            }
        }
    }
}

extension MacContractsTests {
    @MainActor @Suite(.tags(.isolated, .voiceIntegration)) struct GeneratedCanvasTests {
        private func codeDocument() -> GeneratedCanvas {
            .init(title: "Generated code", spokenSummary: "Here is the requested function.", code: "func value() -> Int { 42 }", codeLanguage: "Swift", elements: [])
        }
        @Test("G30.03 · A class diagram receives observed source through typed and voice entry", arguments: [false, true])
        func observedClassContext(_ usesAudio: Bool) async throws {
            let document = codeDocument(), service = GeneratedCanvasFixture(document: document)
            let inspector = CanvasScreenFixture(), speech = SigVoiceSynthesizer(playsHardwareAudio: false)
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: speech, inspector: inspector, managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, spatialContent: service, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); coordinator.stopBackgroundWork(); overlay.dismiss() }
            let prompt = "Faça um diagrama dessa classe do CarPlay e me explique"
            if usesAudio {
                #expect(coordinator.tryHandleVoiceCommand(prompt) == .handledAsync)
                try await PresentationWait.until { overlay.generatedCanvas != nil }
            } else {
                _ = await coordinator.executeFromChatIfApplicable(prompt)
            }
            let requests = await service.requests
            #expect(inspector.requests == [prompt] && requests.count == 1)
            #expect(requests.first?.screenContext == inspector.reading.ocrText)
            #expect(requests.first?.authorPrompt.contains("TripPreviewCoordinator") == true)
            #expect(overlay.generatedCanvas == document)
            #expect(usesAudio ? speech.lastSpokenText == document.spokenSummary : speech.lastSpokenText == nil)
        }
        @Test("G30.03 · Missing screen permission blocks class generation and offers recovery")
        func missingClassPermission() async throws {
            let service = GeneratedCanvasFixture(document: codeDocument())
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: SigVoiceSynthesizer(playsHardwareAudio: false), inspector: CanvasScreenFixture(failure: .permission), managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, spatialContent: service, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); coordinator.stopBackgroundWork(); overlay.dismiss() }
            _ = await coordinator.executeFromChatIfApplicable("Faça um diagrama dessa classe do CarPlay e me explique")
            let requests = await service.requests
            #expect(requests.isEmpty && overlay.generatedCanvas == nil)
            #expect(coordinator.screenAccessIssue == .permission)
        }
        @Test("G30.03 · Translate this takes a fresh reading unless the user explicitly refers to the old reading")
        func freshScreenReference() async throws {
            let inspector = CanvasScreenFixture(), voice = PresentationVoiceGenerator()
            let overlay = SpatialOverlayViewModel(inspector: inspector, managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, voiceEngine: voice, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); coordinator.stopBackgroundWork() }
            _ = await coordinator.executeFromChatIfApplicable("Leia minha tela")
            _ = await coordinator.executeFromChatIfApplicable("Traduza isso")
            #expect(inspector.requests == ["Leia minha tela", "Traduza isso"])
        }
        @Test("G30.02 · Code is supplied by the generator and appears as text in the actual overlay")
        func generatedCodeDelivery() async throws {
            let document = codeDocument(), speech = SigVoiceSynthesizer()
            let service = GeneratedCanvasFixture(document: document)
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: speech, managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, spatialContent: service, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); overlay.dismiss() }
            let request = "Escreva o código do Two Sum na minha tela e explique"
            #expect(coordinator.tryHandleVoiceCommand(request) == .handledAsync)
            try await PresentationWait.until { overlay.generatedCanvas != nil }
            #expect(overlay.generatedCanvas == document && overlay.activeDrawing == nil)
            #expect(speech.lastSpokenText == document.spokenSummary && overlay.isPresentingOverlay)
            let requests = await service.requests
            #expect(requests.first?.prompt == request && requests.first?.wantsCode == true)
        }
        @Test("G30.02 · Cancelled generation cannot show content or speak after a replacement")
        func cancelledCanvasGeneration() async throws {
            let service = GeneratedCanvasFixture(document: codeDocument(), holds: true)
            let speech = SigVoiceSynthesizer()
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: speech, managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, spatialContent: service, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); overlay.dismiss() }
            #expect(coordinator.tryHandleVoiceCommand("Write code on my screen") == .handledAsync)
            while !(await service.entered) { await Task.yield() }
            coordinator.cancelVoiceResponse()
            await service.finish()
            await Task.yield(); await Task.yield()
            #expect(overlay.generatedCanvas == nil && !overlay.isPresentingOverlay && speech.lastSpokenText == nil)
        }
    }
}
