import AppKit
import Combine
import EventKit
import Foundation
import SwiftUI

enum CalendarAccessState: Equatable {
    case notDetermined
    case writeOnly
    case fullAccess
    case denied
    case restricted

    var title: String {
        switch self {
        case .notDetermined:
            return "Calendar access not requested"
        case .writeOnly:
            return "Calendar read access required"
        case .fullAccess:
            return "Calendar connected"
        case .denied:
            return "Calendar access denied"
        case .restricted:
            return "Calendar access restricted"
        }
    }
}

struct CalendarEventSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let isAllDay: Bool
    let url: URL?

    var relativeStart: String {
        let minutes = Int(ceil(startDate.timeIntervalSinceNow / 60))
        if minutes <= 0 {
            return "Now"
        }
        if minutes == 1 {
            return "In 1 minute"
        }
        if minutes < 60 {
            return "In \(minutes) minutes"
        }

        let hours = minutes / 60
        return hours == 1 ? "In 1 hour" : "In \(hours) hours"
    }

    var hasLink: Bool {
        url != nil
    }
}

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var accessState: CalendarAccessState = .notDetermined
    @Published private(set) var upcomingEvents: [CalendarEventSummary] = []
    @Published private(set) var status = "Calendar access not requested"
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var permissionSheetDidNotAppear = false

    private var eventStore: EKEventStore
    private var requestTask: Task<Void, Never>?
    private var activationObserver: AnyCancellable?

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        activationObserver = NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.prepare()
        }
        refreshAuthorizationState()
    }

    var nextEvent: CalendarEventSummary? {
        upcomingEvents.first
    }

    var accessButtonLabel: String {
        if permissionSheetDidNotAppear {
            return "Open calendar settings"
        }

        switch accessState {
        case .notDetermined, .writeOnly:
            return "Connect calendar"
        case .fullAccess:
            return "Refresh calendar"
        case .denied, .restricted:
            return "Open calendar settings"
        }
    }

    func prepare() {
        guard !isRequestingAccess else { return }

        // TCC applies Calendar changes when the app returns from System
        // Settings (and sometimes only after the app is relaunched). Reusing
        // the original store can keep the old authorization snapshot alive,
        // so create a fresh store before reading the state again.
        eventStore = EKEventStore()
        refreshAuthorizationState()
        if accessState == .fullAccess {
            permissionSheetDidNotAppear = false
            refresh()
        }
    }

    func requestAccessAndRefresh() {
        guard !isRequestingAccess else { return }
        refreshAuthorizationState()

        guard accessState != .fullAccess else {
            permissionSheetDidNotAppear = false
            refresh()
            return
        }

        if permissionSheetDidNotAppear {
            openCalendarSettings()
            return
        }

        guard accessState == .notDetermined || accessState == .writeOnly else {
            openCalendarSettings()
            return
        }

        isRequestingAccess = true
        status = "Preparing calendar permission..."

        // EventKit presents the system permission sheet more reliably when the
        // app is active, especially when the request starts from a sensor event
        // or the non-activating notch panel. Waiting for activation to settle
        // prevents a false completion before the sheet can be displayed.
        NSApp.activate(ignoringOtherApps: true)
        requestTask?.cancel()
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }

            status = "Requesting calendar access..."
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let error {
                        isRequestingAccess = false
                        permissionSheetDidNotAppear = true
                        status = "Calendar permission request failed: \(error.localizedDescription)"
                        requestTask = nil
                        return
                    }

                    eventStore.reset()
                    // The permission sheet can finish in System Settings. A
                    // new store is required to observe the resulting TCC
                    // decision instead of displaying the pre-request state.
                    eventStore = EKEventStore()
                    refreshAuthorizationState()

                    if granted && accessState == .fullAccess {
                        permissionSheetDidNotAppear = false
                        refresh()
                    } else if accessState == .notDetermined {
                        // A false result while the authorization state is still
                        // notDetermined does not prove that the person dismissed
                        // anything. Keep the message factual and offer settings.
                        permissionSheetDidNotAppear = true
                        status = "The calendar permission sheet did not appear. Open calendar settings."
                    } else {
                        permissionSheetDidNotAppear = false
                        status = accessState.title
                    }
                    isRequestingAccess = false
                    requestTask = nil
                }
            }
        }
    }

    func refresh() {
        refreshAuthorizationState()
        guard accessState == .fullAccess else {
            upcomingEvents = []
            status = accessState.title
            return
        }

        let now = Date()
        let end = now.addingTimeInterval(24 * 60 * 60)
        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: end,
            calendars: nil
        )

        upcomingEvents = eventStore
            .events(matching: predicate)
            .filter { !$0.isAllDay || $0.startDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map { CalendarEventSummary(event: $0) }

        lastUpdated = now
        status = upcomingEvents.isEmpty
            ? "No events in the next 24 hours"
            : "Calendar updated"
    }

    func openNextEventLink() {
        guard let url = nextEvent?.url else {
            status = "The next event has no link"
            return
        }

        guard NSWorkspace.shared.open(url) else {
            status = "The event link could not be opened"
            return
        }

        status = "Opened the next event link"
    }

    func openCalendarSettings() {
        permissionSheetDidNotAppear = false
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            status = "Open System Settings to allow calendar access"
            return
        }

        guard NSWorkspace.shared.open(settingsURL) else {
            status = "Open System Settings to allow calendar access"
            return
        }

        status = "Enable Calendar access, then press Refresh calendar"
    }

    private func refreshAuthorizationState() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            accessState = .notDetermined
        case .writeOnly:
            accessState = .writeOnly
        case .fullAccess:
            accessState = .fullAccess
        case .denied:
            accessState = .denied
        case .restricted:
            accessState = .restricted
        @unknown default:
            accessState = .restricted
        }

        if !isRequestingAccess && !permissionSheetDidNotAppear {
            status = accessState.title
        }
    }
}

private extension CalendarEventSummary {
    init(event: EKEvent) {
        let notesURL = CalendarEventSummary.firstURL(in: event.notes)

        self.init(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title.isEmpty ? "Untitled event" : event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            calendarTitle: event.calendar?.title ?? "Calendar",
            isAllDay: event.isAllDay,
            url: event.url ?? notesURL
        )
    }

    static func firstURL(in text: String?) -> URL? {
        guard let text else { return nil }

        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let candidate = token.trimmingCharacters(in: .punctuationCharacters)
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else {
                continue
            }
            return url
        }

        return nil
    }
}
