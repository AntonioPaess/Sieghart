import AppKit
import Combine
import EventKit
import Foundation

@MainActor
final class CalendarViewModel: ObservableObject {
    var onReminderAdded: ((SieghartReminder) -> Void)?
    var onNotificationDelivered: ((String, String, Bool) -> Void)?
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
    @Published var eventAlertsEnabled: Bool { didSet { defaults.set(eventAlertsEnabled, forKey: "calendar.eventAlerts"); rescheduleEvents() } }
    @Published var eventLeadMinutes: Int { didSet { defaults.set(eventLeadMinutes, forKey: "calendar.eventLeadMinutes"); rescheduleEvents() } }
    @Published var quietStart: Int { didSet { defaults.set(quietStart, forKey: "calendar.quietStart"); rescheduleReminders(); rescheduleEvents() } }
    @Published var quietEnd: Int { didSet { defaults.set(quietEnd, forKey: "calendar.quietEnd"); rescheduleReminders(); rescheduleEvents() } }
    private let reader: CalendarReading
    private let notifier: ReminderNotifying
    private let defaults: UserDefaults
    private var excludedIDs: Set<String>
    private var scheduledEventKeys: Set<String>
    private var snoozedEventKeys: [String: Date] = [:]
    private var upcomingEventsForAlerts: [CalendarEventSummary] = []
    private var activationObserver: AnyCancellable?
    private var storeChangeObserver: AnyCancellable?

