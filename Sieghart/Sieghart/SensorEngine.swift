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
    case managerOpenFailed(IOReturn)
    case deviceNotFound
    case deviceOpenFailed(IOReturn)
    case malformedReport

    var errorDescription: String? {
        switch self {
        case .managerOpenFailed(let code):
            return "Não foi possível abrir o serviço HID (código \(code))."
        case .deviceNotFound:
            return "Nenhum acelerômetro AppleSPUHIDDevice compatível foi encontrado."
        case .deviceOpenFailed(let code):
            return "O acelerômetro foi encontrado, mas não pôde ser aberto (código \(code))."
        case .malformedReport:
            return "O relatório recebido do sensor tem um formato inesperado."
        }
    }
}

protocol AccelerometerProviding: AnyObject {
    var onSample: ((AccelerationSample) -> Void)? { get set }
    var isRunning: Bool { get }

    func start() throws
    func stop()
}

/// Leitor experimental da IMU AppleSPUHIDDevice.
///
/// O caminho é documentado como experimental e não é uma API pública de
/// movimento do macOS. O leitor fica isolado para podermos trocar a fonte
/// sem alterar a lógica de impacto ou a interface.
final class IOKitAccelerometerReader: AccelerometerProviding, @unchecked Sendable {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
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

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: NSNumber(value: 0xFF00),
            kIOHIDDeviceUsageKey as String: NSNumber(value: 3)
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else {
            throw AccelerometerError.managerOpenFailed(managerResult)
        }

        guard
            let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
            let sensor = devices.first
        else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw AccelerometerError.deviceNotFound
        }

        let deviceResult = IOHIDDeviceOpen(sensor, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw AccelerometerError.deviceOpenFailed(deviceResult)
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffer.initialize(repeating: 0, count: 64)

        device = sensor
        reportBuffer = buffer

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            sensor,
            buffer,
            64,
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
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue as CFString
        )

        isRunning = true
    }

    func stop() {
        guard let sensor = device else { return }

        if let buffer = reportBuffer {
            IOHIDDeviceRegisterInputReportCallback(sensor, buffer, 64, nil, nil)
            buffer.deinitialize(count: 64)
            buffer.deallocate()
        }

        IOHIDDeviceUnscheduleFromRunLoop(
            sensor,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue as CFString
        )
        IOHIDDeviceClose(sensor, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        reportBuffer = nil
        device = nil
        isRunning = false
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
    var cooldown: TimeInterval = 0.75

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
    @Published private(set) var status = "Sensor desligado"
    @Published private(set) var lastSample: AccelerationSample?
    @Published private(set) var lastImpact: ImpactEvent?

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

    func start() {
        do {
            try reader.start()
            isRunning = true
            status = "Sensor ativo — toque leve para testar"
        } catch {
            isRunning = false
            status = error.localizedDescription
        }
    }

    func stop() {
        reader.stop()
        isRunning = false
        status = "Sensor desligado"
    }

    private func receive(_ sample: AccelerationSample) {
        guard isRunning else { return }
        lastSample = sample
        if let impact = detector.process(sample) {
            lastImpact = impact
            status = "Impacto detectado — intensidade \(impact.intensity.formatted(.number.precision(.fractionLength(2))))g"
        }
    }
}
