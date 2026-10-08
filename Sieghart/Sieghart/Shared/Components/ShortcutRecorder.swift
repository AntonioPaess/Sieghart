import AppKit
import Carbon
import SwiftUI

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
