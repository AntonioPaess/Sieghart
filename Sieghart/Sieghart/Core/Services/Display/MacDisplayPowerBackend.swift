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
