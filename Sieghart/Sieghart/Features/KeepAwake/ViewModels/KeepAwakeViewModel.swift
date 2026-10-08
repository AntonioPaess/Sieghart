import AppKit
import Combine
import IOKit.pwr_mgt

@MainActor final class KeepAwakeViewModel: ObservableObject {
    @Published var request: AwakeRequest
    @Published private(set) var enabled = false
    @Published private(set) var holding = false
    @Published private(set) var status = "Your Mac follows its normal sleep settings"
    @Published private(set) var error: String?
    @Published private(set) var remaining: TimeInterval? = nil
    var onReaction: ((Bool) -> Void)?
    private let backend: any AwakeBackend
    private let defaults: UserDefaults
    private let now: () -> Date
    private var token: UInt32?
    private var tokenKeepsDisplay = false
    private var suspended = false
    private var timer: Task<Void, Never>?
    private var notifications: [NSObjectProtocol] = []
    private var notificationCenter: NotificationCenter?
    init(backend: (any AwakeBackend)? = nil, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.backend = backend ?? MacAwakeBackend(); self.defaults = defaults; self.now = now
        request = defaults.data(forKey: "awake.request").flatMap { try? JSONDecoder().decode(AwakeRequest.self, from: $0) } ?? AwakeRequest()
    }
    // Called only by the resident app, never by construction or preview tests.
    func startLifecycle(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        guard notifications.isEmpty else { return }
        notificationCenter = center
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            notifications.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sleeps = note.name == NSWorkspace.willSleepNotification
                MainActor.assumeIsolated { self?.setSleeping(sleeps) }
            })
        }
        if request.restoreOnLaunch && defaults.bool(forKey: "awake.active") && (request.end == nil || request.end! > now()) {
            enabled = true; tick(); startTimer()
        } else { defaults.set(false, forKey: "awake.active") }
    }
    func start() {
        stop(react: false)
        error = nil
        switch request.mode {
        case .duration:
            request.minutes = min(1440, max(1, request.minutes)); request.end = now().addingTimeInterval(Double(request.minutes) * 60)
        case .until:
            guard request.until > now() else { error = "Choose a time in the future"; return }
            request.end = request.until
        case .indefinite: request.end = nil
        }
        enabled = true; persist(); tick(); startTimer()
        onReaction?(error == nil)
    }
    func stop(react: Bool = true) {
        timer?.cancel(); timer = nil; relinquish()
        enabled = false; remaining = nil
        defaults.set(false, forKey: "awake.active")
        status = "Your Mac follows its normal sleep settings"
        if react { onReaction?(true) }
    }
    func saveOptions() { persist(); if enabled { tick() } }
    func setSleeping(_ sleeping: Bool) { suspended = sleeping; if sleeping { relinquish() }; tick() }
    func tick() {
        guard enabled else { return }
        remaining = request.end.map { max(0, $0.timeIntervalSince(now())) }
        if let end = request.end, end <= now() { stop(); status = "Keep awake finished"; return }
        let context = backend.context()
        guard !suspended, request.eligible(context) else {
            relinquish()
            status = suspended ? "Paused while your Mac sleeps" : "Waiting for your power, display or app conditions"
            return
        }
        if token != nil && tokenKeepsDisplay != request.keepDisplay { relinquish() }
        if token == nil {
            do { token = try backend.acquire(display: request.keepDisplay); tokenKeepsDisplay = request.keepDisplay; holding = true; error = nil }
            catch { self.error = error.localizedDescription; status = "Couldn't keep your Mac awake"; onReaction?(false); return }
        }
        status = request.keepDisplay ? "Mac and display stay awake" : "Mac stays awake; display may sleep"
    }
    func shutdown() { timer?.cancel(); timer = nil; relinquish(); notifications.forEach { notificationCenter?.removeObserver($0) }; notifications = []; notificationCenter = nil }
    private func relinquish() { if let token { backend.release(token) }; token = nil; holding = false }
    private func persist() { defaults.set(try? JSONEncoder().encode(request), forKey: "awake.request"); defaults.set(enabled, forKey: "awake.active") }
    private func startTimer() {
        timer?.cancel()
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled, let self else { return }; self.tick() }
        }
    }
}
