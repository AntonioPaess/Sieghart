import AppKit
import Foundation
import Testing

extension LogicTests {
    @Suite(.tags(.logic, .interactions)) struct DiagramLayoutTests {
        private func graph(_ count: Int, arrangement: CanvasDiagram.Arrangement) -> CanvasDiagram {
            let nodes = (0..<count).map { CanvasDiagram.Node(id: "n\($0)", title: "Concept \($0)", detail: "A meaningful relationship", kind: .process) }
            var links = (1..<count).map { CanvasDiagram.Link(from: arrangement == .hierarchy ? "n0" : "n\($0-1)", to: "n\($0)", label: "") }
            if arrangement == .cycle { links.append(.init(from: "n\(count-1)", to: "n0", label: "Repeats")) }
            return .init(arrangement: arrangement, nodes: nodes, links: links)
        }
        @Test("G30.02 · Semantic diagrams lay out every node without overlap and preserve links", arguments: [2,3,4,5,6,7,8,9,10,11,12])
        func semanticLayout(_ count: Int) throws {
            let bounds = CGRect(x: 40, y: 80, width: 1080, height: 600)
            for arrangement in [CanvasDiagram.Arrangement.flow, .cycle, .hierarchy] {
                if count > 8, arrangement == .cycle { continue }
                let graph = try graph(count, arrangement: arrangement).validated()
                let layout = CanvasDiagramLayout.make(graph, in: bounds)
                #expect(layout.boxes.count == count && layout.connections.count == graph.links.count)
                for (index, box) in layout.boxes.enumerated() {
                    #expect(bounds.insetBy(dx: -1, dy: -1).contains(box.frame))
                    for other in layout.boxes.dropFirst(index+1) { #expect(box.frame.intersection(other.frame).isEmpty) }
                }
                #expect(layout.boxes.allSatisfy { !$0.node.title.isEmpty })
            }
        }
        @Test("G30.02 · Invalid diagram endpoints, duplicate IDs and orphan concepts are rejected")
        func diagramIntegrity() throws {
            let a = CanvasDiagram.Node(id: "a", title: "A", detail: "", kind: .process)
            let b = CanvasDiagram.Node(id: "b", title: "B", detail: "", kind: .process)
            for nodes in [[a,a], [a,b,.init(id: "c", title: "C", detail: "", kind: .note)]] {
                #expect(throws: SpatialContentError.self) { try CanvasDiagram(arrangement: .flow, nodes: nodes, links: [.init(from: "a", to: "b", label: "")]).validated() }
            }
            #expect(throws: SpatialContentError.self) { try CanvasDiagram(arrangement: .flow, nodes: [a,b], links: [.init(from: "a", to: "missing", label: "")]).validated() }
        }
        @Test("G30.02 · Diagram intent wins over geometric words used as subject matter")
        func diagramIntent() throws {
            let request = try #require(CanvasRequest.parse("Desenhe um diagrama com retângulos explicando compilação"))
            #expect(request.wantsDiagram && !request.wantsCode)
        }
        @Test("G30.01 · Streaming text emits complete sentences once and preserves decimals")
        func sentenceBuffer() {
            var buffer = SpeechSentenceBuffer()
            let first = buffer.append("Pi vale aproximadamente 3.14159. A próxima")
            #expect(first == ["Pi vale aproximadamente 3.14159."])
            let second = buffer.append("Pi vale aproximadamente 3.14159. A próxima frase está completa.")
            #expect(second == ["A próxima frase está completa."])
            let repeated = buffer.append("Pi vale aproximadamente 3.14159. A próxima frase está completa.", final: true)
            #expect(repeated.isEmpty)
        }
        @Test("G30.05 · Search artifacts contain real parsed source URLs and reject empty or unsafe results")
        func sourceParsing() throws {
            let xml = "<rss><channel><item><title>Swift</title><link>https://www.swift.org/documentation/</link><description>Language documentation.</description></item><item><title>Unsafe</title><link>javascript:alert(1)</link><description>Ignore</description></item></channel></rss>"
            let sources = try PublicWebResearchService.sources(from: Data(xml.utf8))
            #expect(sources.count == 1 && sources[0].url.host == "www.swift.org")
            #expect(throws: ResearchFailure.self) { try PublicWebResearchService.sources(from: Data("<rss><channel/></rss>".utf8)) }
            let irrelevant = ResearchSource(title: "Swift food store", url: URL(string: "https://example.com/food")!, excerpt: "Buy meat online")
            #expect(PublicWebResearchService.relevant([irrelevant], to: "Swift programming language").isEmpty)
        }
        @Test("G03.05 · Model tools cannot invent action permission, change the requested duration, or reverse an action")
        func toolAuthorization() {
            #expect(SiegDesktopToolAuthorization.command(operation: "keep_awake", minutes: 999, original: "Ative o Keep Awake por 2 horas") == .keepAwake(minutes: 120))
            #expect(SiegDesktopToolAuthorization.command(operation: "keep_awake", minutes: 120, original: "Qual o estado do Keep Awake?") == nil)
            #expect(SiegDesktopToolAuthorization.command(operation: "keep_awake", minutes: 120, original: "Não ative o Keep Awake") == nil)
            #expect(SiegDesktopToolAuthorization.command(operation: "keep_awake", minutes: 120, original: "Desliga o Keep Awake") == nil)
            #expect(SiegDesktopToolAuthorization.command(operation: "stop_keep_awake", minutes: 0, original: "Ative o Keep Awake") == nil)
            #expect(SiegDesktopToolAuthorization.command(operation: "keep_awake", minutes: 30, original: "Ative o Keep Awake por 2 horas e mostre a memória") == .keepAwake(minutes: 120))
            #expect(SiegDesktopToolAuthorization.command(operation: "keep_awake", minutes: 180, original: "Deixe o Mac acordado por 2h60") == nil)
            #expect(SpatialAssistantCoordinator.requiresToolPlan("Ative o Keep Awake por 2 horas e mostre a memória"))
            #expect(SiegDesktopToolAuthorization.command(operation: "keep_awake", minutes: 120, original: "How do I keep my Mac awake?") == nil)
            #expect(SiegDesktopToolAuthorization.command(operation: "keep_awake", minutes: 120, original: "Diga a frase ative o Keep Awake") == nil)
        }
    }
}

private actor SilentSentenceProvider: NeuralSpeechProviding {
    private(set) var texts: [String] = []
    func audio(for text: String, language: String, rate: Int) async throws -> Data { texts.append(text); return Data(text.utf8) }
}
@MainActor private final class SilentSentencePlayer: NeuralSpeechPlaying {
    private(set) var played: [Data] = []
    private var completion: (@MainActor () -> Void)?
    func play(_ audio: Data, volume: Float, onFinished: @escaping @MainActor () -> Void) throws { played.append(audio); completion = onFinished }
    func stop() { completion = nil }
    func finish() { let done = completion; completion = nil; done?() }
}

@MainActor private final class WalkthroughInspectorFixture: ScreenSemanticInspecting {
    var readings: [ScreenSemanticReading]
    private(set) var calls = 0
    init(_ readings: [ScreenSemanticReading]) { self.readings = readings }
    func inspectAtCursor(query: String) async -> ScreenSemanticReading {
        calls += 1
        return readings.count > 1 ? readings.removeFirst() : readings[0]
    }
    nonisolated func recognizeText(in cgImage: CGImage) throws -> String { "fixture" }
}

extension MacContractsTests {
    @MainActor @Suite(.tags(.isolated, .voiceIntegration)) struct IntegratedExperienceTests {
        @Test("G03.05 · Repeated model calls reuse the verified action receipt within one turn")
        func repeatedToolCall() async throws {
            let coordinator = SpatialAssistantCoordinator(managesWindows: false)
            var executions = 0
            coordinator.appCommandHandler = { _ in executions += 1; return ("Enabled for 120 minutes", true) }
            let first = await coordinator.executeModelTool("keep_awake", query: "", minutes: 120, original: "Ative o Keep Awake por 2 horas")
            let second = await coordinator.executeModelTool("keep_awake", query: "", minutes: 120, original: "Ative o Keep Awake por 2 horas")
            #expect(first == second && executions == 1)
            coordinator.cancelVoiceResponse()
            _ = await coordinator.executeModelTool("keep_awake", query: "", minutes: 120, original: "Ative o Keep Awake por 2 horas")
            #expect(executions == 2)
        }
        private func screen(_ labels: [String]) -> ScreenSemanticReading {
            .init(elementRole: "AXWindow", elementTitle: "Test", elementValue: "", ocrText: labels.joined(separator: "\n"), elementFrame: .zero, cursorPoint: .zero, spokenExplanation: "",
                screenFrame: CGRect(x: 0, y: 0, width: 640, height: 480), textRegions: labels.enumerated().map { .init(text: $0.element, frame: .init(x: 20, y: 20 + $0.offset*50, width: 100, height: 30)) })
        }
        @Test("G30.03 · Guided steps require the actual target click and an observed result before advancing")
        func verifiedWalkthrough() async throws {
            let initial = screen(["Open"]), changed = screen(["Settings", "Finish"]), done = screen(["Done"])
            let inspector = WalkthroughInspectorFixture([initial, changed, done])
            let overlay = SpatialOverlayViewModel(inspector: inspector, managesWindow: false)
            let guide = ScreenWalkthrough(overlay: overlay, managesWindows: false)
            defer { guide.cancel(); overlay.dismiss() }
            let plan = ScreenGuidancePlan(title: "Test workflow", steps: [
                .init(instruction: "Click Open", targetText: "Open", expectedText: "Settings"),
                .init(instruction: "Click Finish", targetText: "Finish", expectedText: "Done")])
            try guide.start(plan, reading: initial, language: "en-US")
            guide.clicked(globalAppKitPoint: .init(x: 400, y: 300))
            #expect(inspector.calls == 0 && guide.index == 0)
            guide.clicked(globalAppKitPoint: .init(x: 40, y: 445))
            try await PresentationWait.until { inspector.calls == 1 && !guide.isVerifying }
            #expect(guide.index == 0 && guide.status.contains("haven't confirmed"))
            guide.clicked(globalAppKitPoint: .init(x: 40, y: 445))
            try await PresentationWait.until { guide.index == 1 }
            #expect(overlay.activeHighlight?.recognizedText == "Finish")
            guide.confirmCurrentStep()
            try await PresentationWait.until { !guide.isActive }
            #expect(!overlay.isPresentingOverlay && guide.status.contains("completed"))
        }
        @Test("G30.03 · Cancelling a walkthrough before verification prevents another screen capture")
        func cancelledWalkthrough() async throws {
            let reading = screen(["Open"]), inspector = WalkthroughInspectorFixture([screen(["Done"])])
            let overlay = SpatialOverlayViewModel(inspector: inspector, managesWindow: false)
            let guide = ScreenWalkthrough(overlay: overlay, managesWindows: false)
            try guide.start(.init(title: "Fixture", steps: [.init(instruction: "Open", targetText: "Open", expectedText: "Done")]), reading: reading, language: "en-US")
            guide.clicked(globalAppKitPoint: .init(x: 40, y: 445)); guide.cancel()
            await Task.yield(); await Task.yield()
            #expect(inspector.calls == 0 && !overlay.isPresentingOverlay)
        }
        @Test("G30.03 · The held session retains exactly the selected region and ends pointer capture on release")
        func selectionLifecycle() throws {
            let controller = ScreenInteractionController(managesWindows: false)
            let screen = CGRect(x: -1000, y: 100, width: 800, height: 600)
            controller.beginListening(language: "en-US")
            controller.drag(to: .init(x: 30, y: 40), in: screen)
            controller.drag(to: .init(x: 230, y: 140), in: screen)
            controller.finishListening()
            let selected = try #require(controller.takeSelection())
            #expect(selected.bounds == CGRect(x: 30, y: 40, width: 200, height: 100))
            #expect(selected.screenFrame == screen && controller.pendingSelection == nil && controller.phase == .thinking)
            controller.cancel()
            #expect(controller.phase == .idle && controller.trace.isEmpty)
        }
        @Test("G30.03 · Region capture converts screen points to image pixels without including another monitor")
        func regionPixels() throws {
            let color = CGColorSpaceCreateDeviceRGB()
            let context = try #require(CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 0, space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let image = try #require(context.makeImage())
            let selection = ScreenSelection(screenFrame: .init(x: -800, y: 0, width: 800, height: 600), bounds: .init(x: 30, y: 40, width: 200, height: 100), trace: [])
            let cropped = try #require(selection.crop(image))
            #expect(cropped.width == 400 && cropped.height == 200)
            #expect(ScreenSelection(screenFrame: selection.screenFrame, bounds: .init(x: 790, y: 0, width: 200, height: 100), trace: []).crop(image) == nil)
        }
        @Test("G30.03 · A missing selected monitor never broadens a request to another display")
        func missingSelectedMonitor() async throws {
            var captures = 0
            let inspector = ScreenSemanticInspector(queriesSystemAX: false, capture: { _ in captures += 1; throw ScreenInspectionFailure.captureFailed })
            let selected = ScreenSelection(screenFrame: .init(x: 100_000, y: 100_000, width: 800, height: 600), bounds: .init(x: 10, y: 10, width: 100, height: 100), trace: [])
            let result = await inspector.inspect(query: "Read only this region", selection: selected)
            #expect(result.failure == .unavailable && captures == 0 && result.capturedImage == nil)
        }
        @Test("G30.01 · Next speech sentence is fetched while the current one plays; completion waits for both")
        func prefetchedSentences() async throws {
            let provider = SilentSentenceProvider(), player = SilentSentencePlayer()
            var done = 0
            let stream = SigSpeechStream(provider: provider, player: player, language: "en-US", rate: 0, volume: 0.8,
                fallback: { _, _ in Issue.record("No real voice fallback may run in this isolated test") }, finished: { done += 1 })
            defer { stream.cancel() }
            stream.append("This is the first sentence. This is the second sentence.", final: true)
            try await PresentationWait.until { player.played.count == 1 }
            while await provider.texts.count < 2 { await Task.yield() }
            #expect(player.played.count == 1 && done == 0)
            player.finish()
            #expect(player.played.count == 2 && done == 0)
            player.finish()
            try await PresentationWait.until { done == 1 }
        }
        @Test("G30.01 · Cancelling streamed speech removes queued phrases and late completion callbacks")
        func cancelledSpeechQueue() async throws {
            let provider = SilentSentenceProvider(), player = SilentSentencePlayer()
            var done = false
            let stream = SigSpeechStream(provider: provider, player: player, language: "pt-BR", rate: 0, volume: 1, fallback: { _, _ in }, finished: { done = true })
            stream.append("Esta é a primeira frase completa. Esta é a segunda frase completa.", final: true)
            try await PresentationWait.until { player.played.count == 1 }
            stream.cancel(); player.finish(); await Task.yield()
            #expect(player.played.count == 1 && !done)
        }
    }
}
