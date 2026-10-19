import Foundation
import Combine
import UserNotifications

struct CompanionTaskEvent: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case fileReceived, fileReady, downloadReady, captureReady, captureRead, reminderAdded, calendarDue, reminderDue, failed
    }
    var id = UUID()
    var key: String
    var kind: Kind
    var title: String
    var detail: String
    var createdAt: Date
    var quiet: Bool
    var owner: CompanionAvatar {
        switch kind {
        case .reminderAdded, .calendarDue, .reminderDue: .gantt
        case .fileReceived, .fileReady, .downloadReady, .captureReady, .captureRead, .failed: .toni
        }
    }
    var animation: CompanionAnimation {
        switch kind {
        case .fileReceived, .captureReady: .fileReceive
        case .downloadReady, .fileReady: .completed
        case .calendarDue, .reminderDue: .alert
        case .reminderAdded, .captureRead: .understood
        case .failed: .failure
        }
    }
    var module: CompanionNotificationModule {
        switch kind {
        case .downloadReady: .downloads
        case .captureReady, .captureRead: .capture
        case .reminderAdded, .calendarDue, .reminderDue: .calendar
        default: .files
        }
    }
}
enum CompanionNotificationModule: String, CaseIterable, Identifiable {
    case files = "Files", downloads = "Downloads", capture = "Capture", calendar = "Calendar"
    var id: String { rawValue }
}
@MainActor protocol CompanionTaskNotifying {
    func post(_ event: CompanionTaskEvent) async
    func requestAccess() async -> Bool
}
@MainActor final class SilentCompanionTaskNotifier: CompanionTaskNotifying {
    func post(_ event: CompanionTaskEvent) async {}
    func requestAccess() async -> Bool { false }
}
@MainActor final class LocalCompanionTaskNotifier: CompanionTaskNotifying {
    func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    func post(_ event: CompanionTaskEvent) async {
        guard !event.quiet else { return }
        let center = UNUserNotificationCenter.current(), settings = await center.notificationSettings()
        guard !Task.isCancelled else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent(); content.title = event.title; content.body = event.detail
        content.userInfo = ["siegTaskModule": event.module.rawValue]
        try? await center.add(UNNotificationRequest(identifier: "sieghart.task." + event.id.uuidString, content: content, trigger: nil))
    }
}

@MainActor final class CompanionEventCenter: ObservableObject {
    @Published private(set) var latest: CompanionTaskEvent?
    @Published private(set) var recent: [CompanionTaskEvent] = []
    @Published private(set) var notificationModules: Set<String>
    @Published private(set) var status = "Task notifications are optional"
    var onEvent: ((CompanionTaskEvent) -> Void)?
    private let defaults: UserDefaults
    private let notifier: any CompanionTaskNotifying
    private let now: () -> Date
    private var seen: [String]
    private var notificationTasks: [UUID: (CompanionNotificationModule, Task<Void, Never>)] = [:]
    init(defaults: UserDefaults = .standard, notifier: any CompanionTaskNotifying = LocalCompanionTaskNotifier(), now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.notifier = notifier; self.now = now
        notificationModules = Set(defaults.stringArray(forKey: "tasks.notifications") ?? [])
        seen = defaults.stringArray(forKey: "tasks.seen") ?? []
    }
    func notificationsEnabled(_ module: CompanionNotificationModule) -> Bool { notificationModules.contains(module.rawValue) }
    func setNotifications(_ enabled: Bool, for module: CompanionNotificationModule) {
        if enabled { notificationModules.insert(module.rawValue) } else { notificationModules.remove(module.rawValue) }
        defaults.set(Array(notificationModules).sorted(), forKey: "tasks.notifications")
        if !enabled {
            for pending in notificationTasks.values where pending.0 == module { pending.1.cancel() }
        }
    }
    var pendingNotificationCount: Int { notificationTasks.count }
    /// Waits for the deliveries already enqueued by this center, including
    /// canceled deliveries whose tasks still need to release their state.
    func waitForNotificationDelivery() async {
        let pending = notificationTasks.values.map(\.1)
        for task in pending { await task.value }
    }
    func requestNotificationAccess() {
        Task { status = await notifier.requestAccess() ? "Notifications allowed" : "Enable Sieghart notifications in System Settings" }
    }
    @discardableResult func post(_ kind: CompanionTaskEvent.Kind, key: String, title: String, detail: String) -> Bool {
        guard !seen.contains(key) else { return false }
        seen.append(key); seen = Array(seen.suffix(128)); defaults.set(seen, forKey: "tasks.seen")
        let date = now(), start = defaults.object(forKey: "calendar.quietStart") as? Int ?? 22,
            end = defaults.object(forKey: "calendar.quietEnd") as? Int ?? 8
        let hour = Calendar.current.component(.hour, from: date)
        let quiet = start != end && (start < end ? hour >= start && hour < end : hour >= start || hour < end)
        let event = CompanionTaskEvent(key: key, kind: kind, title: title, detail: detail, createdAt: date, quiet: quiet)
        recent.insert(event, at: 0); recent = Array(recent.prefix(20)); latest = event; onEvent?(event)
        // Calendar due notifications already have stable native identifiers.
        // Their delivery can drive reactions without posting a second alert.
        if notificationsEnabled(event.module), ![.calendarDue, .reminderDue, .reminderAdded].contains(kind) {
            let task = Task { [weak self] in
                defer { self?.notificationTasks[event.id] = nil }
                guard let self, !Task.isCancelled, self.notificationsEnabled(event.module) else { return }
                await self.notifier.post(event)
            }
            notificationTasks[event.id] = (event.module, task)
        }
        return true
    }
    func clearCards() { recent = [] }
    func dismissCard(_ id: UUID) { recent.removeAll { $0.id == id } }
}
