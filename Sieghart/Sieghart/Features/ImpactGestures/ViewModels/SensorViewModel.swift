import Foundation
import IOKit.hid
import SwiftUI

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
