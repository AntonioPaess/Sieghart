import AppKit
import AVFoundation
import Foundation
import SwiftUI
import Testing

@MainActor private final class SpatialSpeechCompletionFixture: SigVoiceSynthesizing {
    var isSpeaking = false
    var lastSpokenText: String?
    var configuration = SigVoiceConfiguration()
    var completion: (@MainActor () -> Void)?
    func speak(_ text: String, language: String, onFinished: (@MainActor () -> Void)?) {
        lastSpokenText = text; isSpeaking = true; completion = onFinished
    }
    func stop() { isSpeaking = false; completion = nil }
    func finish() { isSpeaking = false; let callback = completion; completion = nil; callback?() }
}

private actor TransientWeatherFixture {
    private(set) var calls = 0
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        calls += 1
        if calls == 1 { throw URLError(.timedOut) }
        let url = try #require(request.url)
        let json = url.host == "geocoding-api.open-meteo.com"
            ? #"{"results":[{"name":"Recife","latitude":-8,"longitude":-35}]}"#
            : #"{"timezone":"America/Recife","current":{"time":1800000000,"temperature_2m":28,"apparent_temperature":31}}"#
        return (Data(json.utf8), try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
    }
}

extension LogicTests {
    @Suite(.tags(.logic, .interactions))
    struct SpatialAssistantLogicTests {
        @Test("G30.01 · SpeechTranscriptAccumulator merges volatile and finalized segments with native VAD state")
        func transcriptAccumulatorStreaming() {
            var accumulator = SpeechTranscriptAccumulator()
            let s1 = accumulator.ingestTranscriberSegment(text: "Desenhe um", isVolatile: true, at: 1.0)
            #expect(s1.volatileText == "Desenhe um" && s1.finalizedText.isEmpty && !s1.isFinal && s1.speechDetected)
            #expect(s1.combinedText == "Desenhe um")

            let s2 = accumulator.ingestTranscriberSegment(text: "Desenhe um foguete", isVolatile: false, at: 1.4)
            #expect(s2.finalizedText == "Desenhe um foguete" && s2.volatileText.isEmpty && s2.isFinal)

            let s3 = accumulator.ingestTranscriberSegment(text: "na minha tela", isVolatile: true, at: 1.8)
            #expect(s3.combinedText == "Desenhe um foguete na minha tela" && !s3.isFinal)

            let s4 = accumulator.finalizePendingVolatile(at: 2.1)
            #expect(s4.combinedText == "Desenhe um foguete na minha tela" && s4.isFinal && !s4.speechDetected)
        }

        @Test("G30.02 · VectorDrawingInterpreter parses rocket and geometric shapes and builds vector paths")
        func vectorDrawingInterpreter() {
            #expect(VectorDrawingInterpreter.parseShape(from: "Desenhe um foguete na minha tela") == .rocket)
            #expect(VectorDrawingInterpreter.parseShape(from: "Draw a rocket on my screen") == .rocket)
            #expect(VectorDrawingInterpreter.parseShape(from: "Desenhe uma estrela brilhante") == .star)
            #expect(VectorDrawingInterpreter.parseShape(from: "Trace uma seta aqui") == .arrow)
            #expect(VectorDrawingInterpreter.parseShape(from: "Desenhe um círculo") == .circle)
            #expect(VectorDrawingInterpreter.parseShape(from: "Desenhe um coração") == .heart)
            #expect(VectorDrawingInterpreter.parseShape(from: "Não desenhe um foguete") == nil)
            #expect(VectorDrawingInterpreter.parseShape(from: "Open Safari") == nil)

            let canvas = CGRect(x: 0, y: 0, width: 320, height: 320)
            for shape in SpatialVectorShape.allCases {
                let path = VectorDrawingInterpreter.path(for: shape, in: canvas)
                #expect(!path.isEmpty)
                #expect(!path.trimmedPath(from: 0, to: 0.5).isEmpty)
            }
        }

