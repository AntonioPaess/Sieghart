import SwiftUI

@MainActor final class CompanionMotionStudioViewModel: ObservableObject {
    @Published var member: CompanionAvatar
    @Published var animation: CompanionAnimation = .hello
    @Published var replay = 0
    init(member: CompanionAvatar = .sig) { self.member = member }
    func play() { replay += 1 }
}

// Compact panels can collapse normally while the explicitly opened rehearsal
// window remains usable. Closing it releases the scene and its geometry cache.
@MainActor final class CompanionMotionStudioWindow: NSObject, NSWindowDelegate {
    static let shared = CompanionMotionStudioWindow()
    private var window: NSWindow?
    func present(member: CompanionAvatar, animates: Bool) {
        let window = self.window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 590),
                                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Sieghart · Meet your team"; window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = NSHostingView(rootView: CompanionMotionStudio(initialMember: member, animates: animates, close: { [weak self] in self?.window?.close() }))
        if self.window == nil { window.center() }
        self.window = window
        NSApp?.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { window?.contentView = nil; window = nil }
}
