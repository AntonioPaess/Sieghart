import AppKit
import Foundation
import Testing

@Suite(.tags(.logic), .timeLimit(.minutes(1))) struct LogicTests {}
@Suite(.serialized, .timeLimit(.minutes(1))) struct MacContractsTests {}

extension Tag {
    @Tag static var logic: Self
    @Tag static var isolated: Self
    @Tag static var localIntegration: Self
    @Tag static var nativeView: Self
    @Tag static var timer: Self
    @Tag static var callbacks: Self
    @Tag static var voiceIntegration: Self
    @Tag static var interactions: Self
    @Tag static var companions: Self
    @Tag static var usage: Self
    @Tag static var spending: Self
    @Tag static var activity: Self
    @Tag static var pricing: Self
    @Tag static var audio: Self
    @Tag static var imports: Self
    @Tag static var clipboard: Self
    @Tag static var input: Self
    @Tag static var middleClick: Self
    @Tag static var utilities: Self
    @Tag static var calendar: Self
    @Tag static var filesCapture: Self
    @Tag static var agentRoom: Self
    @Tag static var localChat: Self
    @Tag static var newCodexChat: Self
}

@MainActor final class TestDefaults {
    let suiteName = "Sieghart.SwiftTesting.\(UUID().uuidString)"
    let value: UserDefaults
    init() throws { value = try #require(UserDefaults(suiteName: suiteName)) }
    func cleanup() { value.removePersistentDomain(forName: suiteName) }
}

private final class TestBundleMarker: NSObject {}
enum TestResources {
    static var priceCatalogURL: URL {
        Bundle(for: TestBundleMarker.self).bundleURL.appendingPathComponent("Contents/Resources/ModelTokenPrices.json")
    }
}

@MainActor private final class IsolatedCalendarReader: CalendarReading {
    var accessState: CalendarAccessState { .notDetermined }
    func requestAccess() async throws -> Bool {
        Issue.record("An isolated calendar fixture must never request real access")
        throw CocoaError(.userCancelled)
    }
    func load(from start: Date, to end: Date, selectedIDs: Set<String>?) -> CalendarSnapshot {
        CalendarSnapshot(events: [], calendars: [], fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
@MainActor private final class IsolatedReminderNotifier: ReminderNotifying {
    func schedule(_ reminder: SieghartReminder, enabled: Bool, quietStart: Int, quietEnd: Int) async {}
    func cancel(_ id: UUID) {}
    func scheduleEvent(_ event: CalendarEventSummary, key: String, at due: Date, quietStart: Int, quietEnd: Int) async {}
    func cancelEvents(_ keys: Set<String>) {}
}
@MainActor enum IsolatedCalendarFixture {
    static func make(defaults: UserDefaults) -> CalendarViewModel {
        CalendarViewModel(reader: IsolatedCalendarReader(), notifier: IsolatedReminderNotifier(),
                          defaults: defaults, observesSystem: false)
    }
}
