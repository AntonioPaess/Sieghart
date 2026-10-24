import Foundation
import Testing

@MainActor private final class VoiceAwakeBackend: AwakeBackend {
    var acquisitions = 0
    var releases = 0
    var available = true
    var fails = false
    func context() -> AwakeContext { .init(onAC: available) }
    func acquire(display: Bool) throws -> UInt32 {
        if fails { throw UtilityFailure(message: "fixture power failure") }
        acquisitions += 1
        return 7
    }
    func release(_ token: UInt32) { releases += 1 }
}

@MainActor private final class VoiceSystemSampler: SystemSampling {
    var reads = 0
    func read() -> MonitorReading {
        reads += 1
        var reading = MonitorReading()
        reading.memoryTotal = 16 * 1_073_741_824
        reading.memoryUsed = 6 * 1_073_741_824
        reading.battery = 0.73
        reading.disks = [.init(id: "/", name: "Mac", total: 512 * 1_073_741_824, free: 100 * 1_073_741_824)]
        reading.sampledAt = Date()
        return reading
    }
}

private struct VoiceWeatherFixture: VoiceWeatherProviding {
    var fails = false
    func reply(to query: VoiceWeatherQuery) async throws -> String {
        if fails { throw URLError(.notConnectedToInternet) }
        #expect(query.city == "recife")
        return "Em Recife, a temperatura estimada é de 28 graus Celsius."
    }
}

extension MacContractsTests {
    @MainActor @Suite(.tags(.isolated, .voiceIntegration)) struct VoiceFlowTests {
        @Test("G03.01 · Listening/final drain pin the island; only final trailing words execute once")
        func pinnedFinalSearch() async throws {
            let f = try PresentationFixture(pointerExitDelay: .milliseconds(20), keyboardRevealDelay: .milliseconds(40))
            defer { f.cleanup() }
            let activation = try f.activation()
            try await f.startVoice()
            f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.stays({ f.notch.isVisible && f.notch.presentation == .home && activation.isListening }, for: .milliseconds(80))
            for tick in 1...10 { f.level(-42, at: Double(tick) / 10) }
            f.recognize("Pesquise por ChatGPT no Google")
            for tick in 11...25 { f.level(-20, at: Double(tick) / 10) }
            for tick in 26...41 { f.level(-42, at: Double(tick) / 10) }
            #expect(!activation.isListening && activation.isFinalizing && f.capture.finishCount == 1)
            #expect(f.queries.isEmpty)
            f.notch.collapseAfterPointerExit()
            #expect(f.notch.presentation == .home && f.notch.isVisible)
            let final = "Pesquise no Google por ChatGPT API + Swift"
            f.recognize(final, final: true); f.recognize(final, final: true)
            try await PresentationWait.until { !activation.isVoiceBusy && activation.commandAcknowledged }
            #expect(activation.companionVoicePhase == .success)
            #expect(f.queries == ["ChatGPT API + Swift"] && f.urls.count == 1)
            let url = try #require(f.urls.first)
            let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(parts.host == "www.google.com" && parts.queryItems?.first?.value == "ChatGPT API + Swift")
            f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.until { f.notch.presentation == .island }
        }

        @Test("G03.02 · Authoritative final dispatches despite loud microphone") func loudFinal() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            f.clock.voiceTime = 10; try await f.startVoice()
            f.level(-20, at: 10.1); f.recognize("Open Safari", final: true)
            #expect(activation.isExecutingVoiceCommand && activation.companionVoicePhase == .working)
            try await PresentationWait.until { f.apps == ["safari"] && !activation.isVoiceBusy }
            #expect(f.capture.finishCount == 1 && activation.commandAcknowledged)
        }