        @Test("G30.02 · Triangle commands preserve geometry intent and unknown drawings fall back to chat", arguments: [
            ("Desenha um triangulo e escreve a hipotenusa", SpatialVectorShape.rightTriangle),
            ("Desenhe um triângulo retângulo", .rightTriangle),
            ("Draw a right triangle and label the hypotenuse", .rightTriangle),
            ("Trace os catetos de um triângulo", .rightTriangle),
            ("Desenhe a hipotenusa", .rightTriangle),
            ("Desenhe um triângulo", .triangle),
            ("Draw a triangle on my screen", .triangle)
        ])
        func triangleCommands(_ prompt: String, _ expected: SpatialVectorShape) {
            #expect(VectorDrawingInterpreter.parseShape(from: prompt) == expected)
        }

        @Test("G30.02 · Unsupported and negated shapes never become a rocket", arguments: [
            "Desenhe um cachorro na tela", "Draw a house on my screen", "Desenha algo na tela",
            "Não desenhe um triângulo com hipotenusa", "Do not draw a right triangle",
            "Don’t draw a triangle", "Explique a hipotenusa de um triângulo"
        ])
        func unsupportedDrawings(_ prompt: String) {
            #expect(VectorDrawingInterpreter.parseShape(from: prompt) == nil)
        }

        @Test("G30.02 · Right triangle has perpendicular legs and a label offset along its hypotenuse")
        func rightTriangleGeometryAndLabels() throws {
            let rect = CGRect(x: 20, y: 40, width: 400, height: 240)
            let path = VectorDrawingInterpreter.path(for: .rightTriangle, in: rect)
            var vertices: [CGPoint] = []
            var closed = false
            path.forEach { element in
                switch element {
                case .move(to: let p), .line(to: let p): vertices.append(p)
                case .closeSubpath: closed = true
                default: break
                }
            }
            try #require(vertices.count >= 3)
            #expect(closed)
            let top = vertices[0], corner = vertices[1], end = vertices[2]
            #expect(top.x == corner.x && corner.y == end.y)
            #expect(top.y < corner.y && corner.x < end.x)
            #expect(vertices.allSatisfy { $0.x >= rect.minX && $0.x <= rect.maxX && $0.y >= rect.minY && $0.y <= rect.maxY })

            let drawing = SpatialVectorDrawing(shape: .rightTriangle, prompt: "Desenha um triangulo e escreve a hipotenusa")
            let labels = drawing.labels(in: rect)
            let label = try #require(labels.first)
            #expect(labels.count == 1 && label.text == "Hipotenusa")
            let dx = end.x - top.x, dy = end.y - top.y
            #expect(abs(label.rotationDegrees - atan2(dy, dx) * 180 / .pi) < 0.001)
            let offset = CGPoint(x: label.position.x - (top.x + end.x) / 2,
                                 y: label.position.y - (top.y + end.y) / 2)
            #expect(abs(offset.x * dx + offset.y * dy) < 0.001)
            #expect(abs(hypot(offset.x, offset.y) - 24) < 0.001)
            #expect(offset.x > 0 && offset.y < 0)
            #expect(SpatialVectorDrawing(shape: .rightTriangle, prompt: "Draw a right triangle").labels(in: rect).isEmpty)
            #expect(SpatialVectorDrawing(shape: .circle, prompt: "hipotenusa").labels(in: rect).isEmpty)
            #expect(drawing.labels(in: .zero).isEmpty)
        }

        @Test("G30.02 · Circumference synonyms and compound explanation are preserved", arguments: [
            "Desenha uma circunferência na minha tela e explica sobre o pi",
            "Desenhe uma circunferencia e me explique o pi",
            "Draw a circumference and explain pi"
        ])
        func circumferenceAndExplanation(_ command: String) {
            #expect(VectorDrawingInterpreter.parseShape(from: command) == .circle)
            #expect(VectorDrawingInterpreter.explanationRequest(in: command) != nil)
        }

