import AppKit
import Carbon
import SwiftUI

enum ShortcutAction: String, CaseIterable, Identifiable {
    case companion, voice, clipboard, nextOutput, muteMicrophone
    var id: String { rawValue }
    var title: String { switch self { case .companion: "Companion"; case .voice: "Voice"; case .clipboard: "Clipboard"; case .nextOutput: "Switch output"; case .muteMicrophone: "Mute microphone" } }
}

enum ShortcutDeliverySource { case carbon, monitor }

// One physical gesture may arrive through both global backends. Suppress the
// duplicate backend delivery, while retaining successive gestures on one path.
struct ShortcutDeliveryGate {
    private var previous: [ShortcutAction: (source: ShortcutDeliverySource, time: TimeInterval)] = [:]
    mutating func accept(_ action: ShortcutAction, source: ShortcutDeliverySource, at time: TimeInterval) -> Bool {
        // Physical timestamps can arrive in reverse callback order after a
        // Space transition. The second backend must still count as a duplicate.
        if let last = previous[action], last.source != source, abs(time - last.time) < 0.15 { return false }
        previous[action] = (source, time)
        return true
    }
}

struct ShortcutChord: Codable, Equatable {
    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    var keyCode: UInt32?
    var modifiers: UInt
    var keyLabel: String

    static let companion = ShortcutChord(keyCode: 1, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "S")
    static let voice = ShortcutChord(keyCode: 9, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "V")
    static let clipboard = ShortcutChord(keyCode: 8, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "C")
    static let legacyVoice = ShortcutChord(keyCode: nil, modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue, keyLabel: "")

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.allowedModifiers) }
    var isModifierOnly: Bool { keyCode == nil && !flags.isEmpty }
    var label: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { flags.contains($0.0) }.map(\.1).joined() + keyLabel
    }
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    func matches(keyCode: UInt32, flags: NSEvent.ModifierFlags) -> Bool {
        self.keyCode == keyCode && self.flags == flags.intersection(Self.allowedModifiers)
    }

    static func captured(from event: NSEvent) -> ShortcutChord {
        let names: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "Enter", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        let label = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        return ShortcutChord(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags.intersection(allowedModifiers).rawValue, keyLabel: label)
    }
}

// A modifier shortcut fires on release, once. Using a letter or an extra
// modifier during the same gesture prevents an accidental voice activation.
struct ModifierShortcutTracker {
    private var peak: UInt = 0
    private var usedKey = false
    mutating func keyPressed() { if peak != 0 { usedKey = true } }
    mutating func reset() { peak = 0; usedKey = false }
    mutating func update(_ flags: NSEvent.ModifierFlags) -> UInt? {
        let current = flags.intersection(ShortcutChord.allowedModifiers).rawValue
        if current != 0 { peak |= current; return nil }
        defer { reset() }
        return peak != 0 && !usedKey ? peak : nil
    }
}

struct ShortcutRecorder: View {
    @EnvironmentObject private var activation: ActivationController
    let action: ShortcutAction
    private var recording: Bool { activation.recordingShortcut == action }
    var body: some View {
        HStack(spacing: 8) {
            Button(recording ? "Press shortcut…" : activation.shortcut(for: action)?.label ?? "Record shortcut") {
                activation.recordingShortcut = recording ? nil : action
            }
            .buttonStyle(CompanionButtonStyle())
            .focusEffectDisabled()
            .background(ShortcutCaptureView(recording: recording, onCapture: { activation.setShortcut($0, for: action) }, onCancel: { activation.recordingShortcut = nil }).frame(width: 0, height: 0))
            if activation.shortcut(for: action) != nil {
                Button("Off") { activation.setShortcut(nil, for: action) }.buttonStyle(.plain).focusEffectDisabled()
            }
        }
        .accessibilityLabel("\(action.title) shortcut")
        .onDisappear { activation.cancelShortcutRecording(for: action) }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let recording: Bool
    let onCapture: (ShortcutChord) -> Void
    let onCancel: () -> Void
    func makeNSView(context: Context) -> ShortcutCaptureNSView { ShortcutCaptureNSView() }
    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
        guard recording != view.recording else { return }
        view.recording = recording
        view.tracker.reset()
        if recording {
            DispatchQueue.main.async { [weak view] in
                guard let view, view.recording else { return }
                view.window?.makeFirstResponder(view)
            }
        } else if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var recording = false
    var tracker = ModifierShortcutTracker()
    var onCapture: ((ShortcutChord) -> Void)?
    var onCancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { onCancel?() }
        else { onCapture?(ShortcutChord.captured(from: event)) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func flagsChanged(with event: NSEvent) {
        guard recording else { return }
        if let modifiers = tracker.update(event.modifierFlags) {
            onCapture?(ShortcutChord(keyCode: nil, modifiers: modifiers, keyLabel: ""))
        }
    }
}
