import Combine
import Foundation

struct CompanionRoutine: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case research, briefing }
    var id = UUID()
    var title: String
    var kind: Kind
    var prompt: String
    var hour: Int
    var minute: Int
    var timezone: String
    var language: String
    var enabled = false
    var nextRun: Date
    var lastRun: Date? = nil
    var status = ""
    var failures = 0
    var valid: Bool { !title.isEmpty && title.count <= 100 && !prompt.isEmpty && prompt.utf8.count <= 4000 && (0...23).contains(hour) && (0...59).contains(minute) && TimeZone(identifier: timezone) != nil && failures >= 0 }
    func following(_ date: Date) -> Date? {
        guard valid, let timezone = TimeZone(identifier: timezone) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timezone
        return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}

/// Opt-in daily read-only work while the app is open. No routine is created or
/// enabled by the model, and late wakeups coalesce into one scheduled execution.
@MainActor final class CompanionRoutines: ObservableObject {
    @Published private(set) var items: [CompanionRoutine] = []
    @Published private(set) var activeID: UUID?
    @Published private(set) var issue: String?
    var execute: (@MainActor (CompanionRoutine) async throws -> Void)?
    private let defaults: UserDefaults?
    private let key = "sieg.routines.v1"
    private var storageValid = true
    private var timer: Task<Void, Never>?
    private var task: Task<Void, Never>?
    private var running = false
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: key) {
            guard data.count <= 300_000, let values = try? JSONDecoder().decode([CompanionRoutine].self, from: data), values.count <= 20, values.allSatisfy(\.valid), Set(values.map(\.id)).count == values.count else {
                storageValid = false; issue = "As rotinas salvas não puderam ser lidas. Os dados foram preservados."; return
            }
            items = values
        }
    }
    func add(_ routine: CompanionRoutine) {
        guard routine.valid, items.count < 20, storageValid else { return }
        var value = routine; value.enabled = false
        items.append(value); persist(); refreshTimer()
    }
    func setEnabled(_ id: UUID, _ enabled: Bool, now: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }), storageValid else { return }
        if activeID == id, !enabled { cancelActive() }
        items[index].enabled = enabled
        if enabled, let next = items[index].following(now) { items[index].nextRun = next; items[index].failures = 0 }
        persist(); refreshTimer()
    }
    func start() { running = true; refreshTimer() }
    func stop() { running = false; timer?.cancel(); timer = nil; cancelActive() }
    func tick(now: Date = Date()) {
        guard running, activeID == nil, let routine = items.filter({ $0.enabled && $0.nextRun <= now }).min(by: { $0.nextRun < $1.nextRun }) else { return }
        run(routine.id, scheduled: true, now: now)
    }
    func cancelRun() { cancelActive() }
    func runNow(_ id: UUID) { run(id, scheduled: false, now: Date()) }
    private func run(_ id: UUID, scheduled: Bool, now: Date) {
        guard activeID == nil, storageValid, let index = items.firstIndex(where: { $0.id == id }), let execute else { return }
        let routine = items[index]; activeID = id
        if scheduled, let next = routine.following(now) { items[index].nextRun = next }
        items[index].status = routine.language.hasPrefix("en") ? "Working…" : "Em andamento…"; persist()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.activeID == id { self.activeID = nil; self.task = nil } }
            do {
                try await execute(routine); try Task.checkCancellation()
                guard self.activeID == id, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[index].lastRun = now; self.items[index].failures = 0
                self.items[index].status = routine.language.hasPrefix("en") ? "Saved in your library." : "Resultado salvo na biblioteca."
            } catch {
                guard self.activeID == id, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[index].failures += 1
                self.items[index].status = error.localizedDescription
                if self.items[index].failures >= 3 { self.items[index].enabled = false }
            }
            self.persist()
        }
    }
    private func cancelActive() {
        if let activeID, let index = items.firstIndex(where: { $0.id == activeID }) { items[index].status = "Pausada" }
        task?.cancel(); task = nil; activeID = nil; persist()
    }
    private func refreshTimer() {
        timer?.cancel(); timer = nil
        guard running, items.contains(where: \.enabled) else { return }
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    private func persist() {
        guard storageValid, let defaults, let data = try? JSONEncoder().encode(items), data.count <= 300_000 else { return }
        defaults.set(data, forKey: key)
    }
}
