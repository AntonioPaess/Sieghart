import AppKit

/// The window is a settings surface; activation belongs to the resident app.
@MainActor
final class ResidentAppDelegate: NSObject, NSApplicationDelegate {
    var activation: ActivationController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        activation?.recoverShortcuts()
        return false
    }
}
