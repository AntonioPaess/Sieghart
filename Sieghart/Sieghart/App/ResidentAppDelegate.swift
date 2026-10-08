import AppKit

/// The window is a settings surface; activation belongs to the resident app.
@MainActor
final class ResidentAppDelegate: NSObject, NSApplicationDelegate {
    var clipboard: ClipboardViewModel?
    var onLaunch: (() -> Void)?
    var onTerminate: (() -> Void)?
    private var finishedLaunching = false
    var activation: ActivationController? {
        didSet { if finishedLaunching { activation?.startGlobalShortcuts() } }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        finishedLaunching = true
        activation?.startGlobalShortcuts()
        onLaunch?()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        onTerminate?()
        guard let clipboard else { return .terminateNow }
        Task { await clipboard.flush(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        activation?.recoverShortcuts()
        return false
    }
}
