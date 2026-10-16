import AppKit
import SwiftUI

@MainActor private final class PreviewCalendar: CalendarReading {
    let accessState: CalendarAccessState
    init(accessState: CalendarAccessState = .fullAccess) { self.accessState = accessState }
    func requestAccess() async throws -> Bool { true }
    func load(from start: Date, to end: Date, selectedIDs: Set<String>?) -> CalendarSnapshot {
        let events = [
            CalendarEventSummary(id: "review", title: "Design review", startDate: Date().addingTimeInterval(1800), endDate: Date().addingTimeInterval(5400), calendarID: "work", calendarTitle: "Work", isAllDay: false, url: URL(string: "https://example.com/meeting")),
            CalendarEventSummary(id: "walk", title: "Afternoon walk", startDate: Date().addingTimeInterval(7200), endDate: Date().addingTimeInterval(9000), calendarID: "personal", calendarTitle: "Personal", isAllDay: false, url: nil),
            CalendarEventSummary(id: "planning", title: "Plan one thing for tomorrow", startDate: Date().addingTimeInterval(86400), endDate: Date().addingTimeInterval(88200), calendarID: "personal", calendarTitle: "Personal", isAllDay: false, url: nil),
            CalendarEventSummary(id: "project", title: "Companion project check-in", startDate: Date().addingTimeInterval(90000), endDate: Date().addingTimeInterval(91800), calendarID: "work", calendarTitle: "Work", isAllDay: false, url: URL(string: "https://example.com/meeting"))
        ]
        return CalendarSnapshot(events: events.filter { $0.endDate > start && $0.startDate < end }, calendars: [CalendarSource(id: "work", title: "Work", color: .blue), CalendarSource(id: "personal", title: "Personal", color: .green)], fetchedAt: Date())
    }
}
@MainActor private final class PreviewNotifier: ReminderNotifying {
    func schedule(_ reminder: SieghartReminder, enabled: Bool, quietStart: Int, quietEnd: Int) async {}
    func cancel(_ id: UUID) {}
    func scheduleEvent(_ event: CalendarEventSummary, key: String, at due: Date, quietStart: Int, quietEnd: Int) async {}
    func cancelEvents(_ keys: Set<String>) {}
}
private final class PreviewSensor: AccelerometerProviding {
    var onSample: ((AccelerationSample) -> Void)?
    let isRunning = false
    func start() throws {}
    func stop() {}
}
@main struct CalendarPreview {
    static var folder: URL { URL(fileURLWithPath: "Sieghart/Design/Validation/calendar-gantt", isDirectory: true) }
    @MainActor static func render<V: View>(_ view: V, name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.islandPreview, true))
        renderer.scale = 2
        guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: folder.appendingPathComponent(name + ".png"))
    }
    @MainActor static func main() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        AIProviderResources.bundle = Bundle(path: CommandLine.arguments.dropFirst().first ?? "/private/tmp/sieghart-team-build/Build/Products/Debug/Sieghart.app")!
        let suite = "sieghart.calendar.preview.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CompanionPreferences(defaults: defaults)
        preferences.onboardingComplete = true
        let assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let calendar = CalendarViewModel(reader: PreviewCalendar(), notifier: PreviewNotifier(), defaults: defaults, observesSystem: false)
        calendar.prepare(); calendar.span = .month
        calendar.addReminder(title: "Prepare notes", due: Date().addingTimeInterval(7200))
        let notch = NotchWidgetViewModel(assistant: assistant, preferences: preferences, calendar: calendar, managesWindows: false)
        let activation = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false)
        let codex = CodexUsageViewModel(defaults: defaults, load: { throw CocoaError(.fileReadNoSuchFile) })
        let usage = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
        notch.activation = activation; notch.codexUsage = codex; notch.aiUsage = usage
        notch.showCalendar()
        try render(NotchWidgetView(scrollable: false).environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(preferences).environmentObject(codex).environmentObject(usage).padding(36).background(Color(white: 0.22)), name: "calendar-island-preview")
        let permission = CalendarViewModel(reader: PreviewCalendar(accessState: .notDetermined), notifier: PreviewNotifier(), defaults: defaults, observesSystem: false)
        try render(CalendarView(model: permission, compact: true, island: true).frame(width: 672, height: 365).padding(28).background(Color.black), name: "calendar-permission-preview")
        let denied = CalendarViewModel(reader: PreviewCalendar(accessState: .denied), notifier: PreviewNotifier(), defaults: defaults, observesSystem: false)
        try render(CalendarView(model: denied, compact: true, island: true).frame(width: 672, height: 365).padding(28).background(Color.black), name: "calendar-denied-preview")
        notch.showTools()
        try render(NotchWidgetView(scrollable: false).environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(preferences).environmentObject(codex).environmentObject(usage).padding(36).background(Color(white: 0.22)), name: "calendar-tools-preview")
        try render(IslandLayoutEditor(preferences: preferences, onPreview: {}).frame(width: 850).padding(36).background(Color(white: 0.16)), name: "calendar-tools-editor-preview")
        try render(MenuBarView(initialPage: "Calendar").environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(preferences), name: "calendar-menu-preview")
        let sensor = SensorViewModel(reader: PreviewSensor()), gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        try render(ContentView(initialSection: .calendar, scrollable: false).frame(width: 1050, height: 950).environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(preferences).environmentObject(codex).environmentObject(usage).environmentObject(sensor).environmentObject(gestures), name: "calendar-app-preview")
        let empty = CalendarViewModel(reader: EmptyPreviewCalendar(), notifier: PreviewNotifier(), defaults: UserDefaults(suiteName: suite + ".empty")!, observesSystem: false)
        defer { UserDefaults().removePersistentDomain(forName: suite + ".empty") }
        empty.prepare(); empty.span = .month
        try render(CalendarView(model: empty, compact: true, island: true).frame(width: 672).padding(28).background(Color.black), name: "calendar-empty-preview")
        print("Rendered Calendar app, menu and island without EventKit access or native windows")
    }
}

@MainActor private final class EmptyPreviewCalendar: CalendarReading {
    let accessState = CalendarAccessState.fullAccess
    func requestAccess() async throws -> Bool { true }
    func load(from start: Date, to end: Date, selectedIDs: Set<String>?) -> CalendarSnapshot {
        CalendarSnapshot(events: [], calendars: [], fetchedAt: Date())
    }
}
