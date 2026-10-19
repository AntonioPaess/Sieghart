import AppKit
import ApplicationServices
import Carbon

enum MouseButtonAction: String, CaseIterable, Codable, Sendable {
    case inherit, native, back, forward, copy, paste, undo, redo, selectAll
    var title: String {
        switch self {
        case .inherit: "Use navigation preset"
        case .native: "Keep mouse default"
        case .back: "Back"
        case .forward: "Forward"
        case .copy: "Copy"
        case .paste: "Paste"
        case .undo: "Undo"
        case .redo: "Redo"
        case .selectAll: "Select all"
        }
    }
    var menuKey: String? {
        switch self {
        case .back: "["
        case .forward: "]"
        case .copy: "c"
        case .paste: "v"
        case .undo, .redo: "z"
        case .selectAll: "a"
        case .inherit, .native: nil
        }
    }
    func matchesMenu(key: String?, modifiers: UInt32?, enabled: Bool) -> Bool {
        // AX defaults to Command. Bit 0 adds Shift; exact masks prevent
        // confusing Back with Previous Tab, or Undo with Redo.
        guard let menuKey, let key, let modifiers, enabled else { return false }
        return key.lowercased() == menuKey && modifiers == (self == .redo ? 1 : 0)
    }
    func supports(bundleID: String) -> Bool {
        guard self == .back || self == .forward else { return menuKey != nil }
        // Cmd-[ can mean indentation in an editor. Navigation is deliberately
        // scoped to apps whose history command uses this standard shortcut.
        return ["com.apple.finder", "com.apple.Safari", "com.google.Chrome"].contains(bundleID)
    }
}
struct MouseButtonOptions: Equatable {
    static let buttons = Array(3...7) // CG numbers; UI displays buttons 4–8.
    var navigation = false
    var custom = false
    var bindings: [Int: MouseButtonAction] = [:]
    func action(for button: Int) -> MouseButtonAction {
        guard Self.buttons.contains(button) else { return .native }
        if custom, let action = bindings[button], action != .inherit { return action }
        if navigation && button == 3 { return .back }
        if navigation && button == 4 { return .forward }
        return .native
    }
    var enabled: Bool { Self.buttons.contains { action(for: $0) != .native } }
}
struct MouseActionRequest: Equatable, Sendable {
    let action: MouseButtonAction
    let pid: Int32
    let launchedAt: Date
    let bundleID: String
    let appName: String
    let windowID: UInt32
}
enum MouseActionPreparation {
    case ready(MouseActionRequest)
    case unavailable(String)
}
enum MouseActionResult: Equatable, Sendable {
    case requested, unavailable, cancelled
}
@MainActor protocol MouseActionDispatching: AnyObject {
    func prepare(_ action: MouseButtonAction) -> MouseActionPreparation
    func isCurrent(_ request: MouseActionRequest) -> Bool
    func perform(_ request: MouseActionRequest, valid: @escaping @MainActor @Sendable () -> Bool) async -> MouseActionResult
}

@MainActor final class NativeMouseActionDispatcher: MouseActionDispatching {
    private func frontWindow(of pid: Int32) -> UInt32? {
        // Window-server metadata only: no image, title or contents are read.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.prefix(256).first(where: {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }).flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }
    func prepare(_ action: MouseButtonAction) -> MouseActionPreparation {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated,
              app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let date = app.launchDate, let bundle = app.bundleIdentifier, let window = frontWindow(of: app.processIdentifier) else {
            return .unavailable("Choose an app outside Sieghart. Button actions pause during Secure Input.")
        }
        guard action.supports(bundleID: bundle) else {
            return .unavailable("Back and Forward support Finder, Safari and Chrome. This app keeps the mouse default.")
        }
        return .ready(MouseActionRequest(action: action, pid: app.processIdentifier, launchedAt: date,
                                        bundleID: bundle, appName: app.localizedName ?? "App", windowID: window))
    }
    func isCurrent(_ request: MouseActionRequest) -> Bool {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated,
              app.processIdentifier == request.pid, app.launchDate == request.launchedAt,
              app.bundleIdentifier == request.bundleID, frontWindow(of: request.pid) == request.windowID else { return false }
        return true
    }
    func perform(_ request: MouseActionRequest, valid: @escaping @MainActor @Sendable () -> Bool) async -> MouseActionResult {
        // AX menu queries may block on another app. They never run in the tap
        // callback or on the main actor. The worker owns all its AX handles.
        let worker = Task.detached(priority: .userInitiated) { () -> MouseActionResult in
            guard !Task.isCancelled, await valid() else { return .cancelled }
            let app = AXUIElementCreateApplication(request.pid)
            AXUIElementSetMessagingTimeout(app, 0.04)
            func value(_ name: String, from node: AXUIElement) -> CFTypeRef? {
                var output: CFTypeRef?
                return AXUIElementCopyAttributeValue(node, name as CFString, &output) == .success ? output : nil
            }
            guard let rawMenu = value(kAXMenuBarAttribute, from: app), CFGetTypeID(rawMenu) == AXUIElementGetTypeID() else { return .unavailable }
            let menu = rawMenu as! AXUIElement
            var queue: [(AXUIElement, Int)] = [(menu, 0)], index = 0
            let deadline = ContinuousClock.now + .milliseconds(700)
            while index < queue.count, index < 200, ContinuousClock.now < deadline, !Task.isCancelled {
                let (node, depth) = queue[index]; index += 1
                AXUIElementSetMessagingTimeout(node, 0.04)
                let key = value(kAXMenuItemCmdCharAttribute, from: node) as? String
                if key?.lowercased() == request.action.menuKey,
                   request.action.matchesMenu(key: key,
                       modifiers: (value(kAXMenuItemCmdModifiersAttribute, from: node) as? NSNumber)?.uint32Value,
                       enabled: (value(kAXEnabledAttribute, from: node) as? Bool) == true) {
                    guard !Task.isCancelled, await valid(), !Task.isCancelled else { return .cancelled }
                    return AXUIElementPerformAction(node, kAXPressAction as CFString) == .success ? .requested : .unavailable
                }
                if depth < 5, let children = value(kAXChildrenAttribute, from: node) as? [AXUIElement] {
                    queue.append(contentsOf: children.prefix(max(0, 200 - queue.count)).map { ($0, depth + 1) })
                }
            }
            return Task.isCancelled ? .cancelled : .unavailable
        }
        return await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
    }
}
