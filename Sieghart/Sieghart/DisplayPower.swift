import AppKit
import Combine
import IOKit.graphics
import IOBluetooth
import Darwin

struct DisplayInfo: Identifiable, Equatable {
    var id: CGDirectDisplayID
    var name: String
    var builtIn: Bool
    var brightness: Double?
    var dimming: Double = 1
    var hdrHeadroom: Double = 1
}
@MainActor protocol DisplayPowerBackend: AnyObject {
    func displays() -> [DisplayInfo]
    func brightness(_ value: Double, display: CGDirectDisplayID) throws
    func dim(_ value: Double, display: CGDirectDisplayID) throws
    func restore()
    func sleepDisplays() throws
    func connectedBluetooth() -> [String]
    func disconnectBluetooth(_ id: String) throws
    func reconnectBluetooth(_ id: String) throws
}
@MainActor final class DisplayPowerController: ObservableObject {
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

@MainActor final class MacDisplayPowerBackend: NSObject, DisplayPowerBackend {
    var connectionResult: ((Bool) -> Void)?
    private typealias BrightnessGetter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias BrightnessSetter = @convention(c) (UInt32, Float) -> Int32
    private lazy var displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private func brightnessValue(_ id: CGDirectDisplayID) -> Double? {
        guard let handle = displayServices, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        guard unsafeBitCast(symbol, to: BrightnessGetter.self)(id, &value) == 0 else { return nil }
        return Double(value)
    }
    private var originalGamma: [CGDirectDisplayID: ([Float], [Float], [Float])] = [:]
    private var dimming: [CGDirectDisplayID: Double] = [:]
    func displays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            return DisplayInfo(id: id, name: screen.localizedName, builtIn: CGDisplayIsBuiltin(id) != 0, brightness: brightnessValue(id), dimming: dimming[id] ?? 1, hdrHeadroom: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue))
        }
    }
    func brightness(_ value: Double, display: CGDirectDisplayID) throws {
        guard let handle = displayServices, let symbol = dlsym(handle, "DisplayServicesSetBrightness"),
              unsafeBitCast(symbol, to: BrightnessSetter.self)(display, Float(value)) == 0 else {
            throw UtilityFailure(message: "Hardware brightness isn't available for this display. Use software dimming instead.")
        }
    }
    func dim(_ value: Double, display: CGDirectDisplayID) throws {
        if originalGamma[display] == nil {
            let capacity = CGDisplayGammaTableCapacity(display)
            guard capacity > 0 else { throw UtilityFailure(message: "This display doesn't support software dimming") }
            var red = [Float](repeating: 0, count: Int(capacity)), green = red, blue = red, count: UInt32 = 0
            guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success, count > 0 else { throw UtilityFailure(message: "Couldn't read the display's current color table") }
            originalGamma[display] = (Array(red.prefix(Int(count))), Array(green.prefix(Int(count))), Array(blue.prefix(Int(count))))
        }
        guard let baseline = originalGamma[display] else { return }
        let gain = Float(min(1, max(0.2, value)))
        guard CGSetDisplayTransferByTable(display, UInt32(baseline.0.count), baseline.0.map { $0 * gain }, baseline.1.map { $0 * gain }, baseline.2.map { $0 * gain }) == .success else { throw UtilityFailure(message: "macOS couldn't apply software dimming") }
        dimming[display] = Double(gain)
        if gain == 1 { originalGamma.removeValue(forKey: display) }
    }
    func restore() {
        for (id, baseline) in originalGamma { _ = CGSetDisplayTransferByTable(id, UInt32(baseline.0.count), baseline.0, baseline.1, baseline.2) }
        originalGamma = [:]; dimming = [:]
    }
    func sleepDisplays() throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); process.arguments = ["displaysleepnow"]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UtilityFailure(message: "macOS couldn't put the displays to sleep") }
    }
    func connectedBluetooth() -> [String] { (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }.compactMap(\.addressString) }
    func disconnectBluetooth(_ id: String) throws {
        guard let device = IOBluetoothDevice(addressString: id), device.closeConnection() == kIOReturnSuccess else { throw UtilityFailure(message: "Couldn't disconnect a Bluetooth device") }
    }
    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) { connectionResult?(status == kIOReturnSuccess) }
    func reconnectBluetooth(_ id: String) throws {
        guard let device = IOBluetoothDevice(addressString: id) else { throw UtilityFailure(message: "Couldn’t resolve a Bluetooth device") }
        if device.isConnected() { return }
        guard device.openConnection(self, withPageTimeout: 4096, authenticationRequired: true) == kIOReturnSuccess else { throw UtilityFailure(message: "Couldn’t request Bluetooth reconnection") }
    }
}
