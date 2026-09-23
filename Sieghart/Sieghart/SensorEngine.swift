import Foundation
import IOKit.hid
import SwiftUI

struct AccelerationSample: Sendable {
    let timestamp: Date
    let x: Double
    let y: Double
    let z: Double

    var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }
}

struct ImpactEvent: Sendable {
    let timestamp: Date
    let intensity: Double
    let sample: AccelerationSample
}

enum AccelerometerError: LocalizedError {
    case mainRunLoopUnavailable
    case managerOpenFailed(IOReturn)
    case deviceNotFound
    case deviceOpenFailed(IOReturn)
    case malformedReport

    var errorDescription: String? {
        switch self {
        case .mainRunLoopUnavailable:
            return "The main run loop is unavailable."
        case .managerOpenFailed(let code):
            return "Unable to open the HID service (code \(code))."
        case .deviceNotFound:
            return "No compatible AppleSPUHIDDevice accelerometer was found."
        case .deviceOpenFailed(let code):
            return "The accelerometer was found but could not be opened (code \(code))."
        case .malformedReport:
            return "The sensor report has an unexpected format."
        }
    }
}

protocol AccelerometerProviding: AnyObject {
    var onSample: ((AccelerationSample) -> Void)? { get set }
    var isRunning: Bool { get }

    func start() throws
    func stop()
}

/// Experimental reader for the AppleSPUHIDDevice IMU.
///
/// This path is experimental and is not a public macOS motion API. The reader
/// is isolated so the data source can change without changing impact logic or
/// the interface.
final class IOKitAccelerometerReader: AccelerometerProviding, @unchecked Sendable {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var reportBufferCapacity = 0
    private(set) var isRunning = false

    var onSample: ((AccelerationSample) -> Void)?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        stop()
    }

    func start() throws {
        guard !isRunning else { return }

        wakeSPUDriver()

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: NSNumber(value: 0xFF00),
            kIOHIDDeviceUsageKey as String: NSNumber(value: 3)
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let runLoop = CFRunLoopGetMain() else {
            throw AccelerometerError.mainRunLoopUnavailable
        }
        let runLoopMode = CFRunLoopMode.defaultMode.rawValue as CFString
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, runLoopMode)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else {
            throw AccelerometerError.managerOpenFailed(managerResult)
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw AccelerometerError.deviceNotFound
        }

        guard let sensor = devices.first(where: isAccelerometer) else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw AccelerometerError.deviceNotFound
        }

        let reportedSize = (IOHIDDeviceGetProperty(
            sensor,
            kIOHIDMaxInputReportSizeKey as CFString
        ) as? NSNumber)?.intValue ?? 22
        let bufferCapacity = max(64, reportedSize)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferCapacity)
        buffer.initialize(repeating: 0, count: bufferCapacity)

        device = sensor
        reportBuffer = buffer
        reportBufferCapacity = bufferCapacity

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            sensor,
            buffer,
            bufferCapacity,
            { context, _, _, _, _, report, reportLength in
                guard let context else { return }
                let reader = Unmanaged<IOKitAccelerometerReader>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                reader.consume(report: report, length: reportLength)
            },
            context
        )

        IOHIDDeviceScheduleWithRunLoop(
            sensor,
            runLoop,
            runLoopMode
        )

        let deviceResult = IOHIDDeviceOpen(sensor, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            IOHIDDeviceRegisterInputReportCallback(sensor, buffer, bufferCapacity, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(sensor, runLoop, runLoopMode)
            buffer.deinitialize(count: bufferCapacity)
            buffer.deallocate()
            reportBuffer = nil
            reportBufferCapacity = 0
            device = nil
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, runLoopMode)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw AccelerometerError.deviceOpenFailed(deviceResult)
        }

        isRunning = true
    }

    func stop() {
        guard let sensor = device else { return }

        if let buffer = reportBuffer {
            IOHIDDeviceRegisterInputReportCallback(sensor, buffer, reportBufferCapacity, nil, nil)
            buffer.deinitialize(count: reportBufferCapacity)
            buffer.deallocate()
        }

        let runLoopMode = CFRunLoopMode.defaultMode.rawValue as CFString
        if let runLoop = CFRunLoopGetMain() {
            IOHIDDeviceUnscheduleFromRunLoop(sensor, runLoop, runLoopMode)
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, runLoopMode)
        }
        IOHIDDeviceClose(sensor, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        reportBuffer = nil
        reportBufferCapacity = 0
        device = nil
        isRunning = false
    }

    private func isAccelerometer(_ device: IOHIDDevice) -> Bool {
        let transport = (IOHIDDeviceGetProperty(
            device,
            kIOHIDTransportKey as CFString
        ) as? String)?.uppercased()
        let usage = (IOHIDDeviceGetProperty(
            device,
            kIOHIDPrimaryUsageKey as CFString
        ) as? NSNumber)?.intValue
        let reportSize = (IOHIDDeviceGetProperty(
            device,
            kIOHIDMaxInputReportSizeKey as CFString
        ) as? NSNumber)?.intValue ?? 0

        return transport == "SPU" && usage == 3 && reportSize >= 22
    }

    private func wakeSPUDriver() {
        // AppleSPUHIDDriver may expose the device before it starts streaming.
        // This experimental request asks it to publish at 8 ms; failure is
        // intentionally non-fatal because some systems already stream.
        guard let matching = IOServiceMatching("AppleSPUHIDDriver") else { return }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return
        }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            _ = IORegistryEntrySetCFProperty(
                service,
                "ReportInterval" as CFString,
                NSNumber(value: 8_000)
            )
            IOObjectRelease(service)
        }

        IOObjectRelease(iterator)
    }

    private func consume(report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        // AppleSPUHIDDevice reports currently observed by the project are 22
        // bytes. The three signed Q16 axes begin at offsets 6, 10 and 14.
        guard length >= 18 else { return }

        let x = decodeQ16(report.advanced(by: 6))
        let y = decodeQ16(report.advanced(by: 10))
        let z = decodeQ16(report.advanced(by: 14))
        let sample = AccelerationSample(timestamp: Date(), x: x, y: y, z: z)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onSample?(sample)
        }
    }

    private func decodeQ16(_ bytes: UnsafeMutablePointer<UInt8>) -> Double {
        let raw = UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
        return Double(Int32(bitPattern: raw)) / 65_536.0
    }
}

