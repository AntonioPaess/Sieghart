import Foundation
import Testing

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
            f.capture.finishResult = "Search for café & Swift"
            f.recognize("Search for café"); activation.finishListening()
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
            SearchExample(spoken: "pesquise por arquiteturas de mac", query: "arquiteturas de mac", missingFinal: false),
            SearchExample(spoken: "pesquisa github", query: "github", missingFinal: true),
            SearchExample(spoken: "GitHub", query: "GitHub", missingFinal: false),
            SearchExample(spoken: "meu Mac não liga", query: "meu Mac não liga", missingFinal: false),
            SearchExample(spoken: "procure astrofísica e buracos negros", query: "astrofísica e buracos negros", missingFinal: false)
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
            activation.executeVoiceCommand("pesquisa github")
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