        @Test("G30.02 · Questions and search topics mentioning drawings do not draw", arguments: [
            "Como desenhar uma circunferência?", "Pesquise como desenhar um círculo", "Explain how to draw a triangle"
        ])
        func questionsDoNotDraw(_ command: String) {
            #expect(VectorDrawingInterpreter.parseShape(from: command) == nil)
        }

        @Test("G30.02 · Weather route extracts a city and keeps definitions and Mac temperature local")
        func weatherQuestionRouting() {
            #expect(VoiceWeatherQuery.parse("Qual a temperatura de Recife agora?") == .init(city: "recife", future: false))
            #expect(VoiceWeatherQuery.parse("Tu consegue me dizer a temperatura de recife nesse exato momento") == .init(city: "recife", future: false))
            #expect(VoiceWeatherQuery.parse("Como está o tempo em São Paulo hoje?") == .init(city: "sao paulo", future: false))
            #expect(VoiceWeatherQuery.parse("What's the weather in Lisbon?") == .init(city: "lisbon", future: false))
            #expect(VoiceWeatherQuery.parse("Qual a temperatura agora?") == .init(city: nil, future: false))
            #expect(VoiceWeatherQuery.parse("O que é temperatura?") == nil)
            #expect(VoiceWeatherQuery.parse("Qual a temperatura do meu Mac?") == nil)
            #expect(VoiceWeatherQuery.parse("Qual o tempo de duração do pomodoro?") == nil)
        }

