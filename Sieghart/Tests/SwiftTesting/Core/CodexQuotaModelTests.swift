import Dispatch
import Foundation
import Testing

private let coreQuotaModelJSON = """
  {"rateLimits":{"limitId":"codex","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":36,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":33,"windowDurationMins":10080,"resetsAt":1800600000}}}}
  """

extension MacContractsTests {
  @Suite(.tags(.usage, .isolated)) @MainActor
  struct CodexQuotaModelTests {
    @Test("G06.04 opt-in, disconnect cleanup and redacted errors")
    func quotaConsent() async throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let response = try JSONDecoder().decode(
        CodexUsageResponse.self, from: Data(coreQuotaModelJSON.utf8))
      let model = CodexUsageViewModel(defaults: defaults, load: { response })
      #expect(!model.enabled && model.bucket == nil)
      model.enabled = true
      await model.refresh(force: true)
      #expect(model.bucket?.primary?.usedPercent == 36 && model.updatedAt != nil)
      model.enabled = false
      #expect(model.bucket == nil && model.updatedAt == nil)
      let failing = CodexUsageViewModel(
        defaults: defaults, load: { throw NSError(domain: "SECRET_TOKEN", code: 1) })
      failing.enabled = true
      await failing.refresh(force: true)
      #expect(failing.bucket == nil && !(failing.errorMessage ?? "").contains("SECRET_TOKEN"))
    }

    @Test("G06.05 disconnect rejects a response held behind a fixture barrier")
    func lateQuota() async throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let response = try JSONDecoder().decode(
        CodexUsageResponse.self, from: Data(coreQuotaModelJSON.utf8))

      let signal = AsyncStream<Void>.makeStream()
      let release = DispatchSemaphore(value: 0)
      let delayed = CodexUsageViewModel(
        defaults: defaults,
        load: {
          signal.continuation.yield(())
          release.wait()
          return response
        })
      delayed.enabled = true
      let request = Task { await delayed.refresh(force: true) }
      var iterator = signal.stream.makeAsyncIterator()
      _ = await iterator.next()
      delayed.enabled = false
      release.signal()
      await request.value
      signal.continuation.finish()
      #expect(delayed.bucket == nil && delayed.updatedAt == nil && delayed.errorMessage == nil)
    }

  }
}
