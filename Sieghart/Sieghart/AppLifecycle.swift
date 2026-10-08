import AppKit

/// The window is a settings surface; activation belongs to the resident app.
@MainActor
final class ResidentAppDelegate: NSObject, NSApplicationDelegate {
    private var finishedLaunching = false
    var activation: ActivationController? {
        didSet { if finishedLaunching { activation?.startGlobalShortcuts() } }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        finishedLaunching = true
        activation?.startGlobalShortcuts()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        activation?.recoverShortcuts()
        return false
    }
}
