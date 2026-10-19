import AppKit
import Testing

@MainActor private final class IntegrationMotionPanel: NSPanel {
    override var isVisible: Bool { true }
    override var isMiniaturized: Bool { false }
    override var occlusionState: NSWindow.OcclusionState { [.visible] }
}

extension MacContractsTests {
    @Suite(.tags(.agentRoom, .nativeView)) @MainActor struct AgentChatMotionTests {
        private func withView(_ operation: (AgentChatCompanionView) throws -> Void) throws {
            try CompanionArtwork.withIsolatedCaches {
                let art = NSImage(size: NSSize(width: 70, height: 70))
                let pixels = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 70, pixelsHigh: 70, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 280, bitsPerPixel: 32))
                art.addRepresentation(pixels); try #require(art.setName("Companion-ada"))
                let panel = IntegrationMotionPanel(contentRect: NSRect(x: -5000, y: -5000, width: 80, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                let view = AgentChatCompanionView(frame: NSRect(x: 0, y: 0, width: 70, height: 70)); panel.contentView = view
                defer { view.stop(); panel.contentView = nil; panel.close() }
                try operation(view)
            }
        }
        @Test("G17.08 — idle esparso e gesto rápido de envio são observáveis sem loop permanente")
        func idleAndQuickSubmission() throws {
            try withView { view in
                view.configure(state: .ready, sending: false, active: true, conversationID: "owned")
                #expect(view.motionDiagnostics.animationCount == 0 && view.motionDiagnostics.idleTimerScheduled)
                view.configure(state: .ready, sending: false, active: true, conversationID: "owned", submissionID: UUID())
                #expect(view.motionDiagnostics.hasSendAcknowledgement)
                view.configure(state: .ready, sending: true, active: true, conversationID: "owned")
                #expect(view.motionDiagnostics.animationCount > 0 && !view.motionDiagnostics.idleTimerScheduled)
            }
        }
        @Test("G17.08 — falha vence confirmação coalescida, redraw não celebra e retry limpa falha")
        func failureAndRetry() throws {
            try withView { view in
                let failure = UUID()
                view.configure(state: .ready, sending: false, active: true, conversationID: "owned")
                view.configure(state: .completed, sending: true, active: true, conversationID: "owned", failureID: failure)
                view.configure(state: .completed, sending: false, active: true, conversationID: "owned", failureID: failure)
                #expect(view.motionDiagnostics.showingSendFailure)
                view.configure(state: .completed, sending: false, active: true, conversationID: "owned", failureID: failure)
                #expect(view.motionDiagnostics.showingSendFailure)
                view.configure(state: .completed, sending: true, active: true, conversationID: "owned", failureID: failure)
                #expect(!view.motionDiagnostics.showingSendFailure)
                view.configure(state: .completed, sending: false, active: true, conversationID: "owned", failureID: UUID(), submissionID: UUID())
                #expect(view.motionDiagnostics.showingSendFailure && !view.motionDiagnostics.hasSendAcknowledgement)
            }
        }
        @Test("G17.08 — invisível, troca de conversa e stop liberam layers/timer")
        func teardownAndConversationChange() throws {
            try withView { view in
                view.configure(state: .working, sending: true, active: true, conversationID: "owned", failureID: UUID())
                view.configure(state: .working, sending: false, active: false, conversationID: "owned", failureID: UUID())
                #expect(view.motionDiagnostics.animationCount == 0 && !view.motionDiagnostics.idleTimerScheduled)
                view.configure(state: .completed, sending: false, active: true, conversationID: "other", failureID: UUID())
                #expect(view.motionDiagnostics.animationCount == 0 && !view.motionDiagnostics.showingSendFailure)
                view.stop()
                #expect(view.motionDiagnostics.animationCount == 0 && !view.motionDiagnostics.idleTimerScheduled)
            }
        }
        @Test("G17.08 — escopo restaura imagem nomeada e caches após falha")
        func cacheScopeRestoresCaller() throws {
            enum FixtureFailure: Error, Equatable { case expected }
            try CompanionArtwork.withIsolatedCaches {
                let name = NSImage.Name("Companion-ada"), original = NSImage(size: NSSize(width: 20, height: 20))
                try #require(original.setName(name))
                let previousPortrait = CompanionArtwork.portrait(for: .ada)
                #expect(throws: FixtureFailure.expected) {
                    try CompanionArtwork.withIsolatedCaches {
                        let art = NSImage(size: NSSize(width: 10, height: 10)); try #require(art.setName(name))
                        #expect(NSImage(named: name) === art)
                        _ = CompanionArtwork.portrait(for: .ada)
                        throw FixtureFailure.expected
                    }
                }
                #expect(NSImage(named: name) === original)
                #expect(CompanionArtwork.portrait(for: .ada) === previousPortrait)
            }
        }
    }
}
