import AppKit
import CoreGraphics
import SwiftUI

@MainActor enum ScreenAccessRecovery {
    static var appURL: URL { Bundle.main.bundleURL }
    static var allowed: Bool { CGPreflightScreenCaptureAccess() }
    static func openSettings() {
        // Request only in response to the user's button, never during capture.
        if !allowed { _ = CGRequestScreenCaptureAccess() }
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
    static func revealCopy() { NSWorkspace.shared.activateFileViewerSelecting([appURL]) }
}

struct ScreenPermissionHelp: View {
    let language: String
    var retry: (() -> Void)? = nil
    private var en: Bool { language.hasPrefix("en") }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(en ? "Allow this copy to read your screen" : "Permita que esta cópia leia sua tela", systemImage: "viewfinder")
                .font(.headline)
            Text(en ? "Enable Sieghart in Screen Recording. If macOS requests a restart, reopen this same copy." : "Ative o Sieghart em Gravação de Tela. Se o macOS pedir para reiniciar, reabra esta mesma cópia.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { settingsButton; locateButton; retryButton }
                VStack(alignment: .leading, spacing: 8) {
                    settingsButton
                    HStack(spacing: 8) { locateButton; retryButton }
                }
            }
            Label(ScreenAccessRecovery.appURL.lastPathComponent, systemImage: "app")
                .font(.caption2).foregroundStyle(CompanionStyle.muted)
                .help(ScreenAccessRecovery.appURL.path)
        }
    }
    private var settingsButton: some View {
        Button(en ? "Open screen permission" : "Abrir permissão de tela") { ScreenAccessRecovery.openSettings() }
            .buttonStyle(CompanionButtonStyle(primary: true, compact: true))
    }
    private var locateButton: some View {
        Button(en ? "Locate this app" : "Localizar este app") { ScreenAccessRecovery.revealCopy() }
            .buttonStyle(CompanionButtonStyle(compact: true))
    }
    @ViewBuilder private var retryButton: some View {
        if let retry {
            Button(en ? "Try again" : "Tentar novamente", action: retry)
                .buttonStyle(CompanionButtonStyle(compact: true))
        }
    }

}
