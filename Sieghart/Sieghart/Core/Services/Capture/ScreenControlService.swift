import AppKit
import ApplicationServices
import Combine

struct ScreenControl: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let role: String
    let frame: CGRect
    let actions: [String]
    let writable: Bool
}

enum ScreenControlMutation: Equatable, Sendable {
    case press(String), scroll(String, down: Bool), write(String, text: String)
    var id: String { switch self { case .press(let id), .scroll(let id,_), .write(let id,_): id } }
}

@MainActor protocol ScreenControlBackend: AnyObject {
    func snapshot() throws -> [ScreenControl]
    func perform(_ mutation: ScreenControlMutation) throws -> String
}
enum ScreenControlFailure: Error { case unavailable, changed, refused }
@MainActor final class InactiveScreenControlBackend: ScreenControlBackend {
    func snapshot() throws -> [ScreenControl] { throw ScreenControlFailure.unavailable }
    func perform(_ mutation: ScreenControlMutation) throws -> String { throw ScreenControlFailure.unavailable }
}

/// Tokens bind one actual AX element to one application instance and window.
/// No pixel coordinates from the model are accepted as action destinations.
@MainActor final class MacScreenControlBackend: ScreenControlBackend {
    private struct Handle {
        let element: AXUIElement
        let window: AXUIElement
        let pid: pid_t
        let launchDate: Date
        let control: ScreenControl
    }
    private var handles: [String: Handle] = [:]
    private var lastExternalApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    init() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternalApp = app }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid, let app = NSRunningApplication(processIdentifier: pid),
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.lastExternalApp = app }
            }
        }
    }
    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private func string(_ name: String, of element: AXUIElement) -> String { attribute(name, of: element) as? String ?? "" }
    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(kAXPositionAttribute, of: element), let s = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: point, size: size)
    }
    private func actionNames(_ element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success else { return [] }
        return value as? [String] ?? []
    }
    func snapshot() throws -> [ScreenControl] {
        handles = [:]
        let front = NSWorkspace.shared.frontmostApplication
        let target = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApp : front
        guard AXIsProcessTrusted(), let app = target, !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier, let launched = app.launchDate else { throw ScreenControlFailure.unavailable }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.08)
        guard let rawWindow = attribute(kAXFocusedWindowAttribute, of: root), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { throw ScreenControlFailure.unavailable }
        let window = rawWindow as! AXUIElement
        var queue = [window], seen: [AXUIElement] = [], controls: [ScreenControl] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while !queue.isEmpty, seen.count < 250, controls.count < 70, ProcessInfo.processInfo.systemUptime < deadline {
            let element = queue.removeFirst()
            guard !seen.contains(where: { CFEqual($0, element) }) else { continue }
            seen.append(element); AXUIElementSetMessagingTimeout(element, 0.05)
            let role = string(kAXRoleAttribute, of: element)
            let actions = actionNames(element)
            var title = string(kAXTitleAttribute, of: element)
            if title.isEmpty { title = string(kAXDescriptionAttribute, of: element) }
            if title.isEmpty, role == kAXScrollAreaRole, !actions.isEmpty { title = "Page" }
            let enabled = (attribute(kAXEnabledAttribute, of: element) as? Bool) ?? true
            var settable = DarwinBoolean(false)
            let writable = [kAXTextFieldRole,kAXTextAreaRole].contains(role)
                && AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
            if enabled, (attribute("AXHidden", of: element) as? Bool) != true, let rect = frame(element), !title.isEmpty,
               role != "AXSecureTextField", !title.lowercased().contains("password"),
               actions.contains(kAXPressAction) || actions.contains("AXScrollDownByPage") || actions.contains("AXScrollUpByPage") || writable {
                let control = ScreenControl(id: UUID().uuidString, title: String(title.prefix(180)), role: role, frame: rect, actions: actions, writable: writable)
                controls.append(control)
                handles[control.id] = .init(element: element, window: window, pid: app.processIdentifier, launchDate: launched, control: control)
            }
            if let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] { queue += children.prefix(max(0,250-queue.count)) }
        }
        return controls
    }
    func perform(_ mutation: ScreenControlMutation) throws -> String {
        guard AXIsProcessTrusted(), let handle = handles[mutation.id],
              let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier == handle.pid || front.processIdentifier == ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: handle.pid),
              app.launchDate == handle.launchDate, !app.isTerminated else { throw ScreenControlFailure.changed }
        let root = AXUIElementCreateApplication(handle.pid)
        guard let window = attribute(kAXFocusedWindowAttribute, of: root), CFEqual(window, handle.window),
              let current = frame(handle.element), abs(current.minX-handle.control.frame.minX) < 3,
              abs(current.minY-handle.control.frame.minY) < 3,
              abs(current.width-handle.control.frame.width) < 3, abs(current.height-handle.control.frame.height) < 3,
              string(kAXRoleAttribute, of: handle.element) == handle.control.role,
              ((attribute(kAXEnabledAttribute, of: handle.element) as? Bool) ?? true) else { throw ScreenControlFailure.changed }
        let title = string(kAXTitleAttribute, of: handle.element)
        let description = string(kAXDescriptionAttribute, of: handle.element)
        guard title == handle.control.title || description == handle.control.title || (handle.control.role == kAXScrollAreaRole && handle.control.title == "Page" && title.isEmpty && description.isEmpty) else { throw ScreenControlFailure.changed }
        defer { handles = [:] }
        switch mutation {
        case .press:
            guard actionNames(handle.element).contains(kAXPressAction), AXUIElementPerformAction(handle.element, kAXPressAction as CFString) == .success else { throw ScreenControlFailure.refused }
            return "The accessibility press was accepted for \(handle.control.title). Verify the resulting screen before another action."
        case .scroll(_,let down):
            let action = down ? "AXScrollDownByPage" : "AXScrollUpByPage"
            guard actionNames(handle.element).contains(action), AXUIElementPerformAction(handle.element, action as CFString) == .success else { throw ScreenControlFailure.refused }
            return "The accessibility scroll was accepted. Re-read the screen before another action."
        case .write(_,let text):
            guard handle.control.writable, text.utf8.count <= 8000,
                  AXUIElementSetAttributeValue(handle.element, kAXValueAttribute as CFString, text as CFString) == .success,
                  string(kAXValueAttribute, of: handle.element) == text else { throw ScreenControlFailure.refused }
            return "Verified text written to \(handle.control.title)."
        }
    }
}