        @Test("G03.02 · A final callback inside finish preserves acknowledgement and runs once") func synchronousFinish() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            try await f.startVoice()
            f.capture.finishResult = "Search on Google for café & Swift"
            f.recognize("Search on Google for café"); activation.finishListening()
            try await PresentationWait.until { !activation.isVoiceBusy && activation.commandAcknowledged }
            #expect(activation.voiceStatus == "Search opened · Fixture café & Swift")
            #expect(f.queries == ["café & Swift"] && f.capture.finishCount == 1)
        }

        @Test("G03.03 · Replacing cancelled finalization ignores an old session callback") func staleFinal() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            f.clock.voiceTime = 30; try await f.startVoice()
            f.recognize("Search for cancelled command"); activation.finishListening()
            let oldIndex = try #require(f.capture.receivers.indices.last)
            activation.cancelVoiceCommand()
            f.clock.voiceTime = 40; try await f.startVoice()
            f.capture.emit(.recognition(text: "Search for cancelled command", final: true), from: oldIndex)
            #expect(activation.isListening && activation.transcript.isEmpty)
            f.recognize("Start focus for 20 minutes", final: true)
            #expect(f.assistant.focusMinutes == 20 && f.assistant.hasActiveSession)
            #expect(f.queries.isEmpty && activation.commandAcknowledged)
        }

        @Test("G03.03 · A tool without final recognition times out without execution") func strictToolFinal() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            f.clock.voiceTime = 50; try await f.startVoice()
            f.recognize("Start focus for 40 minutes"); activation.finishListening()
            f.clock.voiceTime = 54.1
            try await PresentationWait.until { !activation.isVoiceBusy }
            #expect(!activation.commandAcknowledged && f.queries.isEmpty && !f.assistant.hasActiveSession)
            #expect(activation.voiceStatus.contains("nothing was run"))
        }

        @Test("G03.04 · Input change after recognition rejects late final") func changedInput() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            try await f.startVoice(); f.recognize("Search for interrupted command")
            f.capture.emit(.inputChanged)
            #expect(!activation.isVoiceBusy && activation.voiceStatus.contains("Microphone changed"))
            f.recognize("Search for interrupted command", final: true)
            #expect(f.queries.isEmpty && !activation.commandAcknowledged)
        }

        @Test("G03.04 · Denied permission never starts capture") func deniedAccess() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            f.capture.accessError = VoiceCaptureFailure.microphoneAccess
            activation.toggleListening()
            try await PresentationWait.until { !activation.isVoiceBusy }
            #expect(activation.voiceStatus.contains("Allow microphone"))
            #expect(f.capture.receivers.isEmpty)
        }

        @Test("G03.04 · Preparation pins the island and cancelling pending access never starts capture") func cancelledAccess() async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            f.capture.holdsAccess = true; activation.toggleListening()
            try await PresentationWait.until { f.capture.accessEntered }
            try await PresentationWait.stays({ activation.isPreparing && f.notch.isVisible && f.notch.presentation == .home }, for: .milliseconds(80))
            activation.cancelVoiceCommand(); f.capture.releaseAccess()
            try await PresentationWait.until { f.capture.accessCompleted }
            #expect(f.capture.receivers.isEmpty && !activation.isVoiceBusy)
        }

        struct SearchExample: Sendable { let spoken: String; let query: String; let missingFinal: Bool }
        nonisolated static let searchCases = [
            SearchExample(spoken: "pesquise no Google por arquiteturas de mac", query: "arquiteturas de mac", missingFinal: false),
            SearchExample(spoken: "pesquisa no Google github", query: "github", missingFinal: true),
            SearchExample(spoken: "procure no Google astrofísica e buracos negros", query: "astrofísica e buracos negros", missingFinal: false)
        ]
        @Test("G03.05 · Portuguese search reproductions and missing-final recovery", arguments: searchCases)
        func portugueseSearches(_ example: SearchExample) async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            f.clock.voiceTime = 100; try await f.startVoice()
            #expect(activation.companionVoicePhase == .listening)
            f.speakAndFallQuiet(partial: example.spoken, base: 100)
            #expect(activation.isFinalizing && activation.companionVoicePhase == .thinking)
            if example.missingFinal {
                f.capture.emit(.failure("fixture: recognizer stopped without final result"))
                #expect(activation.isFinalizing && f.queries.isEmpty)
                f.clock.voiceTime = 106.5
            } else { f.recognize(example.spoken, final: true) }
            try await PresentationWait.until { activation.commandAcknowledged && !activation.isVoiceBusy }
            #expect(f.queries == [example.query])
        }

        @Test("G03.05 · Spoken questions use local conversation and speech without browser or mentioned actions", arguments: [
            "O que é o pi?", "GitHub", "meu Mac não liga", "Como iniciar o pomodoro?", "Como abrir o YouTube?"
        ])
        func spokenAnswers(_ question: String) async throws {
            let generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator); defer { f.cleanup() }
            let activation = try f.activation()
            try await f.startVoice()
            f.recognize(question, final: true)
            try await PresentationWait.until { activation.commandAcknowledged && !activation.isVoiceBusy }
            #expect(generator.requests.last?.last?.text == question)
            #expect(activation.voiceStatus == generator.reply)
            #expect(f.notch.spatialAssistant.overlay.voiceSynthesizer.lastSpokenText == generator.reply)
            #expect(f.queries.isEmpty && f.urls.isEmpty && f.apps.isEmpty && !f.assistant.hasActiveSession)
        }

        @Test("G03.05 · Circle and pi explanation execute together from one final spoken transcript")
        func drawAndExplainPi() async throws {
            let generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator); defer { f.cleanup() }
            let activation = try f.activation()
            try await f.startVoice()
            f.recognize("Desenha uma circunferência na minha tela e explica sobre o pi", final: true)
            #expect(f.notch.spatialAssistant.overlay.activeDrawing?.shape == .circle)
            try await PresentationWait.until { activation.commandAcknowledged && !activation.isVoiceBusy }
            let prompt = try #require(generator.requests.last?.last?.text)
            #expect(prompt.contains("Desenha uma circunferência na minha tela e explica sobre o pi"))
            #expect(prompt.contains("already drawn a circle") && prompt.contains("explica sobre o pi"))
            #expect(f.notch.spatialAssistant.overlay.voiceSynthesizer.lastSpokenText == generator.reply)
            #expect(f.notch.spatialAssistant.overlay.activeDrawing?.shape == .circle)
            #expect(f.queries.isEmpty && f.urls.isEmpty)
        }

        @Test("G03.05 · Named-city weather is spoken from live-data provider without a model or browser")
        func weatherSpokenAnswer() async throws {
            let generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator, voiceWeather: VoiceWeatherFixture()); defer { f.cleanup() }
            let activation = try f.activation()
            try await f.startVoice()
            f.recognize("Qual a temperatura de Recife agora?", final: true)
            try await PresentationWait.until { activation.commandAcknowledged && !activation.isVoiceBusy }
            #expect(generator.requests.isEmpty && f.queries.isEmpty && f.urls.isEmpty)
            #expect(activation.voiceStatus.contains("28 graus Celsius"))
            #expect(f.notch.spatialAssistant.overlay.voiceSynthesizer.lastSpokenText == activation.voiceStatus)
        }

        @Test("G03.05 · Weather connection failure is spoken without invented temperature or browser fallback")
        func failedWeatherAnswer() async throws {
            let generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator, voiceWeather: VoiceWeatherFixture(fails: true)); defer { f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("Qual a temperatura de Recife?")
            try await PresentationWait.until { !activation.isVoiceBusy }
            #expect(!activation.commandAcknowledged && activation.voiceStatus.contains("Não consegui consultar"))
            #expect(generator.requests.isEmpty && f.queries.isEmpty)
        }

        @Test("G03.05 · Keep Awake voice command holds an actual app assertion for exactly two hours and can stop")
        func keepAwakeFromVoice() async throws {
            let backend = VoiceAwakeBackend()
            let generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator, awakeBackend: backend); defer { f.cleanup() }
            let activation = try f.activation()
            try await f.startVoice()
            f.recognize("Você consegue ativar o keep awake por duas horas pra mim?", final: true)
            #expect(f.notch.keepAwake.enabled && f.notch.keepAwake.holding && backend.acquisitions == 1)
            #expect(f.notch.keepAwake.request.minutes == 120 && f.notch.keepAwake.remaining == 7200)
            #expect(activation.commandAcknowledged && activation.voiceStatus.contains("120 minutos"))
            #expect(f.notch.spatialAssistant.overlay.voiceSynthesizer.lastSpokenText == activation.voiceStatus)
            activation.executeVoiceCommand("Desativa o Keep Awake")
            #expect(!f.notch.keepAwake.enabled && !f.notch.keepAwake.holding && backend.releases == 1)
            #expect(generator.requests.isEmpty && f.queries.isEmpty)
        }

        @Test("G03.05 · Typed and spoken conversation share app actions, metrics and weather")
        func sharedConversationTools() async throws {
            let backend = VoiceAwakeBackend(), sampler = VoiceSystemSampler()
            let f = try PresentationFixture(voiceWeather: VoiceWeatherFixture(), awakeBackend: backend, sampler: sampler)
            defer { f.cleanup() }
            let coordinator = f.notch.spatialAssistant
            let started = try #require(await coordinator.executeFromChatIfApplicable("Você consegue ativar o Keep Awake por duas horas?"))
            #expect(started.contains("ativado") && f.notch.keepAwake.holding && backend.acquisitions == 1)
            let battery = try #require(await coordinator.executeFromChatIfApplicable("Qual a bateria do meu Mac?"))
            #expect(battery.contains("73 por cento"))
            let weather = try #require(await coordinator.executeFromChatIfApplicable("Qual a temperatura de Recife agora?"))
            #expect(weather.contains("28 graus Celsius"))
            _ = await coordinator.executeFromChatIfApplicable("Desativa o Keep Awake")
            #expect(!f.notch.keepAwake.enabled && backend.releases == 1)
        }

        @Test("G03.05 · Keep Awake reports waiting conditions and power errors truthfully")
        func keepAwakeFailureAndConditions() throws {
            let backend = VoiceAwakeBackend(); backend.available = false
            let f = try PresentationFixture(awakeBackend: backend); defer { f.cleanup() }
            let activation = try f.activation()
            f.notch.keepAwake.request.onlyOnAC = true
            activation.executeVoiceCommand("Ativa o Keep Awake por 2 horas")
            #expect(f.notch.keepAwake.enabled && !f.notch.keepAwake.holding && backend.acquisitions == 0)
            #expect(activation.voiceStatus.contains("aguardando") && f.notch.keepAwake.request.onlyOnAC)
            backend.available = true; backend.fails = true
            activation.executeVoiceCommand("Ativa o Keep Awake por 2 horas")
            #expect(!activation.commandAcknowledged && activation.voiceStatus.contains("Não consegui ativar"))
        }

        @Test("G03.05 · Computer questions read the app's current metrics and do not invent specifications")
        func computerInformation() throws {
            let sampler = VoiceSystemSampler(), generator = PresentationVoiceGenerator()
            let f = try PresentationFixture(voiceGenerator: generator, sampler: sampler); defer { f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("Quanta memória RAM tem meu Mac?")
            #expect(activation.voiceStatus.contains("16,0 gigabytes") && activation.voiceStatus.contains("6,0 em uso"))
            activation.executeVoiceCommand("Qual a bateria do meu Mac?")
            #expect(activation.voiceStatus.contains("73 por cento"))
            activation.executeVoiceCommand("Quanto espaço livre tem meu Mac?")
            #expect(activation.voiceStatus.contains("100,0 gigabytes livres"))
            #expect(sampler.reads == 3 && generator.requests.isEmpty && f.queries.isEmpty)
        }

        @Test("G03.05 · Cancelling a spoken question suppresses a late answer and speech")
        func cancelledSpokenAnswer() async throws {
            let generator = PresentationVoiceGenerator(); generator.holdsReplies = true
            let f = try PresentationFixture(voiceGenerator: generator)
            defer { generator.finishAll(); f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("O que é o pi?")
            try await PresentationWait.until { generator.requests.count == 1 }
            activation.cancelVoiceCommand()
            generator.finish(0, reply: "Resposta antiga")
            try await PresentationWait.stays({ activation.voiceStatus == "Voice is off" && !activation.commandAcknowledged }, for: .milliseconds(30))
            #expect(!f.notch.spatialAssistant.overlay.voiceSynthesizer.isSpeaking && f.queries.isEmpty)
        }

        @Test("G03.05 · Follow-up context survives while replacement suppresses an old completion")
        func replacementSpokenAnswer() async throws {
            let generator = PresentationVoiceGenerator(); generator.holdsReplies = true
            let f = try PresentationFixture(voiceGenerator: generator)
            defer { generator.finishAll(); f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("O que é o pi?")
            try await PresentationWait.until { generator.requests.count == 1 }
            activation.executeVoiceCommand("O que é o raio?")
            try await PresentationWait.until { generator.requests.count == 2 }
            generator.finish(1, reply: "O raio liga o centro à circunferência.")
            try await PresentationWait.until { activation.commandAcknowledged }
            generator.finish(0, reply: "Resposta antiga")
            try await PresentationWait.stays({ activation.voiceStatus == "O raio liga o centro à circunferência." }, for: .milliseconds(30))
            activation.executeVoiceCommand("E o diâmetro?")
            try await PresentationWait.until { generator.requests.count == 3 }
            #expect(generator.requests[2].map(\.text) == ["O que é o raio?", "O raio liga o centro à circunferência.", "E o diâmetro?"])
            generator.finish(2, reply: "O diâmetro mede duas vezes o raio.")
            try await PresentationWait.until { activation.commandAcknowledged }
            #expect(f.queries.isEmpty && f.notch.spatialAssistant.overlay.voiceSynthesizer.lastSpokenText == "O diâmetro mede duas vezes o raio.")
        }

        struct FocusExample: Sendable { let spoken: String; let minutes: Int }
        @Test("G03.06 · Spoken focus durations require final and execute exactly once", arguments: [
            FocusExample(spoken: "inicia o foco", minutes: 25), FocusExample(spoken: "inicia o pomodoro", minutes: 25),
            FocusExample(spoken: "inicia o pomodor em 20 minutos", minutes: 20),
            FocusExample(spoken: "inicia o pomodoro em vinte e cinco minutos", minutes: 25),
            FocusExample(spoken: "Sig, inicie o foco por 40 minutos", minutes: 40)
        ])
        func focusCommands(_ example: FocusExample) async throws {
            let f = try PresentationFixture(); defer { f.cleanup() }
            let activation = try f.activation()
            f.assistant.setFocusMinutes(25); f.clock.voiceTime = 200
            let completed = f.assistant.completedSessions
            try await f.startVoice(); f.speakAndFallQuiet(partial: "inicia o foco", base: 200)
            #expect(activation.isFinalizing && !f.assistant.hasActiveSession)
            f.recognize(example.spoken, final: true); f.recognize(example.spoken, final: true)
            #expect(f.assistant.isRunning && f.assistant.focusMinutes == example.minutes)
            #expect(f.assistant.activeTimerMode == .pomodoro && f.assistant.interval == .focus)
            #expect(f.assistant.remainingSeconds == Double(example.minutes * 60))
            #expect(f.assistant.completedSessions == completed && f.queries.isEmpty)
            #expect(activation.commandAcknowledged && !activation.isVoiceBusy)
        }

        @Test("G03.07 · Production 700ms cue is visible while timer action runs immediately") func pacedTimer() async throws {
            let f = try PresentationFixture(minimumProcessingDuration: .milliseconds(700)); defer { f.cleanup() }
            let activation = try f.activation()
            #expect(activation.companionVoicePhase == .inactive && !activation.isVoiceBusy)
            activation.executeVoiceCommand("inicia o foco em 20 minutos")
            #expect(f.assistant.isRunning && f.assistant.focusMinutes == 20)
            #expect(!activation.isExecutingVoiceCommand && activation.isPresentingVoiceProcessing)
            #expect(activation.companionVoicePhase == .working && !activation.commandAcknowledged)
            f.notch.setPointerInsidePanel(true); f.notch.setPointerInsidePanel(false)
            try await PresentationWait.stays({ activation.companionVoicePhase == .working && f.notch.presentation == .home }, for: .milliseconds(100))
            try await PresentationWait.until { activation.companionVoicePhase == .success && !activation.isVoiceBusy }
            activation.cancelVoiceCommand()
            #expect(activation.companionVoicePhase == .inactive && !activation.isPresentingVoiceProcessing)
        }

        @Test("G03.07 · Browser action precedes paced acknowledgement; cancellation removes stale completion") func pacedSearchCancellation() async throws {
            let f = try PresentationFixture(minimumProcessingDuration: .milliseconds(700)); defer { f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("pesquisa no Google github")
            try await PresentationWait.until { f.queries == ["github"] }
            #expect(activation.isPresentingVoiceProcessing)
            activation.cancelVoiceCommand()
            try await PresentationWait.stays({ activation.companionVoicePhase == .inactive && !activation.commandAcknowledged && !f.notch.isVisible }, for: .milliseconds(730))
            #expect(f.queries == ["github"])
        }

        @Test("G03.07 · Previous completion cannot interrupt a replacement's processing cue") func replacementCue() async throws {
            let f = try PresentationFixture(minimumProcessingDuration: .milliseconds(700)); defer { f.cleanup() }
            let activation = try f.activation()
            activation.executeVoiceCommand("inicia o foco")
            try await PresentationWait.stays({ activation.companionVoicePhase == .working }, for: .milliseconds(100))
            activation.executeVoiceCommand("pause the timer")
            try await PresentationWait.stays({ activation.companionVoicePhase == .working && !activation.commandAcknowledged }, for: .milliseconds(630))
            try await PresentationWait.until { activation.companionVoicePhase == .success }
            #expect(activation.voiceStatus == "Timer paused")
        }
    }
}
