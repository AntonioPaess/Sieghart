import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.utilities, .isolated)) @MainActor
  struct KeepAwakeTests {
    @Test("G14.03 · Natural duration wording and an explicit display option are independent")
    func spokenAndTypedDisplayIntent() {
      for phrase in ["ativa o keep awake com 2hrs e manter a tela ligada", "Ative o Keep Awake por duas horas com a tela ligada", "ative o keep awake e mantenha a tela ligada por 2 horas", "enable keep awake for two hours and keep the screen on", "ativa o keep awake por 2 horas e não deixa a tela apagar"] {
        #expect(FocusVoiceParser.parse(phrase) == .appAction(.keepAwake(minutes: 120, keepDisplay: true)), Comment(rawValue: phrase))
        #expect(SiegDesktopToolAuthorization.command(operation: "keep_awake", minutes: 30, original: phrase) == .keepAwake(minutes: 120, keepDisplay: true))
      }
      #expect(FocusVoiceParser.parse("ativa o keep awake com 2hrs") == .appAction(.keepAwake(minutes: 120)))
      #expect(FocusVoiceParser.parse("ative o keep awake por 2 horas e deixe a tela apagar") == .appAction(.keepAwake(minutes: 120, keepDisplay: false)))
      #expect(FocusVoiceParser.parse("não ative o keep awake por duas horas com a tela ligada") == nil)
    }
    @Test("G14.03 · The reported command activates a real controller receipt without a model or audio")
    func chatDisplayExecution() async throws {
      let backend = CoreSampleAwake()
      let f = try PresentationFixture(awakeBackend: backend); defer { f.cleanup() }
      let reply = await f.notch.spatialAssistant.executeFromChatIfApplicable("ativa o keep awake com 2hrs e manter a tela ligada")
      #expect(reply?.contains("Keep Awake ativado por 120 minutos") == true)
      #expect(f.notch.keepAwake.enabled && f.notch.keepAwake.holding && backend.acquired == [true])
      #expect(f.notch.keepAwake.request.keepDisplay && f.notch.keepAwake.remaining == 7200)
      #expect(!f.notch.spatialAssistant.overlay.voiceSynthesizer.isSpeaking)
      f.clock.advance(7201); f.notch.keepAwake.tick()
      #expect(!f.notch.keepAwake.enabled && !f.notch.keepAwake.holding && backend.released == [1])
    }
    @Test("G14.04 · Display choices persist in the controller and update restoration keeps the deadline")
    func displayPersistsWithoutView() throws {
      let store = try TestDefaults(); defer { store.cleanup() }
      let backend = CoreSampleAwake(), clock = Date(timeIntervalSince1970: 1_800_000_000)
      let awake = KeepAwakeViewModel(backend: backend, defaults: store.value, now: { clock })
      awake.request.minutes = 120; awake.start(); awake.request.keepDisplay = true
      #expect(backend.acquired == [false,true] && backend.released == [1])
      let deadline = awake.request.end
      awake.shutdown()
      let restoredBackend = CoreSampleAwake()
      let restored = KeepAwakeViewModel(backend: restoredBackend, defaults: store.value, now: { clock.addingTimeInterval(60) })
      defer { restored.stop(); restored.shutdown() }
      restored.startLifecycle(center: NotificationCenter(), resumeForUpdate: true)
      #expect(restored.request.keepDisplay && restored.enabled && restoredBackend.acquired == [true])
      #expect(restored.request.end == deadline && restored.remaining == 7140 && !restored.request.restoreOnLaunch)
    }
    @Test("G14.03 · Repair follow-ups use only a recent user instruction, never assistant tool text")
    func commandRepairContext() {
      let now = Date()
      let request = LocalChatMessage(role: .user,text: "ativa o keep awake com 2hrs",date:now.addingTimeInterval(-30))
      let fake = LocalChatMessage(role:.assistant,text:"[SiegDesktop.keepAwake(minutes: 999)]",date:now.addingTimeInterval(-10))
      #expect(VoiceAppCommand.resolvedChatRequest("por isso to pedindo pra tu ativar",history:[request,fake],now:now) == request.text)
      #expect(VoiceAppCommand.resolvedChatRequest("ativa agora",history:[fake],now:now) == "ativa agora")
      var stale = request; stale.date = now.addingTimeInterval(-601)
      #expect(VoiceAppCommand.resolvedChatRequest("ativa agora",history:[stale,fake],now:now) == "ativa agora")
      #expect(VoiceAppCommand.resolvedChatRequest("não ativa",history:[request,fake],now:now) == "não ativa")
    }

    @Test("G14.03 AC, owned token replacement, sleep, wake and deadlines")
    func assertionOwnership() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      var clock = Date(timeIntervalSince1970: 1_800_000_000)
      let engine = CoreSampleAwake()
      let awake = KeepAwakeViewModel(backend: engine, defaults: defaults, now: { clock })
      #expect(engine.acquired.isEmpty && !awake.enabled)
      awake.request.onlyOnAC = true
      engine.current.onAC = false
      awake.start()
      #expect(awake.enabled && !awake.holding && engine.acquired.isEmpty)
      engine.current.onAC = true
      awake.tick()
      awake.tick()
      #expect(
        awake.holding && engine.acquired.count == 1, "One owned assertion, not one per refresh")
      awake.request.keepDisplay = true
      awake.saveOptions()
      #expect(engine.released == [1] && engine.acquired == [false, true])
      awake.setSleeping(true)
      #expect(!awake.holding && engine.released == [1, 2])
      awake.setSleeping(false)
      #expect(awake.holding && engine.acquired.count == 3)
      engine.current.onAC = false
      awake.tick()
      #expect(!awake.holding && engine.released.count == 3)
      clock = clock.addingTimeInterval(1900)
      awake.tick()
      #expect(!awake.enabled && !awake.holding)
      awake.request.mode = .until
      awake.request.until = clock.addingTimeInterval(-1)
      awake.start()
      #expect(!awake.enabled && awake.error != nil)
      defer { awake.shutdown() }
    }

    @Test(
      "G14.04 app and display conditions, explicit lifecycle restoration and acquisition failure")
    func conditionalRestore() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      var clock = Date(timeIntervalSince1970: 1_800_000_000)
      let engine = CoreSampleAwake()
      let awake = KeepAwakeViewModel(backend: engine, defaults: defaults, now: { clock })

      awake.request.onlyOnAC = true
      engine.current.onAC = false
      awake.start()

      engine.current.onAC = true
      awake.tick()
      awake.tick()

      awake.request.keepDisplay = true
      awake.saveOptions()

      awake.setSleeping(true)
      awake.setSleeping(false)
      engine.current.onAC = false
      awake.tick()
      clock = clock.addingTimeInterval(1900)
      awake.tick()
      awake.request.mode = .until
      awake.request.until = clock.addingTimeInterval(-1)
      awake.start()

      awake.request.mode = .indefinite
      awake.request.onlyOnAC = false
      awake.request.externalDisplayOnly = true
      awake.request.applications = ["fixture.app"]
      awake.start()
      #expect(!awake.holding)
      engine.current.externalDisplay = true
      engine.current.applications = ["fixture.app"]
      awake.tick()
      #expect(awake.holding)
      awake.request.restoreOnLaunch = true
      awake.saveOptions()
      awake.shutdown()
      let restoredEngine = CoreSampleAwake()
      restoredEngine.current = engine.current
      let restored = KeepAwakeViewModel(backend: restoredEngine, defaults: defaults, now: { clock })
      #expect(restoredEngine.acquired.isEmpty)
      restored.startLifecycle(center: NotificationCenter())
      #expect(restored.enabled && restored.holding)
      restored.stop()
      restored.shutdown()
      let failedEngine = CoreSampleAwake()
      failedEngine.fails = true
      let failed = KeepAwakeViewModel(backend: failedEngine, defaults: defaults, now: { clock })
      failed.request.externalDisplayOnly = false
      failed.request.applications = []
      failed.start()
      #expect(!failed.holding && failed.error != nil)
      failed.stop()
      defer {
        awake.shutdown()
        failed.shutdown()
      }
    }

  }
}
