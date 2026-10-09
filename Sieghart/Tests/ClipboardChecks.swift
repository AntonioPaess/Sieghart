import AppKit
import Foundation

@MainActor final class FakeClipboard: ClipboardAccess {
    var count = 10
    var content: ClipboardPayload?
    var reads = 0
    var writes = 0
    var delay = false
    var failWrite = false
    func read(after previous: Int?, includeMedia: Bool) async -> ClipboardRead? {
        reads += 1
        let snapshot = ClipboardRead(changeCount: count, payload: previous == count ? nil : content)
        if delay { try? await Task.sleep(for: .milliseconds(80)) }
        return snapshot
    }
    func write(_ payload: ClipboardPayload) async -> Int? {
        guard !failWrite else { return nil }
        count += 1; writes += 1; content = payload; return count
    }
}
actor FixtureClipboardStorage: ClipboardStorage {
    var entries: [ClipboardEntry] = []
    func load() -> [ClipboardEntry] { entries }
    func save(_ entries: [ClipboardEntry], revision: UInt64) { self.entries = entries }
}
@main struct ClipboardChecks {
    @MainActor static func main() async throws {
        let suite = "Sieghart.ClipboardChecks.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_790_000_000), access = FakeClipboard(), store = FixtureClipboardStorage()
        let model = ClipboardViewModel(defaults: defaults, access: access, storage: store, monitorsSystem: false, now: { now })
        await model.restore()
        await model.poll(sourceName: "Example", sourceBundle: "example")
        precondition(access.reads == 0 && model.entries.isEmpty)
        model.isEnabled = true
        access.content = ClipboardPayload(kind: .text, text: "Copied while disabled")
        await model.poll(sourceName: "Example", sourceBundle: "example")
        precondition(model.entries.isEmpty) // enabling only establishes a baseline
        access.count += 1; access.content = ClipboardPayload(kind: .text, text: "A useful first copy")
        await model.poll(sourceName: "Editor", sourceBundle: "example.editor")
        precondition(model.entries.count == 1)
        let original = model.entries[0]
        model.togglePin(original.id)
        access.count += 1
        await model.poll(sourceName: "Browser", sourceBundle: "example.browser")
        precondition(model.entries.count == 1 && model.entries[0].id == original.id && model.entries[0].pinned)
        precondition(model.filtered(query: "USEFUL", pinnedOnly: true).count == 1)
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII=")!
        model.record(ClipboardPayload(kind: .image, image: image), sourceName: "Preview", sourceBundle: "example.preview")
        model.record(ClipboardPayload(kind: .files, files: [URL(fileURLWithPath: "/tmp/example.pdf")]), sourceName: "Finder", sourceBundle: "com.apple.finder")
        precondition(model.entries.count == 3 && model.filtered(query: "example.pdf", kind: .files).count == 1)
        precondition(model.filtered(query: "", kind: .image).count == 1)
        model.record(ClipboardPayload(kind: .text, text: "Marked source test"), sourceName: "Passwords", sourceBundle: "com.apple.Passwords")
        precondition(model.entries.count == 3)
        model.includeMedia = false
        model.record(ClipboardPayload(kind: .image, image: image), sourceName: "Preview", sourceBundle: "example.preview")
        precondition(model.entries.count == 3)
        precondition(!ClipboardPayload(kind: .files, files: [URL(string: "https://example.com")!]).valid)
        precondition(!ClipboardPayload(kind: .text, text: String(repeating: "x", count: 524289)).valid)
        precondition(!ClipboardPayload(kind: .image, image: Data([0,1,2])).valid)
        model.isPaused = true
        let reads = access.reads
        await model.poll(sourceName: "Example", sourceBundle: "example")
        precondition(access.reads == reads)
        model.isPaused = false
        await model.poll(sourceName: "Example", sourceBundle: "example")
        access.count += 1; access.content = ClipboardPayload(kind: .text, text: "Delayed copy")
        access.delay = true
        let delayed = Task { await model.poll(sourceName: "Editor", sourceBundle: "example.editor") }
        try await Task.sleep(for: .milliseconds(20)); model.isEnabled = false
        await delayed.value
        precondition(!model.entries.contains { $0.payload.text == "Delayed copy" })
        access.delay = false
        let copied = await model.copy(original)
        precondition(copied && access.writes == 1)
        model.isEnabled = true
        await model.poll(sourceName: "Example", sourceBundle: "example")
        precondition(model.entries.count == 3)
        await model.paste(original, dismiss: { preconditionFailure("Mock paste must never activate an app") })
        precondition(model.status.contains("Copied") && !model.canPaste)
        access.failWrite = true
        let failed = await model.copy(original); precondition(!failed && model.status.contains("Could not copy"))
        await model.flush()
        let restored = ClipboardViewModel(defaults: defaults, access: FakeClipboard(), storage: store, monitorsSystem: false, now: { now })
        await restored.restore(); precondition(restored.entries.count == 3 && restored.entries.contains { $0.pinned })
        model.remove(original.id); await model.flush(); precondition(!model.entries.contains { $0.id == original.id })
        model.clear(); await model.flush(); let cleared = await store.load(); precondition(cleared.isEmpty)
        var many = (0..<210).map { ClipboardEntry(payload: ClipboardPayload(kind: .text, text: "item \($0)"), copiedAt: now.addingTimeInterval(-Double($0)), sourceName: "Fixture", sourceBundle: "fixture") }
        many[209].pinned = true
        let bounded = ClipboardViewModel.bounded(many, now: now)
        precondition(bounded.count == 200 && bounded.contains { $0.pinned })
        let expired = ClipboardEntry(payload: ClipboardPayload(kind: .text, text: "Old"), copiedAt: now.addingTimeInterval(-31 * 86400), sourceName: "Fixture", sourceBundle: "fixture")
        precondition(ClipboardViewModel.bounded([expired], now: now).isEmpty)
        var pinned = expired; pinned.pinned = true
        precondition(ClipboardViewModel.bounded([pinned, pinned], now: now).count == 1)
        model.historyLimit = 5
        for index in 0..<9 { model.record(ClipboardPayload(kind: .text, text: "Limit \(index)"), sourceName: "Fixture", sourceBundle: "fixture") }
        precondition(model.entries.count == 5)
        model.cleanup = .lidClose; model.handleCleanupEvent(.shutdown); precondition(model.entries.count == 5)
        model.handleCleanupEvent(.lidClose); await model.flush(); precondition(model.entries.isEmpty)
        model.historyLimit = 10; model.cleanup = .shutdown
        model.record(ClipboardPayload(kind: .text, text: "Before restart"), sourceName: "Fixture", sourceBundle: "fixture")
        model.togglePin(model.entries[0].id); await model.flush()
        let afterBoot = ClipboardViewModel(defaults: defaults, access: FakeClipboard(), storage: store, monitorsSystem: false, now: { now }, bootTime: { ClipboardViewModel.systemBootTime() + 100 })
        await afterBoot.restore(); await afterBoot.flush(); precondition(afterBoot.entries.isEmpty && afterBoot.historyLimit == 10)
        precondition(ClipboardViewModel.bounded([expired], now: now, limit: 5, retentionDays: nil).count == 1)
        let width = CGSize(width: 610, height: 220)
        precondition(CompanionGaze.sample(point: CGPoint(x: 0, y: 110), in: width).width == -4)
        precondition(CompanionGaze.sample(point: CGPoint(x: 610, y: 110), in: width).width == 4)
        precondition(CompanionGaze.sample(point: CGPoint(x: 305, y: 110), in: width) == .zero)
        let prefs = CompanionPreferences(defaults: defaults)
        precondition(prefs.railActions.count == 6 && prefs.railActions.contains(.clipboard))
        prefs.setRail(.clipboard, at: 4)
        precondition(prefs.railActions[4] == .clipboard && Set(prefs.railActions).count == 6)
        prefs.setRail(.none, at: 0); prefs.setRail(.none, at: 1)
        precondition(prefs.railActions[0] == .none && prefs.railActions[1] == .none)
        prefs.applyRailPreset(.work)
        precondition(CompanionPreferences(defaults: defaults).railActions == IslandRailPreset.work.actions)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Sieghart-Clipboard-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let file = temporary.appendingPathComponent("history.json"), disk = LocalClipboardStorage(url: file)
        try await disk.save([pinned], revision: 2); try await disk.save([], revision: 1)
        let diskItems = try await disk.load(); precondition(diskItems == [pinned])
        let permission = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber).intValue
        precondition(permission == 0o600)
        for t in stride(from: 0.0, through: 3.5, by: 1.0 / 240) {
            let a = CompanionEntranceMotion.sample(elapsed: t), b = CompanionEntranceMotion.sample(elapsed: t + 1.0 / 240)
            precondition(a.opacity >= 0 && a.opacity <= 1 && a.eyeOpen >= 0.08 && a.eyeOpen <= 1)
            precondition(abs(a.offset - b.offset) < 0.022 && abs(a.scaleX - b.scaleX) < 0.01)
            precondition(a.scaleX >= 0.8 && a.scaleX < 1.1 && a.scaleY >= 0.8 && a.scaleY < 1.1)
        }
        let arrival = CompanionEntranceMotion.sample(elapsed: 4)
        precondition(abs(arrival.offset) < 0.001 && abs(arrival.scaleX - 1) < 0.001 && arrival.eyeOpen == 1)
        precondition(CompanionEntranceMotion.sample(elapsed: 0).opacity == 0)
        precondition(CompanionEntranceMotion.sample(elapsed: 0, reducedMotion: true) == CompanionEntranceMotion())
        print("Clipboard and arrival checks passed: baseline, capture, types, pins, search, exclusions, pause, stale reads, copy fallback, persistence, 5/10/20 limits, lid/reboot cleanup, rail presets/swaps, bilateral gaze and continuous/reduced motion. No system clipboard or apps accessed.")
    }
}
