import AppKit
import Foundation
import Testing

extension LogicTests {
    @Suite(.tags(.logic, .interactions)) struct ProductPolishLogicTests {
        @Test("G30.02 · Toulouse retains its city and country and Lisboa is a weather follow-up")
        func weatherPhrasing() {
            #expect(VoiceWeatherQuery.parse("Qual a temperatura de Toulouse na França?")?.city == "toulouse na franca")
            #expect(VoiceWeatherQuery.parse("E Lisboa?", previousCity: "Bragança em Portugal")?.city == "lisboa")
            #expect(VoiceWeatherQuery.parse("E em Lisboa?", previousCity: "Bragança em Portugal")?.city == "lisboa")
            #expect(VoiceWeatherQuery.parse("pode continuar", previousCity: "Lisboa") == nil)
        }
        @Test("G30.02 · Weather context cannot consume a new explanation or drawing", arguments: [
            "explicar sobre circunferência", "explique os ângulos", "explain circumference",
            "draw a triangle", "read this text", "Você consegue desenhar um círculo na minha tela e me explicar sobre circunferência?"
        ])
        func newIntentAfterWeather(_ request: String) {
            #expect(VoiceWeatherQuery.parse(request, previousCity: "Lisboa") == nil)
            #expect(VoiceWeatherQuery.parse(request, previousCity: "Lisboa", expectsLocation: true) == nil)
        }
        @Test("G30.02 · Location ellipses require a continuation or an explicit pending question")
        func weatherLocationScope() {
            for city in ["Lisboa", "Zermmat", "Toulouse na França"] {
                #expect(VoiceWeatherQuery.parse(city, previousCity: "Recife") == nil)
                #expect(VoiceWeatherQuery.parse("E " + city, previousCity: "Recife")?.city != nil)
                #expect(VoiceWeatherQuery.parse(city, expectsLocation: true)?.city != nil)
            }
        }
        @Test("G30.02 · A provider cannot replace Toulouse in France with Franca in Brazil")
        func geographicIdentity() async throws {
            let service = VoiceWeatherService(transport: { request in
                let url = try #require(request.url), items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let json: String
                if url.host == "geocoding-api.open-meteo.com" {
                    let name = items.first { $0.name == "name" }?.value
                    json = name == "toulouse" ? #"{"results":[{"name":"Toulouse","latitude":43.6,"longitude":1.44,"country":"França","country_code":"FR","population":490000,"feature_code":"PPLA"}]}"# : #"{"results":[{"name":"Franca","latitude":-20.5,"longitude":-47.4,"country":"Brasil","country_code":"BR","feature_code":"PPLA"}]}"#
                } else {
                    #expect(items.first { $0.name == "latitude" }?.value == "43.6")
                    json = #"{"timezone":"Europe/Paris","current":{"time":1800000000,"temperature_2m":10,"apparent_temperature":9,"weather_code":2,"is_day":0}}"#
                }
                return (Data(json.utf8), try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            }, now: { Date(timeIntervalSince1970: 1800000000) })
            let report = try await service.report(to: .init(city: "toulouse na franca", future: false), language: "pt-BR")
            #expect(report.observation?.location == "Toulouse, França")
            let paris = WeatherPlace(name: "Paris", latitude: 48, longitude: 2, admin1: "Île-de-France", country: "France", feature_code: "PPLC", country_code: "FR")
            #expect(!WeatherNameMatching.matches("Paris no Texas", place: paris))
            #expect(WeatherNameMatching.matches("Paris na França", place: paris))
        }
        @Test("G03.05 · Responsibilities route code and mathematics to Ada, utilities to Sieg")
        func responsibilities() {
            for text in ["Explique o Two Sum em Swift", "Explique pi e a circunferência", "Faça o diagrama dessa classe do CarPlay"] {
                #expect(CompanionConversationRouting.destination(for: text, current: .sig, history: []) == .ada)
            }
            for text in ["Qual a temperatura de Recife?", "Ativa o Keep Awake por 2 horas"] {
                #expect(CompanionConversationRouting.destination(for: text, current: .ada, history: []) == .sig)
            }
        }
        @Test("G30.03 · Selected source and accessible editor text take priority over noisy screen OCR")
        func sourcePriority() {
            var reading = ScreenSemanticReading(elementRole: "AXTextArea", elementTitle: "Source", elementValue: "class ExactName {}", ocrText: "Menus and broken OCR", elementFrame: .zero, cursorPoint: .zero, spokenExplanation: "")
            #expect(reading.readableText == "class ExactName {}")
            reading.selectedText = "func selectedMethod() {}"
            #expect(reading.readableText == "func selectedMethod() {}")
        }
    }
}

private actor PolishWeatherFixture: VoiceWeatherProviding {
    var requests: [VoiceWeatherQuery] = []
    func reply(to query: VoiceWeatherQuery) async throws -> String { "Weather fixture" }
    func report(to query: VoiceWeatherQuery, language: String) async throws -> VoiceWeatherReport {
        requests.append(query)
        return .init(reply: "Weather fixture", observation: .init(location: query.city ?? "Missing", temperature: 12, feelsLike: 11, date: Date(), timezone: "UTC", code: 0, isDay: true))
    }
}

private actor PolishSpecialistFixture: SpatialContentGenerating {
    var contexts: [String] = []
    func canvas(for request: CanvasRequest, language: String) async throws -> GeneratedCanvas { throw SpatialContentError.unavailable }
    func describeScreen(_ image: CapturedScreenImage, text: String, question: String, language: String) async throws -> String { throw SpatialContentError.noVision }
    func askSpecialist(_ persona: LocalChatPersona, question: String, context: String, language: String) async throws -> String {
        contexts.append(context); return "Observed source explanation"
    }
}
@MainActor private final class PolishScreenFixture: ScreenSemanticInspecting {
    var requests = 0
    let failure: ScreenInspectionFailure?
    init(failure: ScreenInspectionFailure? = nil) { self.failure = failure }
    func inspectAtCursor(query: String) async -> ScreenSemanticReading {
        requests += 1
        return .init(elementRole: "AXTextArea", elementTitle: "Source", elementValue: "final class ActualVisibleClass {}", ocrText: "Menu noise", elementFrame: .zero, cursorPoint: .zero, spokenExplanation: "", failure: failure)
    }
    func recognizeText(in cgImage: CGImage) throws -> String { "" }
}

extension MacContractsTests {
    @MainActor @Suite(.tags(.isolated, .voiceIntegration)) struct ProductPolishStateTests {
        @Test("G30.02 · A second voice turn E Lisboa reuses weather intent without invoking a generic model")
        func voiceWeatherContinuation() async throws {
            let weather = PolishWeatherFixture(), speech = SigVoiceSynthesizer(playsHardwareAudio: false)
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: speech, managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, weather: weather, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); coordinator.stopBackgroundWork() }
            #expect(coordinator.tryHandleVoiceCommand("Qual a temperatura de Bragança em Portugal?") == .handledAsync)
            try await PresentationWait.until { coordinator.weatherObservation != nil }
            #expect(coordinator.tryHandleVoiceCommand("E Lisboa?") == .handledAsync)
            try await PresentationWait.until { coordinator.weatherObservation?.location == "lisboa" }
            #expect(await weather.requests.map(\.city) == ["braganca em portugal", "lisboa"])
        }
        @Test("G30.02 · Draw and explain remains a compound action after weather", arguments: [
            "Você consegue desenhar um círculo na minha tela e me explicar sobre circunferência?",
            "Desenha um triângulo na tela e explica os ângulos",
            "Draw a circle on my screen and explain circumference",
            "Desenha uma estrela e me fale sobre astronomia"
        ])
        func drawingExplanationAfterWeather(_ command: String) async throws {
            let weather = PolishWeatherFixture(), inspector = PolishScreenFixture()
            let engine = PresentationVoiceGenerator(); engine.reply = "A fresh explanation from the model"
            let speech = SigVoiceSynthesizer(playsHardwareAudio: false)
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: speech, inspector: inspector, managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, voiceEngine: engine, weather: weather, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); coordinator.stopBackgroundWork(); overlay.dismiss() }
            #expect(coordinator.tryHandleVoiceCommand("Qual a temperatura de Lisboa?") == .handledAsync)
            try await PresentationWait.until { coordinator.weatherObservation != nil }
            #expect(coordinator.tryHandleVoiceCommand(command) == .handledAsync)
            try await PresentationWait.until { coordinator.lastStatus == engine.reply }
            let shape = try #require(VectorDrawingInterpreter.parseShape(from: command))
            #expect(overlay.activeDrawing?.shape == shape)
            #expect(coordinator.weatherObservation == nil && inspector.requests == 0)
            #expect(await weather.requests.count == 1)
            let prompt = try #require(engine.requests.last?.last?.text)
            #expect(prompt.contains(command) && prompt.contains(shape.rawValue))
            #expect(engine.requests.count == 1)
        }
        @Test("G30.01 · Model unavailability never produces a canned explanation", arguments: ["Explique pi", "Explique circunferência", "Explain π", "Explain gravity"], ["pt-BR", "en-US"])
        func unavailableModelDoesNotMock(_ request: String, _ language: String) async throws {
            let engine = OfflineFallbackChatEngine(forVoice: true)
            var snapshots: [String] = []
            do {
                _ = try await engine.generateVoice(history: [.init(role: .user, text: request)], language: language) { snapshots.append($0) }
                Issue.record("An unavailable model must not fabricate an answer")
            } catch let LocalChatError.unavailable(message) {
                #expect(message.contains(language.hasPrefix("en") ? "unavailable" : "não está disponível"))
            }
            #expect(snapshots.isEmpty)
        }
        @Test("G30.03 · Ada receives actual observed source before answering a voice screen question")
        func specialistScreenEvidence() async throws {
            let service = PolishSpecialistFixture(), inspector = PolishScreenFixture()
            let speech = SigVoiceSynthesizer(playsHardwareAudio: false)
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: speech, inspector: inspector, managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, spatialContent: service, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); coordinator.stopBackgroundWork(); overlay.dismiss() }
            #expect(coordinator.tryHandleVoiceCommand("Ada, explica o código na minha tela") == .handledAsync)
            try await PresentationWait.until { coordinator.lastStatus == "Observed source explanation" }
            #expect(inspector.requests == 1)
            let contexts = await service.contexts
            #expect(contexts.count == 1 && contexts[0].contains("final class ActualVisibleClass {}") && !contexts[0].contains("Menu noise"))
        }
        @Test("G03.05 · Handoff opens Ada's conversation and preserves the originating Sieg chat")
        func chatHandoff() async throws {
            let engine = PresentationVoiceGenerator(); engine.reply = "Code explanation fixture"
            let chat = LocalChatViewModel(generator: engine)
            await chat.prepare(); let source = try #require(await chat.create(.sig))
            chat.draft = "Explique o Two Sum em Swift"; chat.send(to: source)
            try await PresentationWait.until { chat.generatingID == nil && chat.selected?.messages.last?.role == .assistant }
            #expect(chat.selected?.persona == .ada && chat.selectedID != source)
            let original = try #require(chat.conversations.first { $0.id == source })
            #expect(original.persona == .sig && original.messages.last?.handoff?.conversationID == chat.selectedID)
            chat.shutdown()
        }
        @Test("G03.05 · Legacy utility conversations are reclassified without losing their contents")
        func legacyOwnership() async throws {
            let original = LocalChatConversation(persona: .ada, title: "Recife", messages: [.init(role: .user, text: "Qual a temperatura de Recife?"), .init(role: .assistant, text: "27 graus"), .init(role: .user, text: "Agora explique o Two Sum em Swift")])
            let chat = LocalChatViewModel(generator: PresentationVoiceGenerator(), store: MemoryLocalChatStore([original]))
            await chat.prepare()
            #expect(chat.selected?.persona == .sig && chat.selected?.messages == original.messages && chat.selected?.id == original.id)
        }
        @Test("G03.05 · A backend ignoring cancellation cannot leave chat thinking forever or publish a late reply")
        func chatDeadline() async throws {
            let engine = PresentationVoiceGenerator(); engine.holdsReplies = true
            defer { engine.finishAll() }
            let chat = LocalChatViewModel(generator: engine, responseTimeout: .milliseconds(100))
            await chat.prepare(); let id = try #require(await chat.create(.sig))
            chat.draft = "Hello"; chat.send(to: id)
            try await PresentationWait.until { chat.generatingID == nil && chat.states[id] == .failed }
            #expect(chat.draft == "Hello" && chat.selected?.messages.isEmpty == true)
            engine.finish(0, reply: "Late reply must not appear")
            await Task.yield(); await Task.yield()
            #expect(chat.selected?.messages.isEmpty == true && chat.generationStartedAt == nil)
            chat.shutdown()
        }
        @Test("G30.01 · The compact weather receipt expires and opening it preserves the detailed result")
        func pointerReceipt() async throws {
            let pointer = ScreenInteractionController(managesWindows: false)
            let weather = VoiceWeatherObservation(location: "Lisboa", temperature: 12, feelsLike: 11, date: Date(), timezone: "UTC", code: 0, isDay: true)
            var opened = 0, finished = 0
            pointer.onOpenWeather = { observed in #expect(observed == weather); opened += 1 }; pointer.onWeatherFinished = { finished += 1 }
            pointer.setPhase(.speaking); pointer.setWeatherReceipt(weather); pointer.finishResponse(receiptDuration: .milliseconds(50))
            #expect(pointer.phase == .idle && pointer.weatherReceipt == weather && finished == 1)
            try await PresentationWait.until { pointer.weatherReceipt == nil }
            pointer.setWeatherReceipt(weather); pointer.openWeather()
            #expect(opened == 1 && pointer.weatherReceipt == nil)
            pointer.cancel()
        }
        @Test("G30.01 · Weather leaves Home after completion even while hovered; its cursor receipt restores details")
        func weatherSurfaceLifecycle() async throws {
            let weather = PolishWeatherFixture()
            let fixture = try PresentationFixture(voiceWeather: weather)
            defer { fixture.cleanup() }
            var speech = fixture.notch.spatialAssistant.overlay.voiceSynthesizer.configuration
            speech.enabled = false
            fixture.notch.spatialAssistant.overlay.voiceSynthesizer.configuration = speech
            let activation = try fixture.activation()
            fixture.notch.setPointerInsidePanel(true)
            activation.executeVoiceCommand("Qual a temperatura de Lisboa?")
            try await PresentationWait.until { fixture.notch.spatialAssistant.weatherObservation != nil && !activation.isVoiceBusy }
            fixture.notch.setPointerInsidePanel(false)
            fixture.notch.setPointerInsidePanel(true)
            try await PresentationWait.until({ fixture.notch.spatialAssistant.weatherObservation == nil }, timeout: .seconds(8))
            #expect(fixture.notch.isVisible && fixture.notch.presentation == .home)
            #expect(fixture.notch.spatialAssistant.resultCardHeight == 0)
            #expect(fixture.notch.spatialAssistant.screenInteraction.weatherReceipt != nil)
            fixture.notch.spatialAssistant.screenInteraction.openWeather()
            try await PresentationWait.until { fixture.notch.presentation == .home && fixture.notch.spatialAssistant.weatherObservation?.location == "lisboa" }
            activation.cancelVoiceCommand(keepCompanionVisible: true)
            try await PresentationWait.until { fixture.notch.spatialAssistant.weatherObservation == nil }
            #expect(fixture.notch.spatialAssistant.screenInteraction.weatherReceipt == nil)
        }
    }
}
