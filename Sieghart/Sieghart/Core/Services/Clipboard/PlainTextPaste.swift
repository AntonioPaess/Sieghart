import AppKit
import ApplicationServices

struct PlainClipboardSnapshot: Sendable {
    var changeCount: Int
    var text: String
    var items: [[String: Data]]
}
@MainActor protocol PlainClipboardAccess {
    func snapshot() async throws -> PlainClipboardSnapshot
    func writePlain(_ snapshot: PlainClipboardSnapshot) async throws -> Int
    func restore(_ snapshot: PlainClipboardSnapshot, ifUnchanged count: Int) async -> Bool
}
@MainActor final class NativePlainClipboard: PlainClipboardAccess {
    private let worker = PasteboardWorker()
    func snapshot() async throws -> PlainClipboardSnapshot {
        guard let result = await worker.run({ () -> PlainClipboardSnapshot? in
            let board = NSPasteboard.general, count = board.changeCount
            guard Set((board.types ?? []).map(\.rawValue)).isDisjoint(with: SystemClipboardAccess.excludedTypes),
                  let text = board.string(forType: .string), !text.isEmpty, text.utf8.count <= 512 * 1024 else { return nil }
            var bytes = 0, items: [[String: Data]] = []
            for item in (board.pasteboardItems ?? []).prefix(50) {
                var saved: [String: Data] = [:]
                for type in item.types {
                    guard let data = item.data(forType: type) else { continue }
                    bytes += data.count; guard bytes <= 20 * 1024 * 1024 else { return nil }
                    saved[type.rawValue] = data
                }
                items.append(saved)
            }
            guard board.changeCount == count, !items.isEmpty else { return nil }
            return PlainClipboardSnapshot(changeCount: count, text: text, items: items)
        }), let result else { throw FileToolError.message("Copy some text first. Protected or oversized clipboard data is left untouched.") }
        return result
    }
    func writePlain(_ snapshot: PlainClipboardSnapshot) async throws -> Int {
        guard let count = await worker.run({ () -> Int? in
            let board = NSPasteboard.general
            guard board.changeCount == snapshot.changeCount else { return nil }
            board.clearContents()
            guard board.setString(snapshot.text, forType: .string) else {
                let items = snapshot.items.map { contents -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in contents { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
                    return item
                }
                board.clearContents(); _ = board.writeObjects(items); return nil
            }
            return board.changeCount
        }), let count else { throw FileToolError.message("The clipboard changed. Copy your text again before pasting.") }
        return count
    }
    func restore(_ snapshot: PlainClipboardSnapshot, ifUnchanged count: Int) async -> Bool {
        await worker.run {
            let board = NSPasteboard.general
            guard board.changeCount == count else { return false }
            let items = snapshot.items.map { contents -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in contents { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
                return item
            }
            board.clearContents(); return board.writeObjects(items)
        } ?? false
    }
}
@MainActor protocol PlainPasteTargeting {
    func canPaste(to pid: Int32) -> Bool
    func activate(_ pid: Int32) -> Bool
    func paste(to pid: Int32) -> Bool
    func pasteMatchingStyle(to pid: Int32) async -> Bool
}
extension PlainPasteTargeting { func pasteMatchingStyle(to pid: Int32) async -> Bool { false } }
@MainActor final class NativePlainPasteTarget: PlainPasteTargeting {
    func canPaste(to pid: Int32) -> Bool { AXIsProcessTrusted() && NSRunningApplication(processIdentifier: pid)?.isTerminated == false && pid != ProcessInfo.processInfo.processIdentifier }
    func activate(_ pid: Int32) -> Bool { NSRunningApplication(processIdentifier: pid)?.activate() ?? false }
    func paste(to pid: Int32) -> Bool {
        guard canPaste(to: pid), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand; down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return true
    }
    func pasteMatchingStyle(to pid: Int32) async -> Bool {
        guard canPaste(to: pid), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        let lookup = Task.detached(priority: .userInitiated) {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.04)
            func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
                var result: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
                return result as? T
            }
            guard let menu: AXUIElement = attribute(kAXMenuBarAttribute, from: app) else { return false }
            var queue: [(AXUIElement, Int)] = [(menu, 0)], index = 0
            let deadline = Date().addingTimeInterval(1)
            while index < queue.count && index < 80 && Date() < deadline && !Task.isCancelled {
                let (node, depth) = queue[index]; index += 1; AXUIElementSetMessagingTimeout(node, 0.04)
                let key: String? = attribute(kAXMenuItemCmdCharAttribute, from: node)
                if key?.lowercased() == "v", let mask: NSNumber = attribute(kAXMenuItemCmdModifiersAttribute, from: node), mask.uint32Value == 3,
                   let enabled: NSNumber = attribute(kAXEnabledAttribute, from: node), enabled.boolValue {
                    let focused = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && AXIsProcessTrusted() }
                    guard focused, !Task.isCancelled else { return false }
                    return AXUIElementPerformAction(node, kAXPressAction as CFString) == .success
                }
                if depth < 3, let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: node) {
                    queue.append(contentsOf: children.prefix(80 - min(80, queue.count)).map { ($0, depth + 1) })
                }
            }
            return false
        }
        return await withTaskCancellationHandler(operation: { await lookup.value }, onCancel: { lookup.cancel() })
    }
}
@MainActor final class PlainTextPasteService {
    private let board: any PlainClipboardAccess
    private let target: any PlainPasteTargeting
    private let pause: (Duration) async throws -> Void
    init(board: any PlainClipboardAccess = NativePlainClipboard(), target: any PlainPasteTargeting = NativePlainPasteTarget(),
         pause: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.board = board; self.target = target; self.pause = pause
    }
    func paste(to pid: Int32, dismiss: () -> Void) async throws -> String {
        guard target.canPaste(to: pid) else { throw FileToolError.message("Allow Accessibility for direct paste, then select a destination app.") }
        let saved = try await board.snapshot()
        dismiss(); guard target.activate(pid) else { throw FileToolError.message("Choose your destination app again.") }
        try await pause(.milliseconds(180)); try Task.checkCancellation()
        guard target.canPaste(to: pid) else { throw FileToolError.message("Paste access is unavailable. Your clipboard stayed intact.") }
        if await target.pasteMatchingStyle(to: pid) { return "Pasted without formatting. Original clipboard stayed intact." }
        let written = try await board.writePlain(saved)
        do {
            try Task.checkCancellation()
            guard target.paste(to: pid) else { throw FileToolError.message("The destination changed. Your clipboard was restored.") }
            try await pause(.milliseconds(500))
        } catch { _ = await board.restore(saved, ifUnchanged: written); throw error }
        let restored = await board.restore(saved, ifUnchanged: written)
        return restored ? "Pasted plain text. Original clipboard restored." : "Paste requested. A newer clipboard copy was kept."
    }
}
