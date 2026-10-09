import AppKit
import Combine
import IOKit.graphics
import IOBluetooth
import Darwin

@MainActor final class DisplayPowerViewModel: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var error: String?
    @Published var disconnectBluetoothOnSleep: Bool {
        didSet { defaults.set(disconnectBluetoothOnSleep, forKey: "power.bluetoothSleep") }
    }
    @Published var blockMusicAfterPlayKey: Bool {
        didSet { defaults.set(blockMusicAfterPlayKey, forKey: "power.blockMusic"); configureMusicMonitor() }
    }
    @Published private(set) var bluetoothStatus = "Bluetooth follows macOS settings"
    var onReaction: ((Bool) -> Void)?
    private let backend: any DisplayPowerBackend
    private let defaults: UserDefaults
    private var disconnected: Set<String> = []
    private var lifecycle: [NSObjectProtocol] = []
    private var displayObserver: NSObjectProtocol?
    private var mediaMonitor: Any?
    private var musicLaunchObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    @Published private(set) var musicBlockerReady = false
    private var lastPlayKey: TimeInterval? = nil
    init(backend: (any DisplayPowerBackend)? = nil, defaults: UserDefaults = .standard) {
        self.backend = backend ?? MacDisplayPowerBackend(); self.defaults = defaults
        disconnectBluetoothOnSleep = defaults.bool(forKey: "power.bluetoothSleep")
        blockMusicAfterPlayKey = defaults.bool(forKey: "power.blockMusic")
        if let native = self.backend as? MacDisplayPowerBackend {
            native.connectionResult = { [weak self] success in
                self?.bluetoothStatus = success ? "Bluetooth connection restored" : "A Bluetooth device couldn’t reconnect"
            }
        }
    }
    func refresh() { displays = backend.displays() }
    func startLifecycle() {
        guard lifecycle.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            lifecycle.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sleeps = note.name == NSWorkspace.willSleepNotification
                MainActor.assumeIsolated { if sleeps { self?.willSleep() } else { self?.didWake() } }
            })
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        appActiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.blockMusicAfterPlayKey && !self.musicBlockerReady { self.configureMusicMonitor() } }
        }
        configureMusicMonitor()
    }
    func setBrightness(_ value: Double, display: DisplayInfo) { perform { try backend.brightness(min(1, max(0, value)), display: display.id) }; refresh() }
    func setDimming(_ value: Double, display: DisplayInfo) { perform { try backend.dim(min(1, max(0.2, value)), display: display.id) }; refresh() }
    func restoreBrightness() { backend.restore(); refresh(); onReaction?(true) }
    func sleepDisplays() { perform { try backend.sleepDisplays() } }
    func willSleep() {
        backend.restore()
        guard disconnectBluetoothOnSleep else { return }
        for id in backend.connectedBluetooth() {
            do { try backend.disconnectBluetooth(id); disconnected.insert(id) }
            catch { self.error = error.localizedDescription }
        }
        bluetoothStatus = disconnected.isEmpty ? "No Bluetooth devices disconnected" : "Disconnected \(disconnected.count) devices for sleep"
    }
    func didWake() {
        // Ownership is per device: never connect a device that the user had
        // already disconnected, and never toggle the global Bluetooth radio.
        for id in disconnected {
            do { try backend.reconnectBluetooth(id) }
            catch { self.error = error.localizedDescription }
        }
        disconnected = []; bluetoothStatus = "Requested reconnection of owned Bluetooth devices"; refresh()
    }
    func allowMusicBlocker() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        configureMusicMonitor()
    }
    static func shouldBlockMusic(enabled: Bool, launch: TimeInterval, lastPlayKey: TimeInterval?) -> Bool {
        enabled && lastPlayKey.map { launch >= $0 && launch - $0 <= 2 } == true
    }
    private func configureMusicMonitor() {
        if let mediaMonitor { NSEvent.removeMonitor(mediaMonitor) }; mediaMonitor = nil
        musicBlockerReady = false
        if let musicLaunchObserver { NSWorkspace.shared.notificationCenter.removeObserver(musicLaunchObserver) }; musicLaunchObserver = nil
        guard blockMusicAfterPlayKey, AXIsProcessTrusted() else { return }
        mediaMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8, (event.data1 >> 16) & 0xFFFF == 16, (event.data1 >> 8) & 0xFF == 0xA else { return }
            MainActor.assumeIsolated { self?.lastPlayKey = event.timestamp }
        }
        musicBlockerReady = mediaMonitor != nil
        musicLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid, let app = NSRunningApplication(processIdentifier: pid),
                      app.bundleIdentifier == "com.apple.Music", Self.shouldBlockMusic(enabled: self.blockMusicAfterPlayKey, launch: ProcessInfo.processInfo.systemUptime, lastPlayKey: self.lastPlayKey) else { return }
                self.lastPlayKey = nil
                if !app.terminate() { self.error = "Music couldn't be closed" }
            }
        }
    }
    func shutdown() {
        backend.restore(); didWake()
        lifecycle.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; lifecycle = []
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }; displayObserver = nil
        if let appActiveObserver { NotificationCenter.default.removeObserver(appActiveObserver) }; appActiveObserver = nil
        if let mediaMonitor { NSEvent.removeMonitor(mediaMonitor) }; mediaMonitor = nil
        if let musicLaunchObserver { NSWorkspace.shared.notificationCenter.removeObserver(musicLaunchObserver) }; musicLaunchObserver = nil
    }
    private func perform(_ action: () throws -> Void) { do { try action(); error = nil; onReaction?(true) } catch { self.error = error.localizedDescription; onReaction?(false) } }
}
