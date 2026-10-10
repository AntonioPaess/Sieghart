import AppKit
import Foundation

@MainActor final class FakeCalendarReader: CalendarReading {
    var accessState: CalendarAccessState = .fullAccess
    var all: [CalendarEventSummary] = []
    var lastRange: DateInterval?
    func requestAccess() async throws -> Bool { accessState = .fullAccess; return true }
    func load(from start: Date, to end: Date, selectedIDs: Set<String>?) -> CalendarSnapshot {
        lastRange = DateInterval(start: start, end: end)
        return CalendarSnapshot(events: all.filter { $0.endDate > start && $0.startDate < end },
            calendars: [CalendarSource(id: "one", title: "Work", color: .red), CalendarSource(id: "two", title: "Home", color: .blue)], fetchedAt: Date())
    }
}
@MainActor final class FakeReminderNotifier: ReminderNotifying {
    var scheduled: [UUID] = []
    var cancelled: [UUID] = []
    var eventKeys: [String] = []
    var cancelledEventKeys: Set<String> = []
    func schedule(_ reminder: SieghartReminder, enabled: Bool, quietStart: Int, quietEnd: Int) async { scheduled.append(reminder.id) }
    func scheduleEvent(_ event: CalendarEventSummary, key: String, at due: Date, quietStart: Int, quietEnd: Int) async { eventKeys.append(key) }
    func cancelEvents(_ keys: Set<String>) { cancelledEventKeys.formUnion(keys) }
    func cancel(_ id: UUID) { cancelled.append(id) }
}
@main struct CalendarChecks {
    @MainActor static func main() async {
        let suite = "sieghart.calendar.checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = FakeCalendarReader(), notifier = FakeReminderNotifier()
        let now = Date()
        reader.all = [CalendarEventSummary(id: "a", title: "Meeting", startDate: now.addingTimeInterval(1800), endDate: now.addingTimeInterval(3600), calendarID: "one", calendarTitle: "Work", isAllDay: false, url: URL(string: "https://example.com/meet")),
                      CalendarEventSummary(id: "b", title: "Home", startDate: now.addingTimeInterval(2400), endDate: now.addingTimeInterval(4200), calendarID: "two", calendarTitle: "Home", isAllDay: false, url: nil)]
        let model = CalendarViewModel(reader: reader, notifier: notifier, defaults: defaults, observesSystem: false)
        model.span = .day; model.prepare()
        precondition(model.events.count == 2 && model.nextEvent?.id == "a")
        model.setSelected(false, id: "two")
        precondition(model.events.map(\.id) == ["a"])
        model.eventAlertsEnabled = true
        await Task.yield()
        precondition(notifier.eventKeys.count >= 1)
        let eventKey = notifier.eventKeys.first!
        model.handleNotificationAction("sieghart.dismiss", reminderID: nil, eventKey: eventKey)
        precondition(model.isEventAlertDismissed(reader.all[0]))
        let reopenForAlerts = CalendarViewModel(reader: reader, notifier: notifier, defaults: defaults, observesSystem: false)
        precondition(reopenForAlerts.isEventAlertDismissed(reader.all[0]))
        model.span = .week; precondition(model.dateRange().duration >= 6 * 86_400)
        model.span = .month; precondition(model.dateRange().duration >= 28 * 86_400)
        model.notificationsEnabled = true
        model.addReminder(title: "  Call Sam  ", due: now.addingTimeInterval(7200))
        precondition(model.visibleReminders.count == 1 && model.visibleReminders[0].title == "Call Sam")
        let id = model.visibleReminders[0].id
        model.handleNotificationAction("sieghart.snooze", reminderID: id.uuidString, eventKey: nil)
        precondition(model.visibleReminders[0].snoozedUntil != nil)
        let reopened = CalendarViewModel(reader: reader, notifier: notifier, defaults: defaults, observesSystem: false)
        precondition(reopened.visibleReminders.count == 1 && !reopened.isSelected("two"))
        reopened.handleNotificationAction("sieghart.dismiss", reminderID: id.uuidString, eventKey: nil)
        precondition(reopened.visibleReminders.isEmpty && notifier.cancelled.contains(id))
        let calendar = Calendar(identifier: .gregorian)
        let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 23))!
        let quietEnd = LocalReminderNotifier.scheduledDate(for: night, now: night.addingTimeInterval(-60), quietStart: 22, quietEnd: 8, calendar: calendar)!
        precondition(calendar.component(.day, from: quietEnd) == 11 && calendar.component(.hour, from: quietEnd) == 8)
        precondition(LocalReminderNotifier.scheduledDate(for: night, now: night.addingTimeInterval(-60), quietStart: 8, quietEnd: 8, calendar: calendar) == night)
        reader.accessState = .denied; reopened.prepare()
        precondition(reopened.events.isEmpty && reopened.nextEvent == nil)
        print("Calendar checks passed")
    }
}
