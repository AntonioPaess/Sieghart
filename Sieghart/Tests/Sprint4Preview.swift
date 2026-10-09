import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor private final class PreviewClipboard: ClipboardAccess {
    func read(after changeCount: Int?, includeMedia: Bool) async -> ClipboardRead? { fatalError("No real clipboard in previews") }
    func write(_ payload: ClipboardPayload) async -> Int? { fatalError("No real clipboard in previews") }
}
private actor PreviewStorage: ClipboardStorage {
    func load() -> [ClipboardEntry] { [] }
    func save(_ entries: [ClipboardEntry], revision: UInt64) {}
}
private final class NoPreviewSensor: AccelerometerProviding {
    var onSample: ((AccelerationSample) -> Void)?
    let isRunning = false
    func start() throws { fatalError("No sensors in previews") }
    func stop() {}
}
@main struct Sprint4Preview {
    @MainActor static func png<V: View>(_ view: V, _ name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.islandPreview, true)); renderer.scale = 2
        guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: URL(fileURLWithPath: "Sieghart/Design/Concepts/\(name).png"))
    }
    @MainActor static func main() async throws {
        AIProviderResources.bundle = Bundle(path: "/private/tmp/sieghart-simple-build/Build/Products/Debug/Sieghart.app")!
        let suite = "Sieghart.Sprint4Preview.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = CompanionPreferences(defaults: defaults); prefs.avatar = .crtBuddy; prefs.appearance = .dark; prefs.onboardingComplete = true
        let clipboard = ClipboardViewModel(defaults: defaults, access: PreviewClipboard(), storage: PreviewStorage(), monitorsSystem: false)
        await clipboard.restore(); clipboard.isEnabled = true
        let copies = ["One thing at a time. A little progress is still progress.", "Make space for the work that matters.", "https://example.com/project-notes", "Next: review the draft, then send the final version.", "Remember where you stopped. Resume when you are ready."]
        for text in copies { clipboard.record(ClipboardPayload(kind: .text, text: text), sourceName: "Notes · example", sourceBundle: "example.notes") }
        clipboard.record(ClipboardPayload(kind: .files, files: [URL(fileURLWithPath: "/tmp/Project notes.pdf")]), sourceName: "Finder · example", sourceBundle: "example.finder")
        if let item = clipboard.entries.first(where: { $0.payload.kind == .text }) { clipboard.togglePin(item.id) }
        let assistant = AssistantViewModel(defaults: defaults, schedulesTimer: false)
        let notch = NotchWidgetViewModel(assistant: assistant, preferences: prefs, clipboard: clipboard, managesWindows: false)
        let activation = ActivationController(assistant: assistant, notch: notch, defaults: defaults, registersShortcuts: false)
        let codex = CodexUsageViewModel(defaults: defaults, load: { throw CocoaError(.fileReadNoSuchFile) })
        let usage = AIUsageViewModel(defaults: defaults, readClaude: { nil }, read: { _ in nil })
        notch.activation = activation; notch.codexUsage = codex; notch.aiUsage = usage
        func island() -> some View { NotchWidgetView(scrollable: false).environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(prefs).environmentObject(codex).environmentObject(usage).environment(\.islandPreview, true) }
        notch.showClipboard()
        try png(island().padding(36).background(Color(white: 0.22)), "island-clipboard-preview")
        try png(MenuBarView(initialPage: "Clipboard").environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(prefs), "menu-clipboard-preview")
        let sensor = SensorViewModel(reader: NoPreviewSensor()), gestures = ImpactGestureCoordinator(assistant: assistant, notch: notch)
        try png(ContentView(initialSection: .clipboard, scrollable: false).frame(width: 1050, height: 760).environmentObject(notch).environmentObject(assistant).environmentObject(activation).environmentObject(prefs).environmentObject(codex).environmentObject(usage).environmentObject(sensor).environmentObject(gestures), "app-clipboard-preview")
        for step in 0...2 {
            let view = CompanionOnboardingView(scrollable: false, clipboard: clipboard, initialStep: step, arrivalPreviewTime: 1.5, prepareVoice: { "Preview only" }).frame(width: 900, height: 740).environmentObject(prefs).environmentObject(codex).environmentObject(usage)
            try png(view, "onboarding-\(["welcome", "companions", "tools"][step])-preview")
        }
        let url = URL(fileURLWithPath: "Sieghart/Design/Concepts/companion-welcome-motion.gif")
        let frames = 72
        guard let gif = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<frames {
            let elapsed = Double(frame) / 30
            let view = VStack(spacing: 16) {
                Text("A familiar face, a softer arrival.").font(.title3.weight(.semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(200)), count: 3), spacing: 6) {
                    ForEach(CompanionAvatar.allCases) { avatar in
                        VStack(spacing: 0) {
                            CompanionArrivalView(avatar: avatar, previewElapsed: max(0, elapsed - Double(CompanionAvatar.allCases.firstIndex(of: avatar)!) * 0.055), size: 120).frame(width: 200, height: 178)
                            Text(avatar.name).font(.caption).foregroundStyle(CompanionStyle.muted)
                        }
                    }
                }
                Text("Production native artwork · 30 fps preview · runtime 60 Hz").font(.caption2).foregroundStyle(CompanionStyle.muted)
            }.padding(24).background(CompanionStyle.background).foregroundStyle(CompanionStyle.ink).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view); renderer.scale = 1.5
            guard let cg = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(gif, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 30, kCGImagePropertyGIFUnclampedDelayTime: 1.0 / 30]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
        print("Rendered clipboard app/menu/island and three onboarding steps; 72-frame six-companion welcome. No window, clipboard, shortcuts, microphone or sensors used.")
    }
}
