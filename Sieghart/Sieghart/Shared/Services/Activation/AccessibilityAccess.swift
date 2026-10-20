import AppKit
import ApplicationServices

@MainActor enum AccessibilityAccess {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    /// The OS prompt is asynchronous and may not appear again. The explicit
    /// button always opens settings so a prior decision has a recovery path.
    @discardableResult static func request(
        trusted: () -> Bool = AXIsProcessTrusted,
        prompt: () -> Void = { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) },
        open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> Bool {
        if !trusted() { prompt() }
        return open(settingsURL)
    }
    static func revealRunningApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
