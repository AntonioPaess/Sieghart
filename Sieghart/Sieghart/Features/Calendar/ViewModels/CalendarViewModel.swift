import AppKit
import Combine
import EventKit
import Foundation

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var accessState: CalendarAccessState = .notDetermined
    @Published private(set) var upcomingEvents: [CalendarEventSummary] = []
    @Published private(set) var status = "Calendar access not requested"
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var availableCalendarCount: Int?

    private var requestTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var activationObserver: AnyCancellable?
    private var storeChangeObserver: AnyCancellable?

    init() {
        activationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.prepare() }
        storeChangeObserver = NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.prepare() }
        updateAuthorizationState()
    }

    var nextEvent: CalendarEventSummary? { upcomingEvents.first }

    var accessButtonLabel: String {
        switch accessState {
        case .notDetermined, .writeOnly: "Connect calendar"
        case .fullAccess: "Refresh calendar"
        case .denied, .restricted: "Open calendar settings"
        }
    }

    func prepare() {
        guard !isRequestingAccess else { return }
        updateAuthorizationState()
        if accessState == .fullAccess { refresh() }
    }

    func requestAccessAndRefresh() {
        guard !isRequestingAccess else { return }
        updateAuthorizationState()

        switch accessState {
        case .fullAccess:
            refresh()
        case .denied, .restricted:
            openCalendarSettings()
        case .notDetermined, .writeOnly:
            isRequestingAccess = true
            status = "Waiting for Calendar permission..."
            // The explicit Connect action may come from a nonactivating panel.
            // Activate the app before asking macOS to present permission UI.
            NSApp.activate(ignoringOtherApps: true)
            requestTask = Task { [weak self] in
                guard let self else { return }
                do {
                    // Only an explicit Connect action requests access.
                    // The result cannot prove whether a system sheet appeared.
                    try await Task.sleep(for: .milliseconds(150))
                    let granted = try await EKEventStore().requestFullAccessToEvents()
                    updateAuthorizationState()
                    if granted && accessState == .fullAccess {
                        refresh()
                    } else {
                        status = accessState == .notDetermined
                            ? "Calendar permission is still undecided. Check System Settings if no prompt appeared."
                            : accessState.title
                    }
                } catch {
                    updateAuthorizationState()
                    status = "Calendar permission request failed: \(error.localizedDescription)"
                }
                isRequestingAccess = false
                requestTask = nil
            }
        }
    }

    func refresh() {
        updateAuthorizationState()
        guard accessState == .fullAccess else { return }

        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        isLoading = true
        status = "Loading events from Calendar..."
        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                CalendarSnapshot.load()
            }.value
            guard let self, !Task.isCancelled, generation == refreshGeneration else { return }

            upcomingEvents = snapshot.events
            availableCalendarCount = snapshot.calendarCount
            lastUpdated = snapshot.fetchedAt
            isLoading = false
            if snapshot.calendarCount == 0 {
                status = "Access granted, but EventKit found no calendars. Check Calendar accounts and visibility."
            } else if snapshot.events.isEmpty {
                status = "No current or upcoming events in the next 7 days across \(snapshot.calendarCount) calendars."
            } else {
                status = "Loaded \(snapshot.events.count) upcoming events from \(snapshot.calendarCount) calendars."
            }
            refreshTask = nil
        }
    }

    func openNextEventLink() {
        guard let url = nextEvent?.url else {
            status = "The next event has no meeting link"
            return
        }
        status = NSWorkspace.shared.open(url)
            ? "Opened the next event link"
            : "The event link could not be opened"
    }

    func openCalendarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"),
              NSWorkspace.shared.open(url) else {
            status = "Open System Settings → Privacy & Security → Calendars"
            return
        }
        status = "Check Calendar access in System Settings, then refresh here."
    }

    private func updateAuthorizationState() {
        let previous = accessState
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: accessState = .notDetermined
        case .writeOnly: accessState = .writeOnly
        case .fullAccess: accessState = .fullAccess
        case .denied: accessState = .denied
        case .restricted: accessState = .restricted
        @unknown default: accessState = .restricted
        }

        if accessState != .fullAccess {
            refreshGeneration += 1
            refreshTask?.cancel()
            refreshTask = nil
            isLoading = false
            upcomingEvents = []
            availableCalendarCount = nil
            lastUpdated = nil
            if !isRequestingAccess || previous != accessState { status = accessState.title }
        }
    }
}
