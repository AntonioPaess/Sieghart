import AppKit
import AVFoundation
import Foundation
import Testing

private actor NeuralAudioFixture: NeuralSpeechProviding {
    struct Request: Sendable { let text: String; let language: String; let rate: Int }
    private(set) var requests: [Request] = []
    private var pending: [CheckedContinuation<Data, any Error>] = []
    func audio(for text: String, language: String, rate: Int) async throws -> Data {
        requests.append(.init(text: text, language: language, rate: rate))
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func deliver(_ data: Data) { pending.removeFirst().resume(returning: data) }
    var count: Int { requests.count }
}

@MainActor private final class NeuralPlayerFixture: NeuralSpeechPlaying {
    var audios: [Data] = []
    var completions: [@MainActor () -> Void] = []
    var volume: Float?
    func play(_ audio: Data, volume: Float, onFinished: @escaping @MainActor () -> Void) {
        audios.append(audio); self.volume = volume; completions.append(onFinished)
    }
    func stop() {}
}

@MainActor private final class SuspendedScreenFixture: ScreenSemanticInspecting {
    var pending: CheckedContinuation<ScreenSemanticReading, Never>?
    func inspectAtCursor(query: String) async -> ScreenSemanticReading {
        await withCheckedContinuation { pending = $0 }
    }
    func recognizeText(in cgImage: CGImage) throws -> String { "" }
    func finish() {
        pending?.resume(returning: .init(elementRole: "AXWindow", elementTitle: "Fixture", elementValue: "", ocrText: "Hello from the screen", elementFrame: .init(x: 40, y: 80, width: 300, height: 100), cursorPoint: .init(x: 100, y: 100), spokenExplanation: "Texto capturado"))
        pending = nil
    }
}

@MainActor private final class MemoryAwakeBackendForVoice: AwakeBackend {
    var acquisitions = 0
    func context() -> AwakeContext { .init(onAC: true) }
    func acquire(display: Bool) throws -> UInt32 { acquisitions += 1; return 99 }
    func release(_ token: UInt32) {}
}

extension LogicTests {
    @Suite(.tags(.logic, .interactions)) struct VoiceExperienceLogicTests {
        @Test("G30.01 · Neural protocol checksum is deterministic for independent reference vectors")
        func neuralChecksum() {
            #expect(EdgeSpeechToken.value(at: Date(timeIntervalSince1970: 0)) == "52BC7A17B50DFEC9-28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6")
            #expect(EdgeSpeechToken.value(at: Date(timeIntervalSince1970: 1792000000)) == "31DE969FFA38E06B-BD29DC903722D717D852F4F854F2386D98C8D3A93663E1A1AE89223A876AFDB4")
        }

        @Test("G30.01 · Neural frames validate length and audio type; XML and chunk sizes remain bounded")
        func neuralProtocolBoundaries() throws {
            let header = Data("Path:audio\r\nContent-Type:audio/mpeg\r\n".utf8)
            let audio = Data([1, 2, 3])
            let frame = Data([UInt8(header.count >> 8), UInt8(header.count & 255)]) + header + audio
            #expect(try EdgeNeuralSpeechService.audioPayload(frame) == audio)
            #expect(throws: NeuralSpeechError.self) { try EdgeNeuralSpeechService.audioPayload(Data([0, 100, 1])) }
            let xml = EdgeNeuralSpeechService.ssml(text: "Hi <Sieg> & 'friend'", language: "en-US", rate: 100)
            #expect(xml.contains("en-US-AndrewNeural") && xml.contains("&lt;Sieg&gt; &amp; &apos;friend&apos;") && xml.contains("+30%"))
            let text = String(repeating: "Olá! &<>\"' 🌦️ ", count: 400)
            let chunks = EdgeNeuralSpeechService.chunks(text)
            #expect(chunks.joined() == text)
            #expect(chunks.allSatisfy { EdgeNeuralSpeechService.ssml(text: $0, language: "pt-BR", rate: -3).utf8.count < 3_600 })
        }

        @Test("G30.02 · Weather report carries actual conditions and localizes both speech and missing-city prompts")
        func weatherReport() async throws {
            let service = VoiceWeatherService(transport: { request in
                let url = try #require(request.url)
                let json = url.host == "geocoding-api.open-meteo.com"
                    ? #"{"results":[{"name":"Recife","latitude":-8,"longitude":-35}]}"#
                    : #"{"timezone":"America/Recife","current":{"time":1800000000,"temperature_2m":28,"apparent_temperature":31,"weather_code":61,"is_day":0}}"#
                return (Data(json.utf8), try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            }, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let report = try await service.report(to: .init(city: "recife", future: false), language: "en-US")
            #expect(report.reply.contains("28 degrees Celsius") && report.reply.contains("Rain"))
            let observation = try #require(report.observation)
            #expect(observation.temperature == 28 && observation.symbol == "cloud.rain.fill" && !observation.isDay)
            #expect(observation.condition(language: "pt-BR") == "Chuva")
            let missing = try await service.report(to: .init(city: nil, future: false), language: "en-US")
            #expect(missing.observation == nil && missing.reply.hasPrefix("Which city"))
        }

        @Test("G30.02 · Spoken city plus region without punctuation resolves without dropping qualifiers", arguments: [
            ("recife pernambuco", "recife, pernambuco", "Recife", "Pernambuco", "Brasil"),
            ("braganca portugal", "braganca, portugal", "Bragança", "Bragança", "Portugal"),
            ("portugal, braganca", "braganca, portugal", "Bragança", "Bragança", "Portugal")
        ])
        func spokenQualifiedCity(_ spoken: String, _ qualified: String, _ city: String, _ region: String, _ country: String) async throws {
            let service = VoiceWeatherService(transport: { request in
                let url = try #require(request.url)
                let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?.value
                let json: String
                if url.host == "geocoding-api.open-meteo.com" {
                    #expect(name?.contains(",") == true || name == spoken)
                    json = name == qualified ? "{\"results\":[{\"name\":\"\(city)\",\"latitude\":41.8,\"longitude\":-6.8,\"admin1\":\"\(region)\",\"country\":\"\(country)\",\"feature_code\":\"PPLA\"}]}" : "{}"
                } else {
                    json = #"{"timezone":"Europe/Lisbon","current":{"time":1800000000,"temperature_2m":17,"apparent_temperature":16,"weather_code":3,"is_day":0}}"#
                }
                return (Data(json.utf8), try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            }, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let report = try await service.report(to: .init(city: spoken, future: false), language: "pt-BR")
            #expect(report.observation?.location.contains(city) == true)
            #expect(report.observation?.location.contains(country) == true)
            #expect(report.reply.contains("17 graus Celsius"))
        }

        @Test("G03.03 · Releases arriving before delayed presses cannot start or stop the wrong voice turn")
        func gestureOrdering() {
            var gesture = VoiceShortcutGesture()
            func verify(_ actual: Bool, _ expected: Bool) { #expect(actual == expected) }
            verify(gesture.release(at: 20), false)
            verify(gesture.press(at: 19), false)
            verify(gesture.press(at: 21), true)
            #expect(gesture.isHeld)
            verify(gesture.press(at: 21.01), false)
            verify(gesture.release(at: 20.5), false)
            #expect(gesture.isHeld)
            verify(gesture.release(at: 22), true)
            #expect(!gesture.isHeld)
            verify(gesture.press(at: 21.9), false)
            verify(gesture.press(at: 23), true)
            gesture.cancel()
            #expect(!gesture.isHeld)
            verify(gesture.press(at: 23), false)
        }

        @Test("G03.03 · Unreadable physical key state never ends capture; confirmed release is debounced")
        func physicalReleaseWatch() {
            var watch = VoiceShortcutReleaseWatch()
            func verify(_ actual: Bool, _ expected: Bool) { #expect(actual == expected) }
            for _ in 0..<10 { verify(watch.observe(false), false); verify(watch.observe(nil), false) }
            verify(watch.observe(true), false)
            verify(watch.observe(false), false)
            verify(watch.observe(false), false)
            verify(watch.observe(true), false)
            verify(watch.observe(false), false)
            verify(watch.observe(false), false)
            verify(watch.observe(false), true)
        }

        @Test("G03.03 · Holding ignores silence/finals but retains capture time and lost-input limits")
        func heldSessionLimits() {
            var session = VoiceCommandSession(); session.start(at: 0)
            session.recognize("first final", final: true, at: 1)
            session.observe(decibels: -50, duration: 0.1, at: 10)
            #expect(session.decision(at: 10, holding: true) == .wait)
            #expect(session.decision(at: 13.1, holding: true) == .inputLost)
            session.observe(decibels: -50, duration: 0.1, at: 55)
            #expect(session.decision(at: 55, holding: true) == .limitReached)
            session.recognize("new trailing words", final: false, at: 55)
            session.endAudio(at: 55)
            #expect(session.takeFinalCommand() == nil)
            session.recognize("new trailing words final", final: true, at: 56)
            #expect(session.takeFinalCommand() == "new trailing words final")
        }
    }
}

extension MacContractsTests {
    @MainActor @Suite(.tags(.isolated, .voiceIntegration)) struct VoiceExperienceTests {
        @Test("G30.01 · Antonio playback completes on audio drain and drops cancelled/stale callbacks")
        func neuralPlaybackLifecycle() async throws {
            let service = NeuralAudioFixture(), player = NeuralPlayerFixture()
            let synth = SigVoiceSynthesizer(configuration: .sieg, playsHardwareAudio: true, neuralService: service, neuralPlayer: player)
            var completions = 0
            synth.speak("Primeira", language: "pt-BR") { completions += 1 }
            while await service.count < 1 { await Task.yield() }
            synth.stop()
            await service.deliver(Data([1]))
            await Task.yield()
            #expect(player.audios.isEmpty && completions == 0)
            synth.speak("Second", language: "en-US") { completions += 1 }
            while await service.count < 2 { await Task.yield() }
            await service.deliver(Data([2]))
            try await PresentationWait.until { player.audios.count == 1 }
            #expect(synth.isSpeaking && synth.activeVoiceIdentifier == "en-US-AndrewNeural" && completions == 0)
            let oldCompletion = try #require(player.completions.last)
            synth.stop()
            synth.speak("Terceira", language: "pt-BR") { completions += 1 }
            oldCompletion()
            #expect(synth.isSpeaking && completions == 0)
            while await service.count < 3 { await Task.yield() }
            await service.deliver(Data([3]))
            try await PresentationWait.until { player.audios.count == 2 }
            player.completions.last?()
            #expect(!synth.isSpeaking && completions == 1 && player.volume == SigVoiceConfiguration.sieg.volume)
        }

        @Test("G03.03 · Shortcut hold never executes during pauses or recognizer finals; release sends once")
        func holdAndRelease() async throws {
            let generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator); defer { f.cleanup() }
            let activation = try f.activation()
            activation.pressVoiceShortcut()
            try await PresentationWait.until { activation.isListening }
            f.recognize("Explique pi", final: true)
            for tick in 1...30 { f.level(-65, at: Double(tick) / 10) }
            #expect(activation.isListening && generator.requests.isEmpty && f.capture.finishCount == 0)
            activation.pressVoiceShortcut() // Repeat cannot restart the microphone.
            activation.releaseVoiceShortcut(); activation.releaseVoiceShortcut()
            try await PresentationWait.until { !activation.isVoiceBusy && activation.commandAcknowledged }
            #expect(generator.requests.count == 1 && f.capture.finishCount == 1 && f.capture.receivers.count == 1)
        }

        @Test("G03.03 · Releasing a shortcut while permission prepares never starts late capture")
        func fastRelease() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            f.capture.holdsAccess = true
            activation.pressVoiceShortcut()
            try await PresentationWait.until { f.capture.accessEntered }
            activation.releaseVoiceShortcut(); f.capture.releaseAccess()
            try await PresentationWait.until { f.capture.accessCompleted }
            #expect(!activation.isVoiceBusy && f.capture.receivers.isEmpty)
        }

        @Test("G03.05 · Selected language reaches generation despite Portuguese history and app confirmations")
        func selectedLanguage() async throws {
            let generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator); defer { f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("Explique pi")
            try await PresentationWait.until { !activation.isVoiceBusy }
            activation.voiceLanguage = "en_US"
            generator.reply = "Pi is the ratio of a circle's circumference to its diameter."
            activation.executeVoiceCommand("Explain pi")
            try await PresentationWait.until { !activation.isVoiceBusy }
            #expect(generator.languages == ["pt-BR", "en-US"] && activation.voiceStatus == generator.reply)
            activation.executeVoiceCommand("Stop Keep Awake")
            #expect(activation.voiceStatus.hasPrefix("Keep Awake disabled"))
        }

        @Test("G03.03 · Keyboard press/release events route voice holds through both shortcut backends")
        func shortcutEvents() async throws {
            let generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator); defer { f.cleanup() }
            let activation = try f.activation()
            activation.setShortcut(.init(keyCode: 5, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "G"), for: .voice)
            activation.receiveHotkey(.voice, eventTime: 10)
            try await PresentationWait.until { activation.isListening }
            f.recognize("Explique pi", final: true)
            activation.receiveShortcutEvent(keyCode: 5, flags: [.control, .option], isKeyUp: true, eventTime: 11)
            activation.receiveHotkey(.voice, released: true, eventTime: 11.01)
            try await PresentationWait.until { !activation.isVoiceBusy }
            #expect(generator.requests.count == 1)
            activation.setShortcut(.init(keyCode: nil, modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue, keyLabel: ""), for: .voice)
            activation.receiveShortcutEvent(keyCode: nil, flags: [.control, .shift], eventTime: 20)
            try await PresentationWait.until { activation.isListening }
            f.recognize("Explique pi outra vez", final: true)
            activation.receiveShortcutEvent(keyCode: nil, flags: [.control], eventTime: 21)
            try await PresentationWait.until { !activation.isVoiceBusy }
            #expect(generator.requests.count == 2)
        }

        @Test("G30.02 · Weather cards resize the widget and clear when a new request fails")
        func weatherCardLifecycle() async throws {
            let service = VoiceWeatherService(transport: { request in
                let url = try #require(request.url)
                let json = url.host == "geocoding-api.open-meteo.com"
                    ? #"{"results":[{"name":"Recife","latitude":-8,"longitude":-35}]}"#
                    : #"{"timezone":"America/Recife","current":{"time":1800000000,"temperature_2m":28,"apparent_temperature":31,"weather_code":61,"is_day":1}}"#
                return (Data(json.utf8), try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            }, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let f = try PresentationFixture(voiceWeather: service); defer { f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("Qual a temperatura de Recife?")
            try await PresentationWait.until { !activation.isVoiceBusy }
            #expect(f.notch.spatialAssistant.weatherObservation?.code == 61)
            f.notch.spatialAssistant.dismissWeather()
            #expect(f.notch.spatialAssistant.weatherObservation == nil)
            activation.executeVoiceCommand("Qual a temperatura agora?")
            try await PresentationWait.until { !activation.isVoiceBusy }
            #expect(f.notch.spatialAssistant.weatherObservation == nil)
        }

        @Test("G30.03 · Translation receives captured text as data and the selected response language")
        func screenTranslation() async throws {
            let inspector = SuspendedScreenFixture(), generator = PresentationVoiceGenerator()
            generator.reply = "Olá da tela"
            let speech = SigVoiceSynthesizer()
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: speech, inspector: inspector, managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, voiceEngine: generator, managesWindows: false)
            defer { coordinator.cancelVoiceResponse(); overlay.dismiss() }
            #expect(coordinator.tryHandleVoiceCommand("Traduza minha tela") == .handledAsync)
            try await PresentationWait.until { inspector.pending != nil }
            inspector.finish()
            try await PresentationWait.until { speech.lastSpokenText == generator.reply }
            #expect(generator.languages == ["pt-BR"])
            #expect(generator.requests.first?.last?.text.contains("<screen_text>\nHello from the screen") == true)
        }

        @Test("G03.05 · Observed Kepa Wake and 2h00 transcript controls the actual Keep Awake backend")
        func observedKeepAwakeTranscript() async throws {
            let generator = PresentationVoiceGenerator()
            // The standard fixture rejects unexpected power writes, so use the
            // app view model directly through the already-tested test backend.
            let backend = MemoryAwakeBackendForVoice()
            let f = try PresentationFixture(voiceGenerator: generator, awakeBackend: backend); defer { f.cleanup() }
            let activation = try f.activation()
            try await f.startVoice()
            f.recognize("Ative o Kepa Wake por 2h00", final: true)
            #expect(f.notch.keepAwake.enabled && f.notch.keepAwake.holding && f.notch.keepAwake.remaining == 7200)
            #expect(backend.acquisitions == 1 && generator.requests.isEmpty && activation.commandAcknowledged)
            #expect(activation.voiceStatus.contains("120 minutos"))
            #expect(VoiceAppCommand.parse("ative o kepa wake por 2h60") == nil)
        }

        @Test("G03.05 · Typed weather and app actions stay in chat and never speak or publish a weather widget")
        func typedRepliesStaySilent() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let coordinator = f.notch.spatialAssistant
            let reply = try #require(await coordinator.executeFromChatIfApplicable("Desativa o Keep Awake"))
            #expect(reply.contains("desativado"))
            #expect(!coordinator.overlay.voiceSynthesizer.isSpeaking && coordinator.overlay.voiceSynthesizer.lastSpokenText == nil)
            let weather = try #require(await coordinator.executeFromChatIfApplicable("Qual a temperatura agora?"))
            #expect(weather.contains("cidade") && coordinator.weatherObservation == nil)
            #expect(coordinator.overlay.voiceSynthesizer.lastSpokenText == nil)
        }

        @Test("G03.03 · Delayed shortcut events and post-final recognizer teardown do not break a held turn")
        func delayedShortcutEvents() async throws {
            let generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator); defer { f.cleanup() }
            let activation = try f.activation()
            activation.setShortcut(.init(keyCode: 9, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "V"), for: .voice)
            activation.receiveHotkey(.voice, released: true, eventTime: 100)
            activation.receiveHotkey(.voice, eventTime: 99)
            await Task.yield()
            #expect(!activation.isVoiceBusy && f.capture.receivers.isEmpty)
            activation.receiveHotkey(.voice, eventTime: 101)
            try await PresentationWait.until { activation.isListening }
            activation.receiveHotkey(.voice, released: true, eventTime: 100.5)
            f.recognize("Explique pi", final: true)
            f.capture.emit(.failure("fixture recognizer teardown after final"))
            #expect(activation.isListening && generator.requests.isEmpty)
            activation.receiveHotkey(.voice, released: true, eventTime: 102)
            activation.receiveHotkey(.voice, eventTime: 101.01)
            // Releasing capture ends its busy state before the coordinator's
            // response task begins. Await both sides of that handoff.
            try await PresentationWait.until { !activation.isVoiceBusy && generator.requests.count == 1 }
            #expect(generator.requests.count == 1 && f.capture.finishCount == 1)
        }

        @Test("G30.03 · Actual image pixels are recognized locally; capture failures do not invent screen text")
        func screenPixelsAndPermission() async throws {
            let image = NSImage(size: .init(width: 700, height: 180))
            image.lockFocus()
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 700, height: 180).fill()
            ("SIEG SCREEN TEST" as NSString).draw(at: .init(x: 40, y: 65), withAttributes: [.font: NSFont.systemFont(ofSize: 38), .foregroundColor: NSColor.black])
            image.unlockFocus()
            let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let inspector = ScreenSemanticInspector(queriesSystemAX: false, capture: { _ in pixels })
            let reading = await inspector.inspectAtCursor(query: "Read my screen")
            #expect(reading.failure == nil && reading.ocrText.contains("SIEG SCREEN TEST"))
            let denied = ScreenSemanticInspector(queriesSystemAX: false, capture: { _ in throw ScreenInspectionFailure.permission })
            let failure = await denied.inspectAtCursor(query: "Read my screen")
            #expect(failure.failure == .permission && failure.ocrText.isEmpty)
            #expect(failure.explanation(language: "en-US").contains("Allow Sieghart"))
        }

        @Test("G30.03 · Cancelled screen capture cannot reopen its annotation or speak an old result")
        func cancelledScreenCapture() async throws {
            let inspector = SuspendedScreenFixture(), speech = SigVoiceSynthesizer()
            let overlay = SpatialOverlayViewModel(voiceSynthesizer: speech, inspector: inspector, managesWindow: false)
            let coordinator = SpatialAssistantCoordinator(overlay: overlay, managesWindows: false)
            #expect(coordinator.tryHandleVoiceCommand("Read my screen") == .handledAsync)
            try await PresentationWait.until { inspector.pending != nil }
            coordinator.cancelVoiceResponse(); inspector.finish()
            await Task.yield(); await Task.yield()
            #expect(!overlay.isPresentingOverlay && speech.lastSpokenText == nil)
        }
    }
}
