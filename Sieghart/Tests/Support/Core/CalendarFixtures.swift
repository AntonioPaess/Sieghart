import AppKit
import Foundation

@MainActor final class CoreCalendarReader: CalendarReading {
  var accessState: CalendarAccessState = .fullAccess
  var events: [CalendarEventSummary] = []
  var lastRange: DateInterval?
  var onLoad: (() -> Void)?
  let now: Date
  init(now: Date) { self.now = now }
  func requestAccess() async throws -> Bool {
    accessState = .fullAccess
    return true
  }
  func load(from start: Date, to end: Date, selectedIDs: Set<String>?) -> CalendarSnapshot {
    lastRange = DateInterval(start: start, end: end)
    onLoad?()
    return CalendarSnapshot(
      events: events.filter { $0.endDate > start && $0.startDate < end },
      calendars: [
        CalendarSource(id: "one", title: "Work", color: .red),
        CalendarSource(id: "two", title: "Home", color: .blue),
      ], fetchedAt: now)
  }
}

@MainActor final class CoreReminderNotifier: ReminderNotifying {
  var scheduled: [UUID] = []
  var cancelled: [UUID] = []
  var eventKeys: [String] = []
  var cancelledEventKeys: Set<String> = []
  var onEventScheduled: (() -> Void)?
  func schedule(_ reminder: SieghartReminder, enabled: Bool, quietStart: Int, quietEnd: Int) async {
    scheduled.append(reminder.id)
  }
  func scheduleEvent(
    _ event: CalendarEventSummary, key: String, at due: Date, quietStart: Int, quietEnd: Int
  ) async {
    eventKeys.append(key)
    onEventScheduled?()
  }
  func cancelEvents(_ keys: Set<String>) { cancelledEventKeys.formUnion(keys) }
  func cancel(_ id: UUID) { cancelled.append(id) }
}

@MainActor final class CoreCalendarFixture {
  let storage: TestDefaults
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let calendar: Calendar
  let reader: CoreCalendarReader
  let notifier = CoreReminderNotifier()
  var activations = 0
  init() throws {
    storage = try TestDefaults()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    calendar.locale = Locale(identifier: "en_US_POSIX")
    self.calendar = calendar
    reader = CoreCalendarReader(now: now)
    reader.events = [
      CalendarEventSummary(
        id: "a", title: "Meeting", startDate: now.addingTimeInterval(1800),
        endDate: now.addingTimeInterval(3600), calendarID: "one", calendarTitle: "Work",
        isAllDay: false, url: URL(string: "https://example.com/meet")),
      CalendarEventSummary(
        id: "b", title: "Home", startDate: now.addingTimeInterval(2400),
        endDate: now.addingTimeInterval(4200), calendarID: "two", calendarTitle: "Home",
        isAllDay: false, url: nil),
    ]
  }
  func model() -> CalendarViewModel {
    CalendarViewModel(
      reader: reader, notifier: notifier, defaults: storage.value, observesSystem: false,
      now: { self.now }, calendar: calendar, activateApplication: { self.activations += 1 })
  }
  func cleanup() { storage.cleanup() }
}
