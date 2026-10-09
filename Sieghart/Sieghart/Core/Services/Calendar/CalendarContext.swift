import AppKit
import Combine
import EventKit
import Foundation

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

struct CalendarEventSummary: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let isAllDay: Bool
    let url: URL?

    var relativeStart: String {
        let minutes = Int(ceil(startDate.timeIntervalSinceNow / 60))
        if minutes <= 0 { return "Now" }
        if minutes == 1 { return "In 1 minute" }
        if minutes < 60 { return "In \(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "In 1 hour" : "In \(hours) hours"
    }

    var hasLink: Bool { url != nil }
}

struct CalendarSnapshot: Sendable {
    let events: [CalendarEventSummary]
    let calendarCount: Int
    let fetchedAt: Date

    static func load() -> CalendarSnapshot {
        // The store and its EKEvent objects stay on this background task.
        // Only value summaries cross back to the main actor.
        let store = EKEventStore()
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86_400)
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map(CalendarEventSummary.init)
        return CalendarSnapshot(events: events, calendarCount: calendars.count, fetchedAt: now)
    }
}

private extension CalendarEventSummary {
    init(event: EKEvent) {
        self.init(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title.isEmpty ? "Untitled event" : event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            calendarTitle: event.calendar?.title ?? "Calendar",
            isAllDay: event.isAllDay,
            url: Self.webURL(event.url) ?? Self.firstURL(in: event.location) ?? Self.firstURL(in: event.notes)
        )
    }

    static func webURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    static func firstURL(in text: String?) -> URL? {
        guard let text else { return nil }
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let candidate = token.trimmingCharacters(in: .punctuationCharacters)
            if let url = webURL(URL(string: candidate)) { return url }
        }
        return nil
    }
}
