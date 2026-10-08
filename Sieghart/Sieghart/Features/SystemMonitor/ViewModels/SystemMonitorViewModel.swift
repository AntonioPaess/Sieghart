import AppKit
import Combine
import IOKit
import IOKit.ps
import Darwin

@MainActor final class SystemMonitorViewModel: ObservableObject {
    @Published private(set) var reading = MonitorReading()
    @Published private(set) var history: [MonitorReading] = []
    let backend: any SystemSampling
    private var task: Task<Void, Never>?
    private var observers = 0
    var onReading: ((MonitorReading) -> Void)?
    init(backend: (any SystemSampling)? = nil) { self.backend = backend ?? MacSystemSampler() }
    func refresh() {
        var next = backend.read()
        next.derive(from: reading.sampledAt == nil ? nil : reading.counters)
        reading = next
        history.append(next); history = Array(history.suffix(60))
        onReading?(next)
    }
    func observe() {
        observers += 1; refresh()
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }
    func stopObserving() {
        observers = max(0, observers - 1)
        if observers == 0 { task?.cancel(); task = nil }
    }
}
