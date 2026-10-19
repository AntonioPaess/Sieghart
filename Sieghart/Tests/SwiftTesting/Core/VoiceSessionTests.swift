import AVFoundation
import Foundation
import Speech
import Testing

extension LogicTests {
  @Suite(.tags(.callbacks, .logic))
  struct VoiceSessionTests {
    @Test("G02.02 residual noise and authoritative final end audio")
    func endpoints() throws {
      var session = VoiceCommandSession()
      session.start(at: 0)
      for tick in 1...10 { session.observe(decibels: -42, duration: 0.1, at: Double(tick) / 10) }
      session.recognize("Pesquise por ChatGPT no Google", final: false, at: 1)
      for tick in 11...25 { session.observe(decibels: -20, duration: 0.1, at: Double(tick) / 10) }
      for tick in 26...41 { session.observe(decibels: -42, duration: 0.1, at: Double(tick) / 10) }
      #expect(
        session.decision(at: 4.1) == .endAudio,
        "Trailing microphone noise must not keep listening forever")

      session.start(at: 0)
      session.recognize("Pesquise por ChatGPT no Google", final: true, at: 1)
      #expect(
        session.decision(at: 1) == .endAudio, "An authoritative final result must finish capture")
    }

    @Test("G02.03 forty seconds of speech retain final words and dispatch once")
    func longSpeech() throws {
      var session = VoiceCommandSession()
      session.start(at: 0)
      session.recognize("pesquisa no Google", final: false, at: 0.1)
      // Speech continues for forty seconds, even when the transcript stalls.
      for tick in 1...400 {
        let time = Double(tick) / 10
        session.observe(decibels: -26, duration: 0.1, at: time)
        #expect(session.decision(at: time) == .wait)
      }
      for tick in 401...413 {
        let time = Double(tick) / 10
        session.observe(decibels: -72, duration: 0.1, at: time)
        #expect(session.decision(at: time) == .wait)
      }
      session.observe(decibels: -72, duration: 0.1, at: 41.5)
      #expect(session.decision(at: 41.5) == .endAudio)
      session.endAudio(at: 41.5)
      let observed1 = session.takeFinalCommand()
      #expect(observed1 == nil)  // No partial dispatch.
      session.recognize("pesquisa no Google sobre animações fluidas", final: true, at: 42)
      let observed2 = session.takeFinalCommand()
      #expect(observed2 == "pesquisa no Google sobre animações fluidas")
      let observed3 = session.takeFinalCommand()
      #expect(observed3 == nil)  // Exactly once.
    }

    @Test("G02.04 short pauses, cancellation, input loss and time limits")
    func timeouts() throws {
      var session = VoiceCommandSession()
      session.start(at: 0)
      for tick in 1...10 { session.observe(decibels: -42, duration: 0.1, at: Double(tick) / 10) }
      for tick in 11...20 { session.observe(decibels: -80, duration: 0.1, at: Double(tick) / 10) }
      #expect(session.decision(at: 2) == .wait)
      session.observe(decibels: -42, duration: 0.1, at: 2.1)
      #expect(session.decision(at: 2.3) == .wait)
      session.cancel()
      session.recognize("open Safari", final: true, at: 3)
      let observed4 = session.takeFinalCommand()
      #expect(observed4 == nil)
      session.start(at: 4)
      #expect(session.transcript.isEmpty)
      #expect(session.decision(at: 7.1) == .inputLost)

      session.start(at: 0)
      for tick in 1...120 { session.observe(decibels: -65, duration: 0.1, at: Double(tick) / 10) }
      #expect(session.decision(at: 12) == .noSpeech)
      session.start(at: 0)
      for tick in 1...550 { session.observe(decibels: -25, duration: 0.1, at: Double(tick) / 10) }
      #expect(session.decision(at: 55) == .limitReached)
      let observed5 = session.takeFinalCommand()
      #expect(observed5 == nil)
      session.endAudio(at: 55)
      #expect(session.decision(at: 59.1) == .finalResultTimedOut)
    }

    @Test("G02.05 short final closes recognition in order exactly once")
    @MainActor func drain() throws {
      var session = VoiceCommandSession()
      session.start(at: 0)
      session.recognize("open", final: true, at: 0.1)
      session.observe(decibels: -25, duration: 0.1, at: 0.4)
      #expect(session.decision(at: 0.4) == .endAudio)
      session.endAudio(at: 0.4)
      let observed6 = session.takeFinalCommand()
      #expect(observed6 == "open")
      let observed7 = session.takeFinalCommand()
      #expect(observed7 == nil)

      var drain = SpeechRecognitionDrain()
      var drainCalls: [String] = []
      drain.finish(
        endAudio: { drainCalls.append("endAudio") },
        finishTask: { drainCalls.append("task.finish") })
      drain.finish(
        endAudio: { drainCalls.append("duplicate endAudio") },
        finishTask: { drainCalls.append("duplicate finish") })
      #expect(
        drainCalls == ["endAudio", "task.finish"],
        "Drain must close the request and finish the recognizer, in order, once")
    }

    @Test("G02.06 quiet voice, settling and bounded recovery")
    func quietSpeechAndRecovery() throws {
      var session = VoiceCommandSession()
      session.start(at: 0)
      for tick in 1...20 { session.observe(decibels: -80, duration: 0.1, at: Double(tick) / 10) }
      session.recognize("voz baixa", final: false, at: 2)
      for tick in 21...150 { session.observe(decibels: -58, duration: 0.1, at: Double(tick) / 10) }
      #expect(session.decision(at: 15) == .wait)

      session.start(at: 0)
      session.recognize("pesquisa github", final: false, at: 0.1)
      session.endAudio(at: 2)
      let observed8 = session.takeSettledSearchText(at: 3)
      #expect(observed8 == nil)
      session.recognize("pesquisa github actions", final: false, at: 5.7)
      #expect(session.decision(at: 6) == .wait, "New trailing words must be allowed to settle")
      let observed9 = session.takeSettledSearchText(at: 6)
      #expect(observed9 == nil)
      let observed10 = session.takeSettledSearchText(at: 7.2)
      #expect(observed10 == "pesquisa github actions")
      let observed11 = session.takeSettledSearchText(at: 7.2)
      #expect(observed11 == nil)
      session.start(at: 10)
      session.recognize("pesquisa cancelada", final: false, at: 10.1)
      session.cancel()
      let observed12 = session.takeSettledSearchText(at: 20)
      #expect(observed12 == nil)

      var recovery = VoiceInputRecovery()
      let observed13 = recovery.retry(hasSpeech: false)
      #expect(observed13)
      let observed14 = recovery.retry(hasSpeech: false)
      #expect(!observed14)
      recovery = VoiceInputRecovery()
      let observed15 = recovery.retry(hasSpeech: true)
      #expect(!observed15)
    }

  }
}