        @Test("G30.02 · Weather decodes fresh data, includes source/time and sends the city only to geocoding")
        func weatherHTTPContract() async throws {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let service = VoiceWeatherService(transport: { request in
                let url = try #require(request.url)
                let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                let values = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                let json: String
                if url.host == "geocoding-api.open-meteo.com" {
                    #expect(values["name"] == "recife" && request.timeoutInterval > 0 && request.timeoutInterval <= 4)
                    json = #"{"results":[{"name":"Recife","latitude":-8.05,"longitude":-34.88,"admin1":"Pernambuco","country":"Brasil"}]}"#
                } else {
                    #expect(url.host == "api.open-meteo.com" && values["name"] == nil)
                    #expect(values["current"] == "temperature_2m,apparent_temperature,weather_code,is_day" && values["timeformat"] == "unixtime")
                    json = #"{"timezone":"America/Recife","current":{"time":1800000000,"temperature_2m":28.2,"apparent_temperature":31.1}}"#
                }
                return (Data(json.utf8), try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            }, now: { now })
            let reply = try await service.reply(to: .init(city: "recife", future: false))
            #expect(reply.contains("Recife, Pernambuco, Brasil") && reply.contains("28 graus Celsius") && reply.contains("31 graus"))
            #expect(reply.contains("Open-Meteo") && reply.contains("horário local"))
        }

        @Test("G30.02 · Stale, malformed or failed weather data is rejected", arguments: ["stale", "http", "apparent", "timezone"])
        func invalidWeatherData(_ failure: String) async throws {
            let service = VoiceWeatherService(transport: { request in
                let url = try #require(request.url)
                let time = failure == "stale" ? "100" : "1800000000"
                let feelsLike = failure == "apparent" ? "1e100" : "31"
                let timezone = failure == "timezone" ? "not-a-timezone" : "America/Recife"
                let json = url.host == "geocoding-api.open-meteo.com"
                    ? #"{"results":[{"name":"Recife","latitude":-8,"longitude":-35}]}"#
                    : "{\"timezone\":\"\(timezone)\",\"current\":{\"time\":\(time),\"temperature_2m\":28,\"apparent_temperature\":\(feelsLike)}}"
                return (Data(json.utf8), try #require(HTTPURLResponse(url: url, statusCode: failure == "http" ? 503 : 200, httpVersion: nil, headerFields: nil)))
            }, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            await #expect(throws: (any Error).self) { try await service.reply(to: .init(city: "recife", future: false)) }
        }

        @Test("G30.02 · A cold weather connection retries once after timeout")
        func weatherTimeoutRetry() async throws {
            let fixture = TransientWeatherFixture()
            let service = VoiceWeatherService(transport: { try await fixture.send($0) }, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let reply = try await service.reply(to: .init(city: "recife", future: false))
            #expect(reply.contains("28 graus Celsius"))
            #expect(await fixture.calls == 3)
        }

        @MainActor @Test("G30.01 · Spoken output excludes thought traces and Markdown")
        func spokenReplyFormatting() {
            #expect(SpatialAssistantCoordinator.spokenReply("<think>Não falar isto</think>\n**Pi** é aproximadamente `3,14`. [Exemplo](https://example.com)") == "Pi é aproximadamente 3,14. Exemplo")
        }

        @Test("G30.03 · ScreenSemanticInspector detects screen reading intents without matching normal searches")
        func screenInspectionIntents() {
            #expect(ScreenSemanticInspector.isScreenInspectionIntent("O que tem escrito na minha tela?"))
            #expect(ScreenSemanticInspector.isScreenInspectionIntent("Explique o que é isso aqui"))
            #expect(ScreenSemanticInspector.isScreenInspectionIntent("What is written on my screen?"))
            #expect(!ScreenSemanticInspector.isScreenInspectionIntent("Open Safari"))
            #expect(!ScreenSemanticInspector.isScreenInspectionIntent("Pesquise por Swift"))
        }

        @Test("G30.06 · AdaThoughtDisclosure extracts collapsible reasoning steps for Ada Room")
        func thoughtDisclosureParsing() {
            let raw = """
            <think>
            Analisando arquitetura do projeto
            Verificando conformidade offline do SSC
            </think>
            Aqui está o plano de ação direto.
            """
            let parsed = AdaThoughtDisclosure.parse(raw)
            #expect(parsed.stepCount == 2)
            #expect(parsed.headerTitle == "Pensando... 2 passos")
            #expect(parsed.visibleReply == "Aqui está o plano de ação direto.")
        }
    }
}

extension MacContractsTests {
    @Suite(.tags(.isolated, .voiceIntegration))
    @MainActor
    struct SpatialAssistantIntegrationTests {
        @Test("G30.01 · SigVoiceSynthesizer uses a calm lower tone by default and honors custom settings")
        func sigVoicePitchConfiguration() {
            let synth = SigVoiceSynthesizer(playsHardwareAudio: false)
            #expect(synth.configuredTimePitchCents == -100)
            synth.configuration.pitchCents = -250
            #expect(synth.configuredTimePitchCents == -250)
            synth.speak("Olá, eu sou o Sig!", language: "pt-BR")
            #expect(synth.lastSpokenText == "Olá, eu sou o Sig!")
            #expect(synth.isSpeaking)
            synth.stop()
            #expect(!synth.isSpeaking)
        }

        @Test("G30.01 · Voice selection and tuning survive relaunch and update the live companion")
        func voicePreferencesReachRuntime() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let saved = SigVoiceConfiguration(voiceIdentifier: SigVoiceCatalog.antonio, pitchCents: 0,
                                              rate: 0.42, volume: 0.7, enabled: true)
            CompanionPreferences(defaults: store.value).speechConfiguration = saved
            let f = try PresentationFixture(defaultsFixture: store); defer { f.cleanup() }
            #expect(f.preferences.speechConfiguration == saved)
            #expect(f.notch.spatialAssistant.overlay.voiceSynthesizer.configuration == saved)
            f.preferences.speechConfiguration.rate = 0.55
            f.notch.spatialAssistant.overlay.voiceSynthesizer.speak("Prévia", language: "pt-BR")
            #expect(f.notch.spatialAssistant.overlay.voiceSynthesizer.isSpeaking)
            f.preferences.speechConfiguration.enabled = false
            #expect(!f.notch.spatialAssistant.overlay.voiceSynthesizer.isSpeaking)
            let changed = f.preferences.speechConfiguration
            #expect(f.notch.spatialAssistant.overlay.voiceSynthesizer.configuration == changed)
            #expect(CompanionPreferences(defaults: store.value).speechConfiguration == changed)
        }

        @Test("G30.01 · Invalid voice settings recover safely without changing unrelated preferences")
        func invalidVoicePreferences() throws {
            let store = try TestDefaults(); defer { store.cleanup() }
            let prefs = CompanionPreferences(defaults: store.value)
            prefs.windowGlass = true
            prefs.speechConfiguration = .init(voiceIdentifier: "", pitchCents: 9_000, rate: -2, volume: 4)
            let loaded = CompanionPreferences(defaults: store.value)
            #expect(loaded.speechConfiguration.voiceIdentifier == SigVoiceCatalog.antonio)
            #expect(loaded.speechConfiguration.pitchCents == 0)
            #expect(loaded.speechConfiguration.rate == SigVoiceConfiguration.sieg.rate && loaded.speechConfiguration.volume == 1)
            #expect(loaded.windowGlass)
            store.value.set(Data("invalid JSON".utf8), forKey: "voice.output.configuration.v1")
            #expect(CompanionPreferences(defaults: store.value).speechConfiguration == SigVoiceConfiguration.sieg)
            let normalized = SigVoiceConfiguration(pitchCents: .nan, rate: .infinity, volume: -.infinity).normalized
            #expect(normalized.pitchCents == -100 && normalized.rate.isFinite && normalized.volume == 0.85)
        }

        @Test("G30.01 · Speech chunks own their PCM bytes after the synthesis callback returns", arguments: [AVAudioChannelCount(1), 2])
        func speechChunkOwnership(_ channels: AVAudioChannelCount) throws {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: channels))
            let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
            source.frameLength = 128
            for channel in 0..<Int(channels) {
                for frame in 0..<128 { source.floatChannelData?[channel][frame] = Float(channel + 1) * 0.25 }
            }
            let chunk = try #require(SigVoicePCMChunk(copying: source))
            for channel in 0..<Int(channels) {
                for frame in 0..<128 { source.floatChannelData?[channel][frame] = 0 }
            }
            let copy = try #require(chunk.makeBuffer())
            #expect(copy.frameLength == 128 && copy.format.isEqual(format))
            for channel in 0..<Int(channels) {
                #expect(copy.floatChannelData?[channel][64] == Float(channel + 1) * 0.25)
            }
            source.frameLength = 0
            #expect(SigVoicePCMChunk(copying: source) == nil)
        }

        @Test("G30.01 · Native speech graph accepts mono/stereo speech and converts through its mixer offline", arguments: [
            (AVAudioChannelCount(1), 22_050.0), (2, 44_100.0)
        ])
        func speechAudioFormatRouting(_ channels: AVAudioChannelCount, _ sampleRate: Double) throws {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
            let graph = SigVoicePlaybackGraph(format: format, pitchCents: 500)
            defer { graph.stop() }
            let outputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
            try graph.engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: 512)
            let speech = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
            speech.frameLength = 4096
            for channel in 0..<Int(channels) {
                for frame in 0..<4096 {
                    speech.floatChannelData?[channel][frame] = Float(sin(Double(frame) * 440 * 2 * .pi / sampleRate)) * 0.2
                }
            }
            #expect(graph.player.outputFormat(forBus: 0).isEqual(format))
            #expect(graph.pitch.pitch == 500)
            try graph.schedule(speech) {}
            let output = try #require(AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 512))
            for _ in 0..<16 {
                #expect(try graph.engine.renderOffline(512, to: output) == .success)
            }
            #expect(graph.engine.manualRenderingSampleTime == 8192)
            let mismatch = try #require(AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 64))
            mismatch.frameLength = 64
            #expect(throws: SigVoicePlaybackGraph.PlaybackError.self) { try graph.schedule(mismatch) {} }
        }