    init(reader: CalendarReading = EventKitCalendarReader(), notifier: ReminderNotifying = LocalReminderNotifier(), defaults: UserDefaults = .standard, observesSystem: Bool = true) {
        self.reader = reader; self.notifier = notifier; self.defaults = defaults
        self.excludedIDs = Set(defaults.stringArray(forKey: "calendar.excludedIDs") ?? [])
        self.notificationsEnabled = defaults.bool(forKey: "calendar.notifications")
        self.eventAlertsEnabled = defaults.bool(forKey: "calendar.eventAlerts")
        self.eventLeadMinutes = defaults.object(forKey: "calendar.eventLeadMinutes") as? Int ?? 10
        self.scheduledEventKeys = Set(defaults.stringArray(forKey: "calendar.scheduledEventKeys") ?? [])
        self.snoozedEventKeys = defaults.dictionary(forKey: "calendar.snoozedEventKeys") as? [String: Date] ?? [:]
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
    var upcomingEvents: [CalendarEventSummary] { upcomingEventsForAlerts }
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
        else { events = []; nextEvent = nil; upcomingEventsForAlerts = []; calendars = []; lastUpdated = nil; status = accessState.title; cancelEventAlerts() }
    }
    func requestAccessAndRefresh() {
        guard !isRequestingAccess else { return }
        accessState = reader.accessState
        switch accessState {
        case .fullAccess: refresh()
        case .denied, .restricted: openCalendarSettings()
        case .notDetermined, .writeOnly:
            isRequestingAccess = true; status = "Waiting for Calendar permission..."
            NSApp?.activate(ignoringOtherApps: true)
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
        guard accessState == .fullAccess else { events = []; nextEvent = nil; upcomingEventsForAlerts = []; calendars = []; status = accessState.title; cancelEventAlerts(); return }
        isLoading = true
        let range = dateRange()
        let snapshot = reader.load(from: range.start, to: range.end, selectedIDs: nil)
        calendars = snapshot.calendars
        events = snapshot.events.filter { !excludedIDs.contains($0.calendarID) }
        let now = Date()
        let upcoming = reader.load(from: now, to: Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now.addingTimeInterval(30 * 86_400), selectedIDs: nil)
        nextEvent = upcoming.events.first { !excludedIDs.contains($0.calendarID) && $0.endDate > now }
        upcomingEventsForAlerts = upcoming.events.filter { !excludedIDs.contains($0.calendarID) }
        rescheduleEvents()
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
    func openCalendarApp() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
            status = "Calendar app could not be found"; return
        }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor in self.status = "Could not open Calendar: \(error.localizedDescription)" } }
        }
    }
    func addReminder(title: String, due: Date) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "Enter a reminder title"; return }
        guard due > Date() else { status = "Choose a future time"; return }
        let reminder = SieghartReminder(id: UUID(), title: trimmed, dueDate: due)
        reminders.append(reminder); saveReminders(); rescheduleReminders(); status = "Reminder added"; onReminderAdded?(reminder)
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
    func handleNotificationAction(_ action: String, reminderID: String?, eventKey: String?) {
        guard ["sieghart.dismiss", "sieghart.snooze"].contains(action) else { return }
        if let raw = reminderID, let id = UUID(uuidString: raw) {
            if action == "sieghart.dismiss" { dismiss(id) } else { snooze(id) }
            return
        }
        guard let key = eventKey else { return }
        if action == "sieghart.dismiss" {
            dismissedEventKeys.insert(key)
            notifier.cancelEvents([key]); scheduledEventKeys.remove(key); saveScheduledEventKeys()
            status = "Event alert dismissed"
        } else {
            if upcomingEventsForAlerts.isEmpty { prepare() }
            if let event = upcomingEventsForAlerts.first(where: { Self.eventKey($0) == key }) { snoozeEventAlert(event) }
        }
    }
    func handleNotificationDelivered(reminderID: String?, eventKey: String?) {
        if let raw = reminderID, let id = UUID(uuidString: raw), let reminder = visibleReminders.first(where: { $0.id == id }) {
            onNotificationDelivered?("reminder:\(raw):\(reminder.effectiveDate.timeIntervalSince1970)", reminder.title, true)
        } else if let key = eventKey {
            if upcomingEventsForAlerts.isEmpty { prepare() }
            if let event = upcomingEventsForAlerts.first(where: { Self.eventKey($0) == key }) { onNotificationDelivered?(key, event.title, false) }
        }
    }
    func isEventAlertDismissed(_ event: CalendarEventSummary) -> Bool { dismissedEventKeys.contains(Self.eventKey(event)) }
    func dismissEventAlert(_ event: CalendarEventSummary) {
        let key = Self.eventKey(event)
        dismissedEventKeys.insert(key)
        defaults.set(Array(dismissedEventKeys), forKey: "calendar.dismissedEventKeys")
        notifier.cancelEvents([key]); scheduledEventKeys.remove(key); saveScheduledEventKeys()
        status = "Event alert dismissed"
    }
    func snoozeEventAlert(_ event: CalendarEventSummary, minutes: Int = 10) {
        let key = Self.eventKey(event)
        let time = Date().addingTimeInterval(Double(minutes * 60))
        guard time < event.endDate else { status = "Event ends before the postponed alert"; return }
        snoozedEventKeys[key] = time
        defaults.set(snoozedEventKeys, forKey: "calendar.snoozedEventKeys")
        notifier.cancelEvents([key])
        Task { await notifier.scheduleEvent(event, key: key, at: time, quietStart: quietStart, quietEnd: quietEnd) }
        status = "Event alert postponed"
    }
    private var dismissedEventKeys: Set<String> {
        get { Set(defaults.stringArray(forKey: "calendar.dismissedEventKeys") ?? []) }
        set { defaults.set(Array(newValue), forKey: "calendar.dismissedEventKeys") }
    }
    private static func eventKey(_ event: CalendarEventSummary) -> String { "sieghart.event.\(event.id).\(Int(event.startDate.timeIntervalSince1970))" }
    private func saveScheduledEventKeys() { defaults.set(Array(scheduledEventKeys), forKey: "calendar.scheduledEventKeys") }
    private func cancelEventAlerts() {
        notifier.cancelEvents(scheduledEventKeys)
        scheduledEventKeys = []; saveScheduledEventKeys()
    }
    private func rescheduleEvents() {
        guard eventAlertsEnabled, accessState == .fullAccess else { cancelEventAlerts(); return }
        let now = Date()
        snoozedEventKeys = snoozedEventKeys.filter { $0.value > now }
        defaults.set(snoozedEventKeys, forKey: "calendar.snoozedEventKeys")
        let chosen = Array(upcomingEventsForAlerts.filter { $0.startDate > now && !dismissedEventKeys.contains(Self.eventKey($0)) }.prefix(32))
        let newKeys = Set(chosen.map(Self.eventKey))
        notifier.cancelEvents(scheduledEventKeys.subtracting(newKeys))
        scheduledEventKeys = newKeys; saveScheduledEventKeys()
        for event in chosen {
            let key = Self.eventKey(event)
            let due = snoozedEventKeys[key] ?? event.startDate.addingTimeInterval(-Double(eventLeadMinutes * 60))
            Task { await notifier.scheduleEvent(event, key: key, at: due, quietStart: quietStart, quietEnd: quietEnd) }
        }
    }
    private func saveReminders() { defaults.set(try? JSONEncoder().encode(reminders), forKey: "calendar.reminders") }
    private func rescheduleReminders() {
        for reminder in reminders {
            if !notificationsEnabled || reminder.completed { notifier.cancel(reminder.id) }
            else { Task { await notifier.schedule(reminder, enabled: true, quietStart: quietStart, quietEnd: quietEnd) } }
        }
    }
}
