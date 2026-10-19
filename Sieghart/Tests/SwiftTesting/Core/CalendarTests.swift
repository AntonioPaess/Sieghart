import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.calendar, .isolated)) @MainActor
  struct CalendarTests {
    @Test("G15.01 event selection, next event and dismissed alert survive reopening")
    func eventsAndAlerts() async throws {
      let f = try CoreCalendarFixture()
      defer { f.cleanup() }
      let model = f.model()
      model.span = .day
      model.prepare()
      #expect(model.events.count == 2 && model.nextEvent?.id == "a")
      model.setSelected(false, id: "two")
      #expect(model.events.map(\.id) == ["a"])
      let signal = AsyncStream<Void>.makeStream()
      f.notifier.onEventScheduled = { signal.continuation.yield(()) }
      model.eventAlertsEnabled = true
      var iterator = signal.stream.makeAsyncIterator()
      _ = await iterator.next()
      let key = try #require(f.notifier.eventKeys.first)
      model.handleNotificationAction("sieghart.dismiss", reminderID: nil, eventKey: key)
      let event = try #require(f.reader.events.first)
      #expect(model.isEventAlertDismissed(event))
      #expect(f.model().isEventAlertDismissed(event))
      signal.continuation.finish()
    }

    @Test("G15.02 fixed UTC week and month ranges retain their minimum durations")
    func ranges() throws {
      let f = try CoreCalendarFixture()
      defer { f.cleanup() }
      let model = f.model()
      model.span = .week
      #expect(model.dateRange().duration >= 6 * 86_400)
      model.span = .month
      #expect(model.dateRange().duration >= 28 * 86_400)
    }

    @Test("G15.03 trimmed reminder, snooze, filter and dismissal persist")
    func reminders() throws {
      let f = try CoreCalendarFixture()
      defer { f.cleanup() }
      let model = f.model()
      model.setSelected(false, id: "two")
      model.notificationsEnabled = true
      model.addReminder(title: "  Call Sam  ", due: f.now.addingTimeInterval(7200))
      let reminder = try #require(model.visibleReminders.first)
      #expect(model.visibleReminders.count == 1 && reminder.title == "Call Sam")
      model.handleNotificationAction(
        "sieghart.snooze", reminderID: reminder.id.uuidString, eventKey: nil)
      #expect(model.visibleReminders.first?.snoozedUntil == f.now.addingTimeInterval(600))
      let reopened = f.model()
      #expect(reopened.visibleReminders.count == 1 && !reopened.isSelected("two"))
      reopened.handleNotificationAction(
        "sieghart.dismiss", reminderID: reminder.id.uuidString, eventKey: nil)
      #expect(reopened.visibleReminders.isEmpty && f.notifier.cancelled.contains(reminder.id))
    }

    @Test("G15.05 denied access clears events and explicit fake authorization refreshes")
    func permission() async throws {
      let f = try CoreCalendarFixture()
      defer { f.cleanup() }
      let model = f.model()
      model.setSelected(false, id: "two")
      f.reader.accessState = .denied
      model.prepare()
      #expect(model.events.isEmpty && model.nextEvent == nil)
      f.reader.accessState = .notDetermined
      model.prepare()
      let signal = AsyncStream<Void>.makeStream()
      f.reader.onLoad = { signal.continuation.yield(()) }
      model.requestAccessAndRefresh()
      var iterator = signal.stream.makeAsyncIterator()
      _ = await iterator.next()
      #expect(model.accessState == .fullAccess && model.events.count == 1)
      #expect(f.activations == 1)
      signal.continuation.finish()
    }
  }
}

extension LogicTests {
  @Suite(.tags(.calendar, .logic))
  @MainActor struct QuietHoursTests {
    @Test("G15.04 quiet hours cross midnight and equal endpoints disable the interval")
    func overnight() throws {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .gmt
      let night = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 23)))
      let end = try #require(
        LocalReminderNotifier.scheduledDate(
          for: night, now: night.addingTimeInterval(-60), quietStart: 22, quietEnd: 8,
          calendar: calendar))
      #expect(
        calendar.component(.day, from: end) == 11 && calendar.component(.hour, from: end) == 8)
      #expect(
        LocalReminderNotifier.scheduledDate(
          for: night, now: night.addingTimeInterval(-60), quietStart: 8, quietEnd: 8,
          calendar: calendar) == night)
    }
  }
}