struct ImpactDetector {
    var sensitivity: Double = 0.08
    // Keep the cooldown short enough to recognize deliberate double impacts.
    var cooldown: TimeInterval = 0.22

    private var baseline = 1.0
    private var lastImpactAt: Date?

    mutating func process(_ sample: AccelerationSample) -> ImpactEvent? {
        let magnitude = sample.magnitude
        baseline += (magnitude - baseline) * 0.02
        let dynamicAcceleration = abs(magnitude - baseline)

        guard dynamicAcceleration >= sensitivity else { return nil }
        if let lastImpactAt, sample.timestamp.timeIntervalSince(lastImpactAt) < cooldown {
            return nil
        }

        self.lastImpactAt = sample.timestamp
        return ImpactEvent(
            timestamp: sample.timestamp,
            intensity: min(dynamicAcceleration, 1.0),
            sample: sample
        )
    }
}

@MainActor
final class SensorViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Sensor inactive"
    @Published private(set) var lastSample: AccelerationSample?
    @Published private(set) var lastImpact: ImpactEvent?
    @Published private(set) var sampleCount = 0

    var onImpact: ((ImpactEvent) -> Void)?

    private let reader: AccelerometerProviding
    private var detector = ImpactDetector()

    init(reader: AccelerometerProviding = IOKitAccelerometerReader()) {
        self.reader = reader
        reader.onSample = { [weak self] sample in
            Task { @MainActor [weak self] in
                self?.receive(sample)
            }
        }
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func startIfNeeded() {
        guard !isRunning else { return }
        start()
    }

    func start() {
        do {
            try reader.start()
            isRunning = true
            sampleCount = 0
            status = "Sensor active — waiting for the first report"
        } catch {
            isRunning = false
            status = error.localizedDescription
        }
    }

    func stop() {
        reader.stop()
        isRunning = false
        status = "Sensor inactive"
    }

    private func receive(_ sample: AccelerationSample) {
        guard isRunning else { return }
        sampleCount += 1
        lastSample = sample
        if sampleCount == 1 {
            status = "Sensor active — receiving reports"
        }
        if let impact = detector.process(sample) {
            lastImpact = impact
            status = "Impact detected — intensity \(impact.intensity.formatted(.number.precision(.fractionLength(2))))g"
            onImpact?(impact)
        }
    }
}