        @Test("G30.02 · SpatialOverlayViewModel draws vector rocket, animates stroke trim, and dismisses cleanly")
        func spatialOverlayDrawingAndInspection() async {
            let synth = SigVoiceSynthesizer(playsHardwareAudio: false)
            let overlay = SpatialOverlayViewModel(
                voiceSynthesizer: synth,
                inspector: ScreenSemanticInspector(queriesSystemAX: false),
                managesWindow: false
            )
            overlay.draw(shape: .rocket, prompt: "Desenhe um foguete na minha tela", holdDuration: 10)
            #expect(overlay.isPresentingOverlay)
            #expect(overlay.activeDrawing?.shape == .rocket)
            #expect(overlay.strokeProgress == 1.0)
            #expect(synth.lastSpokenText?.contains("foguete") == true)

            overlay.dismiss()
            #expect(!overlay.isPresentingOverlay && overlay.activeDrawing == nil)

            let reading = await overlay.inspectScreen(query: "O que tem escrito na minha tela?", holdDuration: 10)
            #expect(!overlay.isPresentingOverlay)
            #expect(overlay.activeHighlight == nil)
            #expect(reading.failure == .unavailable && reading.ocrText.isEmpty)
            #expect(synth.lastSpokenText?.contains("não está disponível") == true)
            overlay.dismiss()
        }

