import AppKit

// The panel is never ordered onscreen. Override visibility only to exercise
// the layer lifecycle without opening Sieg or changing the user's desktop.
@MainActor private final class MotionFixturePanel: NSPanel {
    override var isVisible: Bool { true }
    override var isMiniaturized: Bool { false }
    override var occlusionState: NSWindow.OcclusionState { .visible }
}

enum AgentChatMotionChecks {
    @MainActor static func run() {
        // Supply owned pixels so this lifecycle check never creates a 3D
        // fallback scene merely because the test executable has no catalog.
        let fixtureArt = NSImage(size: NSSize(width: 70, height: 70))
        let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 70, pixelsHigh: 70,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 280, bitsPerPixel: 32)!
        fixtureArt.addRepresentation(pixels)
        fixtureArt.setName("Companion-ada")
        let panel = MotionFixturePanel(contentRect: NSRect(x: -5000, y: -5000, width: 80, height: 80),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let ada = AgentChatCompanionView(frame: NSRect(x: 0, y: 0, width: 70, height: 70))
        panel.contentView = ada
        ada.configure(state: .ready, sending: false, active: true, conversationID: "owned")
        // Idle has a sparse wakeup, with no continuously changing layer.
        precondition(ada.motionDiagnostics.animationCount == 0 && ada.motionDiagnostics.idleTimerScheduled)
        let submitted = UUID()
        ada.configure(state: .ready, sending: false, active: true, conversationID: "owned", submissionID: submitted)
        precondition(ada.motionDiagnostics.hasSendAcknowledgement) // A quick RPC cannot hide the send gesture.
        ada.configure(state: .ready, sending: true, active: true, conversationID: "owned")
        precondition(ada.motionDiagnostics.animationCount > 0 && !ada.motionDiagnostics.idleTimerScheduled)
        let failure = UUID()
        ada.configure(state: .completed, sending: true, active: true, conversationID: "owned", failureID: failure)
        ada.configure(state: .completed, sending: false, active: true, conversationID: "owned", failureID: failure)
        precondition(ada.motionDiagnostics.showingSendFailure)
        ada.configure(state: .completed, sending: false, active: true, conversationID: "owned", failureID: failure)
        precondition(ada.motionDiagnostics.showingSendFailure) // Redraws cannot celebrate a failed send.
        ada.configure(state: .completed, sending: true, active: true, conversationID: "owned", failureID: failure)
        precondition(!ada.motionDiagnostics.showingSendFailure)
        let secondFailure = UUID()
        ada.configure(state: .completed, sending: false, active: true, conversationID: "owned",
                      failureID: secondFailure, submissionID: UUID())
        precondition(ada.motionDiagnostics.showingSendFailure && !ada.motionDiagnostics.hasSendAcknowledgement) // Rejection wins even when the send event coalesces.
        ada.configure(state: .working, sending: false, active: false, conversationID: "owned", failureID: failure)
        precondition(ada.motionDiagnostics.animationCount == 0 && !ada.motionDiagnostics.idleTimerScheduled)
        ada.configure(state: .completed, sending: false, active: true, conversationID: "other", failureID: UUID())
        precondition(ada.motionDiagnostics.animationCount == 0 && !ada.motionDiagnostics.showingSendFailure)
        ada.stop()
        precondition(ada.motionDiagnostics.animationCount == 0 && !ada.motionDiagnostics.idleTimerScheduled)
        panel.contentView = nil
        panel.close()
    }
}
