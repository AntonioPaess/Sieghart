import AppKit
import ApplicationServices
import Combine

@MainActor final class MouseButtonController: ObservableObject {
    @Published var options: MouseButtonOptions {
        didSet { persist(); cancelActions(); if started { configure() } }
    }
    @Published private(set) var status = "Extra mouse buttons are off."
    @Published private(set) var lastButton: Int?
    private let defaults: UserDefaults
    private let backend: any MouseButtonMonitoring
    private let dispatcher: any MouseActionDispatching
    private let trusted: () -> Bool
    private let requestAccess: () -> Void
    private var started = false
    private var asleep = false
    private var locked = false
    private var sessionActive = true
    private var installed = false
    private var generation = 0
    private var actionGeneration = 0
    private var captured: Set<Int> = []
    private var queue: [MouseActionRequest] = []
    private var worker: Task<Void, Never>?
    private var health: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    init(defaults: UserDefaults = .standard, backend: (any MouseButtonMonitoring)? = nil,
         dispatcher: (any MouseActionDispatching)? = nil, trusted: @escaping () -> Bool = AXIsProcessTrusted,
         requestAccess: @escaping () -> Void = { AccessibilityAccess.request() }) {
        self.defaults = defaults; self.backend = backend ?? NativeMouseButtonMonitor()
        self.dispatcher = dispatcher ?? NativeMouseActionDispatcher(); self.trusted = trusted; self.requestAccess = requestAccess
        var value = MouseButtonOptions(navigation: defaults.bool(forKey: "input.mouseButtons.navigation"),
                                       custom: defaults.bool(forKey: "input.mouseButtons.custom"))
        for button in MouseButtonOptions.buttons {
            value.bindings[button] = MouseButtonAction(rawValue: defaults.string(forKey: "input.mouseButtons.\(button)") ?? "") ?? .inherit
        }
        options = value
    }
    private func persist() {
        defaults.set(options.navigation, forKey: "input.mouseButtons.navigation")
        defaults.set(options.custom, forKey: "input.mouseButtons.custom")
        for button in MouseButtonOptions.buttons { defaults.set((options.bindings[button] ?? .inherit).rawValue, forKey: "input.mouseButtons.\(button)") }
    }
    private var available: Bool { started && !asleep && !locked && sessionActive }
    func allowAccess() { requestAccess(); if started { configure() } }
    func configure() {
        guard available else { stopBackend(); status = started ? "Mouse button actions are paused." : "Extra mouse buttons are off."; return }
        guard options.enabled || !captured.isEmpty else {
            stopBackend(); status = options.custom ? "Choose an action for a button, or turn on Back and Forward." : "Extra mouse buttons are off."; return
        }
        guard trusted() else { stopBackend(); status = "Enable this copy of Sieghart in macOS permissions, then retry."; return }
        if installed {
            status = options.enabled ? "Mouse button actions are ready." : "Finishing the held button release; new clicks keep their mouse default."
            return
        }
        generation += 1; let current = generation
        do {
            try backend.start(handle: { [weak self] sample in
                guard let self, self.generation == current, self.installed else { return false }
                return self.receive(sample)
            }, interrupted: { [weak self] in
                guard let self, self.generation == current, self.installed else { return }
                self.stopBackend(); self.configure()
            })
            installed = true; status = "Mouse button actions are ready."
            health = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self, self.generation == current, self.installed else { return }
                    self.checkHealth()
                }
            }
        } catch { stopBackend(); status = "Mouse button actions unavailable. Check permissions and retry." }
    }
    private func receive(_ sample: MouseButtonSample) -> Bool {
        guard available, trusted() else { stopBackend(); status = "Mouse button actions are paused. Check permissions and retry."; return false }
        guard (3...31).contains(sample.button) else { return false }
        switch sample.phase {
        case .up:
            let consumed = captured.remove(sample.button) != nil
            if consumed && captured.isEmpty && !options.enabled {
                let current = generation
                DispatchQueue.main.async { [weak self] in if self?.generation == current { self?.configure() } }
            }
            return consumed
        case .dragged: return captured.contains(sample.button)
        case .down:
            if captured.contains(sample.button) { return true }
            lastButton = sample.button + 1
            let action = options.action(for: sample.button)
            guard action != .native, !sample.hasModifiers else { return false }
            switch dispatcher.prepare(action) {
            case .unavailable(let reason): status = reason; return false
            case .ready(let request):
                captured.insert(sample.button)
                guard queue.count < 8 else { status = "Button actions are busy. This click was skipped; wait and try again."; return true }
                queue.append(request); beginWorker(); return true
            }
        }
    }
    private func beginWorker() {
        guard worker == nil else { return }
        let current = actionGeneration
        worker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.actionGeneration == current else { return }
                guard !self.queue.isEmpty else { self.worker = nil; return }
                let request = self.queue.removeFirst()
                let result = await self.dispatcher.perform(request, valid: { [weak self] in
                    guard let self, self.actionGeneration == current, self.available, self.options.enabled, self.trusted() else { return false }
                    return self.dispatcher.isCurrent(request)
                })
                guard !Task.isCancelled, self.actionGeneration == current else { return }
                switch result {
                case .requested: self.status = "Requested \(request.action.title.lowercased()) in \(request.appName)."
                case .unavailable: self.status = "\(request.action.title) is unavailable or disabled in \(request.appName)'s menu."
                case .cancelled: self.status = "Button action cancelled because the app or access changed."
                }
            }
        }
    }
    private func cancelActions() { actionGeneration += 1; worker?.cancel(); worker = nil; queue = [] }
    private func stopBackend() {
        generation += 1; installed = false; backend.stop(); captured = []
        health?.cancel(); health = nil; cancelActions()
    }
    func checkHealth() {
        guard installed else { return }
        guard available, trusted() else { configure(); return }
        if !options.enabled {
            captured = captured.filter { backend.isPressed($0) }
            if captured.isEmpty { configure() }
        }
    }
    func start(observeSystem: Bool = true) {
        guard !started else { return }; started = true; configure()
        guard observeSystem else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == NSWorkspace.willSleepNotification { self?.setSleeping(true) }
                    if name == NSWorkspace.didWakeNotification { self?.setSleeping(false) }
                    if name == NSWorkspace.sessionDidResignActiveNotification { self?.setSessionActive(false) }
                    if name == NSWorkspace.sessionDidBecomeActiveNotification { self?.setSessionActive(true) }
                    if name == NSWorkspace.didActivateApplicationNotification { self?.cancelPendingActions() }
                }
            }))
        }
        let distributed = DistributedNotificationCenter.default()
        for name in [Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked")] {
            observers.append((distributed, distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(name.rawValue == "com.apple.screenIsLocked") }
            }))
        }
    }
    func cancelPendingActions() { cancelActions() }
    func setSleeping(_ value: Bool) { asleep = value; configure() }
    func setLocked(_ value: Bool) { locked = value; configure() }
    func setSessionActive(_ value: Bool) { sessionActive = value; configure() }
    func stop() {
        started = false; stopBackend()
        for (center, token) in observers { center.removeObserver(token) }; observers = []
        status = "Extra mouse buttons are off."; lastButton = nil
    }
}