        @Test("G30.02 · Compound drawing fades after speech actually ends, without touching a replacement")
        func drawingFollowsSpeechCompletion() async throws {
            let speech = SpatialSpeechCompletionFixture()
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: speech, managesWindow: false)
            let generator = PresentationVoiceGenerator()
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, voiceEngine: generator, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); overlay.dismiss() }
            coordinator.answerVoiceQuestion("Explique pi", drawing: .circle)
            try await PresentationWait.until { speech.isSpeaking }
            try await PresentationWait.stays({ overlay.activeDrawing?.shape == .circle }, for: .milliseconds(50))
            speech.finish()
            try await PresentationWait.until({ overlay.activeDrawing == nil }, timeout: .seconds(2))
            coordinator.answerVoiceQuestion("Explique pi", drawing: .circle)
            try await PresentationWait.until { speech.isSpeaking }
            let oldCompletion = speech.completion
            coordinator.cancelVoiceResponse()
            overlay.draw(shape: .heart, prompt: "Coração", holdDuration: 10)
            oldCompletion?()
            try await PresentationWait.stays({ overlay.activeDrawing?.shape == .heart }, for: .milliseconds(50))
        }

        @Test("G30.02 · Slow generation leaves the main actor responsive and has a bounded loading state")
        func voiceGenerationDeadline() async throws {
            let generator = PresentationVoiceGenerator(); generator.holdsReplies = true
            let coordinator = SpatialAssistantCoordinator(voiceEngine: generator, voiceResponseTimeout: .milliseconds(40), managesWindows: false)
            defer { generator.finishAll(); coordinator.cancelVoiceResponse() }
            var completed = false
            coordinator.answerVoiceQuestion("Explique pi") { reply, success in
                completed = true
                #expect(!success && reply.contains("demorando"))
            }
            try await PresentationWait.until { completed }
            generator.finish(0, reply: "Resposta atrasada")
            try await PresentationWait.stays({ coordinator.lastStatus.contains("demorando") }, for: .milliseconds(50))
        }

        @Test("G30.02 · Ada chat draws and labels the requested triangle and leaves unknown shapes to the chat engine")
        func triangleFromChat() async throws {
            let synth = SigVoiceSynthesizer(playsHardwareAudio: false)
            let overlay = SpatialOverlayViewModel(
                voiceSynthesizer: synth,
                inspector: ScreenSemanticInspector(queriesSystemAX: false),
                managesWindow: false
            )
            defer { overlay.dismiss() }
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, managesWindows: false)
            let reply = try #require(await coordinator.executeFromChatIfApplicable("Desenha um triangulo e escreve a hipotenusa"))
            let drawing = try #require(overlay.activeDrawing)
            #expect(drawing.shape == .rightTriangle)
            #expect(drawing.labels(in: drawing.canvasRect).map(\.text) == ["Hipotenusa"])
            #expect(reply.contains("triângulo retângulo") && reply.contains("Hipotenusa"))
            #expect(synth.lastSpokenText == nil)
            overlay.dismiss()
            #expect(await coordinator.executeFromChatIfApplicable("Desenha um cachorro na tela")?.contains("não está disponível") == true)
            #expect(overlay.activeDrawing == nil && !overlay.isPresentingOverlay)
            #expect(coordinator.tryHandleVoiceCommand("Draw a house on my screen") == .handledAsync)
            coordinator.cancelVoiceResponse()
        }

        @Test("G30.04 · SystemCommandExecutor runs navigation directly and requires Notch confirmation for destructive actions")
        func systemCommandSafetyAndConfirmation() async throws {
            var openedURLs: [URL] = []
            let executor = SystemCommandExecutor(
                appLauncher: { name in "MockApp(\(name))" },
                urlOpener: { url, _ in openedURLs.append(url); return "Opened \(url.host ?? "")" },
                axPresser: { _ in true },
                sensitiveExecutor: { key in key == "empty-trash" }
            )

            let navCmd = try #require(SystemCommandExecutor.parse("Ir no YouTube no Safari"))
            let navResult = try await executor.execute(navCmd)
            #expect(openedURLs.first?.host == "www.youtube.com")
            if case .executed(let summary) = navResult {
                #expect(summary.contains("youtube.com"))
            } else {
                Issue.record("Expected direct execution for non-destructive web navigation")
            }

            let destructiveCmd = try #require(SystemCommandExecutor.parse("Esvaziar lixeira"))
            #expect(destructiveCmd.isDestructive)
            let pendingResult = try await executor.execute(destructiveCmd)
            #expect(executor.pendingConfirmation?.commandKey == "empty-trash")
            if case .awaitingConfirmation(let confirmation) = pendingResult {
                #expect(confirmation.title == "Esvaziar Lixeira")
            } else {
                Issue.record("Expected Notch confirmation gate for destructive command")
            }

            let confirmed = executor.confirmPendingAction()
            #expect(executor.pendingConfirmation == nil)
            #expect(executor.confirmedCommandKeys == ["empty-trash"])
            if case .executed(let summary) = confirmed {
                #expect(summary.contains("Confirmado"))
            } else {
                Issue.record("Expected confirmed execution")
            }
        }

        @Test("G30.05 · BackgroundResearchAgent emits agent-done and delivers interactive ResearchArtifact")
        func backgroundResearchAgentArtifactDelivery() async throws {
            let agent = BackgroundResearchAgent(stepDelay: .milliseconds(10), playsSoundCue: false, provider: SpatialResearchFixture())
            let topic = try #require(BackgroundResearchAgent.parseResearchTopic(from: "Pesquise em segundo plano sobre SwiftUI Spatial Canvas"))
            #expect(topic == "SwiftUI Spatial Canvas")

            var delivered: ResearchArtifact?
            agent.onArtifactDelivered = { artifact in delivered = artifact }

            let artifact = try #require(await agent.startResearch(topic: topic))
            #expect(!agent.isResearching)
            #expect(agent.lastCuePlayed == "agent-done")
            #expect(artifact.completionCue == "agent-done")
            #expect(delivered?.id == artifact.id)
            #expect(artifact.bulletPoints.count == 3)
        }

        @Test("G30.06 · Unavailable generation cannot invent thought steps or a screen inspection")
        func offlineFallbackChatEngine() async throws {
            let engine = OfflineFallbackChatEngine()
            #expect(engine.readiness == .available) // Verified native controls remain callable.
            var snapshots: [String] = []
            do {
                _ = try await engine.generate(
                    history: [LocalChatMessage(role: .user, text: "Explique a arquitetura espacial do Sieghart")],
                    persona: .ada
                ) { snapshots.append($0) }
                Issue.record("Missing inference must produce an unavailable error")
            } catch let LocalChatError.unavailable(message) {
                #expect(message.contains("não está disponível"))
            }
            #expect(snapshots.isEmpty)
        }
    }
}
