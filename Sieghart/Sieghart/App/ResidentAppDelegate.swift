import AppKit
import UserNotifications

/// The window is a settings surface; activation belongs to the resident app.
@MainActor
final class ResidentAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var calendar: CalendarViewModel?
    var files: FilesViewModel?
    var capture: CaptureViewModel?
    weak var notch: NotchWidgetViewModel?
    var clipboard: ClipboardViewModel?
    var onLaunch: (() -> Void)?
    var onTerminate: (() -> Void)?
    private var finishedLaunching = false
    var activation: ActivationController? {
        didSet { if finishedLaunching { activation?.startGlobalShortcuts() } }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LocalReminderNotifier.registerActions()
        UNUserNotificationCenter.current().delegate = self
        finishedLaunching = true
        activation?.startGlobalShortcuts()
        onLaunch?()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let reminderID = info["reminderID"] as? String
        let eventKey = info["calendarEventKey"] as? String
        let taskModule = info["siegTaskModule"] as? String
        Task { @MainActor [weak self] in
            self?.calendar?.handleNotificationAction(action, reminderID: reminderID, eventKey: eventKey)
            if action == UNNotificationDefaultActionIdentifier {
                self?.calendar?.handleNotificationDelivered(reminderID: reminderID, eventKey: eventKey)
                if taskModule == CompanionNotificationModule.capture.rawValue { self?.notch?.showCapture() }
                else if taskModule == CompanionNotificationModule.downloads.rawValue { self?.notch?.showFiles(downloads: true) }
                else if taskModule == CompanionNotificationModule.files.rawValue { self?.notch?.showFiles() }
                else if reminderID != nil || eventKey != nil { self?.notch?.showCalendar() }
            }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo, reminder = info["reminderID"] as? String, event = info["calendarEventKey"] as? String
        Task { @MainActor [weak self] in self?.calendar?.handleNotificationDelivered(reminderID: reminder, eventKey: event) }
        completionHandler([.banner, .sound])
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        onTerminate?()
        guard let clipboard else { return .terminateNow }
        Task { await files?.shutdownAndFlush(); await capture?.shutdown(); await clipboard.flush(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        activation?.recoverShortcuts()
        return false
    }
}