enum ScreenControlRequest {
    case press(label: String), scroll(down: Bool), write(text: String, label: String)
    static func parse(_ text: String) -> Self? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        func parts(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = re.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
            return (1..<match.numberOfRanges).compactMap { Range(match.range(at:$0),in:value).map { String(value[$0]) } }
        }
        if let p = parts(#"^(?:por favor |please )?(?:clique|clica|click|press|pressione)\s+(?:(?:no|na|em|the)\s+)?(?:(?:botão|botao|button)\s+)?[“\"]?([^”\"\n]{1,120}?)[”\"]?[.!]?$"#) { return .press(label:p[0]) }
        if let p = parts(#"^(?:por favor |please )?(?:role|rola|scroll)\s+(?:(?:a tela|a página|a pagina|the page|the screen)\s+)?(?:para\s+)?(baixo|cima|down|up)[.!]?$"#) { return .scroll(down:["baixo","down"].contains(p[0].lowercased())) }
        if let p = parts(#"^(?:escreva|digite|write|type)\s+[“\"](.{1,4000})[”\"]\s+(?:no campo|na caixa|in the field|into)\s+[“\"]?([^”\"\n]{1,120}?)[”\"]?[.!]?$"#) { return .write(text:p[0],label:p[1]) }
        return nil
    }
    static func requiresReview(_ label: String) -> Bool {
        let normalized = label.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.init(identifier:"en_US"))
        return ["send","enviar","submit","publicar","post","buy","comprar","pay","pagar","delete","apagar","excluir","lixo","trash","allow","permitir","autorizar","install","instalar","confirm","confirmar","accept","aceitar","agree","concordar","senha","password"].contains { normalized.contains($0) }
    }
}

@MainActor final class ScreenControlService: ObservableObject {
    struct Review { let control: ScreenControl; let mutation: ScreenControlMutation; let summary: String }
    @Published private(set) var pendingReview: Review?
    private(set) var controls: [ScreenControl] = []
    private let backend: any ScreenControlBackend
    init(backend: any ScreenControlBackend) { self.backend = backend }
    func inspect() throws -> String {
        pendingReview = nil; controls = try backend.snapshot()
        return controls.map { "id=\($0.id), label=\($0.title), role=\($0.role), actions=\($0.actions.joined(separator:",")), writable=\($0.writable)" }.joined(separator:"\n")
    }
    func execute(id: String, original: String) throws -> String {
        guard let request = ScreenControlRequest.parse(original), let control = controls.first(where:{$0.id == id}) else { throw ScreenControlFailure.refused }
        let mutation: ScreenControlMutation
        func same(_ left:String,_ right:String) -> Bool { left.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.init(identifier:"en_US")) == right.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.init(identifier:"en_US")) }
        switch request {
        case .press(let label): guard same(label,control.title) else { throw ScreenControlFailure.refused }; mutation = .press(id)
        case .scroll(let down): guard control.actions.contains(down ? "AXScrollDownByPage" : "AXScrollUpByPage") else { throw ScreenControlFailure.refused }; mutation = .scroll(id,down:down)
        case .write(let text,let label): guard same(label,control.title),control.writable else { throw ScreenControlFailure.refused }; mutation = .write(id,text:text)
        }
        if case .write = mutation { pendingReview = .init(control:control,mutation:mutation,summary:original); return "Review required in Sieg before writing. Nothing was changed." }
        if ScreenControlRequest.requiresReview(control.title) { pendingReview = .init(control:control,mutation:mutation,summary:original); return "Review required in Sieg. No action was executed." }
        let receipt = try backend.perform(mutation)
        controls = []
        return receipt
    }
    func confirmReview() throws -> String {
        guard let pendingReview else { throw ScreenControlFailure.changed }
        defer { self.pendingReview = nil; controls = [] }
        return try backend.perform(pendingReview.mutation)
    }
    func cancelReview() { pendingReview = nil }
}
