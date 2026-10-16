import AppKit
import SwiftUI

// Native single-line field matching Coucou's PromptView. Every edit updates the
// draft; Return and the adjacent button use the same send action.
struct AgentChatComposer: NSViewRepresentable {
    @Binding var text: String
    var focusID: String?
    var placeholder = "Ask me anything…"
    var submit: () -> Void
    func makeNSView(context: Context) -> AgentChatEditor {
        let field = AgentChatEditor()
        field.changed = { text = $0 }; field.submit = submit
        return field
    }
    func updateNSView(_ field: AgentChatEditor, context: Context) {
        field.changed = { text = $0 }; field.submit = submit
        field.placeholderString = placeholder
        field.update(text: text, focusID: focusID)
    }
}
final class AgentChatEditor: NSTextField, NSTextFieldDelegate {
    var changed: ((String) -> Void)?
    var submit: (() -> Void)?
    private var lastFocusID: String?
    private var lastBoundText: String?
    override init(frame: NSRect) {
        super.init(frame: frame)
        delegate = self; isEditable = true; isSelectable = true
        isBordered = false; drawsBackground = false; focusRingType = .none
        font = .systemFont(ofSize: 13); textColor = .white
        usesSingleLineMode = true; lineBreakMode = .byTruncatingTail
        cell?.isScrollable = true
        target = self; action = #selector(sendDraft)
        setAccessibilityLabel("Message to the selected conversation")
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func update(text: String, focusID: String?) {
        // The field editor owns uncommitted text while the panel is focused.
        // Comparing against stringValue can overwrite an edit or IME input on
        // an unrelated SwiftUI refresh before AppKit commits the cell value.
        if lastBoundText != text || lastFocusID != focusID {
            if currentDraft != text { stringValue = text }
            lastBoundText = text
        }
        if lastFocusID != focusID { lastFocusID = focusID; requestFocus() }
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); requestFocus() }
    private func requestFocus() {
        guard lastFocusID != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isKeyWindow else { return }
            window.makeFirstResponder(self)
        }
    }
    private var currentDraft: String { currentEditor()?.string ?? stringValue }
    func controlTextDidChange(_ notification: Notification) { changed?(currentDraft) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { sendDraft(); return true }
        return false
    }
    @objc func sendDraft() {
        (currentEditor() as? NSTextView)?.unmarkText()
        changed?(currentDraft); submit?()
    }
}
