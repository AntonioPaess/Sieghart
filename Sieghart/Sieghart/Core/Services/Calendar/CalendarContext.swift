import AppKit
import EventKit
import Foundation
import UserNotifications

enum CalendarAccessState: Equatable {
    case notDetermined, writeOnly, fullAccess, denied, restricted
    var title: String {
        switch self {
        case .notDetermined: "Calendar access not requested"
        case .writeOnly: "Calendar read access required"
        case .fullAccess: "Calendar access granted"
        case .denied: "Calendar access denied"
        case .restricted: "Calendar access restricted"
        }
    }
}

struct CalendarSource: Identifiable, Equatable {
    let id: String
    let title: String
    let color: NSColor
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.title == rhs.title }
}

struct CalendarEventSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarID: String
    let calendarTitle: String
    let isAllDay: Bool
    let url: URL?
    var hasLink: Bool { url != nil }
    var relativeStart: String {
        let minutes = Int(ceil(startDate.timeIntervalSinceNow / 60))
        if minutes <= 0 { return "Now" }
        if minutes == 1 { return "In 1 minute" }
        if minutes < 60 { return "In \(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "In 1 hour" : "In \(hours) hours"
    }
}

struct CalendarSnapshot {
    let events: [CalendarEventSummary]
    let calendars: [CalendarSource]
    let fetchedAt: Date
}

@MainActor
protocol CalendarReading {
    var accessState: CalendarAccessState { get }
    func requestAccess() async throws -> Bool
    func load(from start: Date, to end: Date, selectedIDs: Set<String>?) -> CalendarSnapshot
}

@MainActor
final class EventKitCalendarReader: CalendarReading {
    private let store = EKEventStore()
    var accessState: CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
    func load(from start: Date, to end: Date, selectedIDs: Set<String>?) -> CalendarSnapshot {
        let sources = store.calendars(for: .event)
        let included = sources.filter { selectedIDs?.contains($0.calendarIdentifier) ?? true }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: included))
            .filter { $0.endDate > start && $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEventSummary(id: event.eventIdentifier ?? "\(event.calendar.calendarIdentifier)-\(event.startDate.timeIntervalSince1970)-\(event.title ?? "")",
                    title: event.title?.isEmpty == false ? event.title! : "Untitled event", startDate: event.startDate,
                    endDate: event.endDate, calendarID: event.calendar.calendarIdentifier, calendarTitle: event.calendar.title,
                    isAllDay: event.isAllDay, url: Self.webURL(event.url) ?? Self.firstURL(event.location) ?? Self.firstURL(event.notes))
            }
        return CalendarSnapshot(events: events, calendars: sources.map { CalendarSource(id: $0.calendarIdentifier, title: $0.title, color: $0.color) }, fetchedAt: Date())
    }
    private static func webURL(_ url: URL?) -> URL? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    private static func firstURL(_ text: String?) -> URL? {
        guard let text else { return nil }
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let candidate = token.trimmingCharacters(in: .punctuationCharacters)
            if let url = webURL(URL(string: candidate)) { return url }
        }
        return nil
    }
}

struct SieghartReminder: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var dueDate: Date
    var completed = false
    var snoozedUntil: Date?
    var effectiveDate: Date { snoozedUntil ?? dueDate }
}

@MainActor
protocol ReminderNotifying {
    func schedule(_ reminder: SieghartReminder, enabled: Bool, quietStart: Int, quietEnd: Int) async
    func cancel(_ id: UUID)
    func scheduleEvent(_ event: CalendarEventSummary, key: String, at due: Date, quietStart: Int, quietEnd: Int) async
    func cancelEvents(_ keys: Set<String>)
}

@MainActor
final class LocalReminderNotifier: ReminderNotifying {
    private let center = UNUserNotificationCenter.current()
    func schedule(_ reminder: SieghartReminder, enabled: Bool, quietStart: Int, quietEnd: Int) async {
        cancel(reminder.id)
        guard enabled, !reminder.completed else { return }
        let now = Date()
        guard let due = Self.scheduledDate(for: reminder.effectiveDate, now: now, quietStart: quietStart, quietEnd: quietEnd) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Sieghart reminder"
        content.body = reminder.title
        content.userInfo = ["reminderID": reminder.id.uuidString]
        content.categoryIdentifier = "sieghart.schedule"
        try? await center.add(UNNotificationRequest(identifier: reminder.id.uuidString, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, due.timeIntervalSinceNow), repeats: false)))
    }
    func scheduleEvent(_ event: CalendarEventSummary, key: String, at due: Date, quietStart: Int, quietEnd: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [key])
        let now = Date()
        guard due > now else { return }
        let hour = Calendar.current.component(.hour, from: due)
        let quiet = quietStart != quietEnd && (quietStart < quietEnd ? (hour >= quietStart && hour < quietEnd) : (hour >= quietStart || hour < quietEnd))
        guard !quiet else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Upcoming event"
        content.body = event.title
        content.userInfo = ["calendarEventKey": key]
        content.categoryIdentifier = "sieghart.schedule"
        try? await center.add(UNNotificationRequest(identifier: key, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, due.timeIntervalSinceNow), repeats: false)))
    }
    func cancelEvents(_ keys: Set<String>) { center.removePendingNotificationRequests(withIdentifiers: Array(keys)) }
    static func scheduledDate(for due: Date, now: Date, quietStart: Int, quietEnd: Int, calendar: Calendar = .current) -> Date? {
        guard due > now else { return nil }
        guard quietStart != quietEnd, (0..<24).contains(quietStart), (0..<24).contains(quietEnd) else { return due }
        let hour = calendar.component(.hour, from: due)
        let quiet = quietStart < quietEnd ? (hour >= quietStart && hour < quietEnd) : (hour >= quietStart || hour < quietEnd)
        guard quiet else { return due }
        let targetDay = quietStart > quietEnd && hour >= quietStart ? calendar.date(byAdding: .day, value: 1, to: due) ?? due : due
        return calendar.date(bySettingHour: quietEnd, minute: 0, second: 0, of: targetDay) ?? due
    }
    func cancel(_ id: UUID) { center.removePendingNotificationRequests(withIdentifiers: [id.uuidString]) }
    func requestAccess() async -> Bool { (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false }
    static func registerActions() {
        let actions = [UNNotificationAction(identifier: "sieghart.snooze", title: "Snooze 10 minutes"),
                       UNNotificationAction(identifier: "sieghart.dismiss", title: "Dismiss")]
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: "sieghart.schedule", actions: actions, intentIdentifiers: [], options: [])])
    }
}
