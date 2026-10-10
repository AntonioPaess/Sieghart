import AppKit
import Combine
import EventKit
import Foundation

@MainActor
final class CalendarViewModel: ObservableObject {
    enum Span: String, CaseIterable { case day = "Day", week = "Week", month = "Month" }
    @Published private(set) var accessState: CalendarAccessState = .notDetermined
    @Published private(set) var events: [CalendarEventSummary] = []
    @Published private(set) var nextEvent: CalendarEventSummary?
    @Published private(set) var calendars: [CalendarSource] = []
    @Published private(set) var reminders: [SieghartReminder] = []
    @Published private(set) var status = "Calendar access not requested"
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var span: Span = .week { didSet { refresh() } }
    @Published var selectedDate = Date() { didSet { refresh() } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "calendar.notifications"); rescheduleReminders() } }
    @Published var quietStart: Int { didSet { defaults.set(quietStart, forKey: "calendar.quietStart"); rescheduleReminders() } }
    @Published var quietEnd: Int { didSet { defaults.set(quietEnd, forKey: "calendar.quietEnd"); rescheduleReminders() } }
    private let reader: CalendarReading
    private let notifier: ReminderNotifying
    private let defaults: UserDefaults
    private var excludedIDs: Set<String>
    private var activationObserver: AnyCancellable?
    private var storeChangeObserver: AnyCancellable?

    init(reader: CalendarReading = EventKitCalendarReader(), notifier: ReminderNotifying = LocalReminderNotifier(), defaults: UserDefaults = .standard, observesSystem: Bool = true) {
        self.reader = reader; self.notifier = notifier; self.defaults = defaults
        self.excludedIDs = Set(defaults.stringArray(forKey: "calendar.excludedIDs") ?? [])
        self.notificationsEnabled = defaults.bool(forKey: "calendar.notifications")
        self.quietStart = defaults.object(forKey: "calendar.quietStart") as? Int ?? 22
        self.quietEnd = defaults.object(forKey: "calendar.quietEnd") as? Int ?? 8
        if let data = defaults.data(forKey: "calendar.reminders"), let saved = try? JSONDecoder().decode([SieghartReminder].self, from: data) { reminders = saved }
        accessState = reader.accessState; status = accessState.title
        rescheduleReminders()
        if observesSystem {
            activationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).receive(on: RunLoop.main).sink { [weak self] _ in self?.prepare() }
            storeChangeObserver = NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: RunLoop.main).sink { [weak self] _ in self?.prepare() }
        }
    }

    var visibleReminders: [SieghartReminder] { reminders.filter { !$0.completed }.sorted { $0.effectiveDate < $1.effectiveDate } }
    var accessButtonLabel: String {
        switch accessState {
        case .notDetermined, .writeOnly: "Connect calendar"
        case .fullAccess: "Refresh calendar"
        case .denied, .restricted: "Open calendar settings"
        }
    }
    func isSelected(_ id: String) -> Bool { !excludedIDs.contains(id) }
    func setSelected(_ selected: Bool, id: String) {
        if selected { excludedIDs.remove(id) } else { excludedIDs.insert(id) }
        defaults.set(Array(excludedIDs).sorted(), forKey: "calendar.excludedIDs")
        refresh()
    }
    func prepare() {
        accessState = reader.accessState
        if accessState == .fullAccess { refresh() }
        else { events = []; nextEvent = nil; calendars = []; lastUpdated = nil; status = accessState.title }
    }
    func requestAccessAndRefresh() {
        guard !isRequestingAccess else { return }
        accessState = reader.accessState
        switch accessState {
        case .fullAccess: refresh()
        case .denied, .restricted: openCalendarSettings()
        case .notDetermined, .writeOnly:
            isRequestingAccess = true; status = "Waiting for Calendar permission..."
            NSApp.activate(ignoringOtherApps: true)
            Task {
                do {
                    let granted = try await reader.requestAccess()
                    accessState = reader.accessState
                    if granted && accessState == .fullAccess { refresh() }
                    else { status = accessState.title }
                } catch { status = "Calendar permission request failed: \(error.localizedDescription)" }
                isRequestingAccess = false
            }
        }
    }
    func refresh() {
        accessState = reader.accessState
        guard accessState == .fullAccess else { events = []; nextEvent = nil; calendars = []; status = accessState.title; return }
        isLoading = true
        let range = dateRange()
        let snapshot = reader.load(from: range.start, to: range.end, selectedIDs: nil)
        calendars = snapshot.calendars
        events = snapshot.events.filter { !excludedIDs.contains($0.calendarID) }
        let now = Date()
        let upcoming = reader.load(from: now, to: Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now.addingTimeInterval(30 * 86_400), selectedIDs: nil)
        nextEvent = upcoming.events.first { !excludedIDs.contains($0.calendarID) && $0.endDate > now }
        lastUpdated = snapshot.fetchedAt
        isLoading = false
        status = calendars.isEmpty ? "No calendars found. Check your Calendar accounts." : events.isEmpty ? "No events in this period." : "\(events.count) events"
    }
    func shift(_ amount: Int) {
        let component: Calendar.Component = span == .day ? .day : span == .week ? .weekOfYear : .month
        selectedDate = Calendar.current.date(byAdding: component, value: amount, to: selectedDate) ?? selectedDate
    }
    func dateRange() -> DateInterval {
        let calendar = Calendar.current
        let component: Calendar.Component = span == .day ? .day : span == .week ? .weekOfYear : .month
        return calendar.dateInterval(of: component, for: selectedDate) ?? DateInterval(start: selectedDate, duration: 86_400)
    }
    func open(_ event: CalendarEventSummary) {
        guard let url = event.url else { status = "This event has no meeting link"; return }
        status = NSWorkspace.shared.open(url) ? "Opened meeting link" : "Meeting link could not be opened"
    }
    func openCalendarSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        status = NSWorkspace.shared.open(url) ? "Check Calendar access in System Settings." : "Open System Settings → Privacy & Security → Calendars"
    }
    func addReminder(title: String, due: Date) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "Enter a reminder title"; return }
        guard due > Date() else { status = "Choose a future time"; return }
        let reminder = SieghartReminder(id: UUID(), title: trimmed, dueDate: due)
        reminders.append(reminder); saveReminders(); rescheduleReminders(); status = "Reminder added"
    }
    func dismiss(_ id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].completed = true; notifier.cancel(id); saveReminders(); status = "Reminder dismissed"
    }
    func snooze(_ id: UUID, minutes: Int = 10) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].snoozedUntil = Date().addingTimeInterval(Double(minutes * 60))
        saveReminders(); rescheduleReminders(); status = "Reminder postponed"
    }
    func requestNotificationAccess() {
        guard let notifier = notifier as? LocalReminderNotifier else { return }
        Task { status = await notifier.requestAccess() ? "Notifications allowed" : "Enable notifications in System Settings"; rescheduleReminders() }
    }
    private func saveReminders() { defaults.set(try? JSONEncoder().encode(reminders), forKey: "calendar.reminders") }
    private func rescheduleReminders() {
        for reminder in reminders {
            if !notificationsEnabled || reminder.completed { notifier.cancel(reminder.id) }
            else { Task { await notifier.schedule(reminder, enabled: true, quietStart: quietStart, quietEnd: quietEnd) } }
        }
    }
}
