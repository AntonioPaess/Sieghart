import Combine
import Foundation

enum FileReceptionPhase: Equatable { case idle, hovering, receiving, processing, ready, failed }

@MainActor final class FileReceptionViewModel: ObservableObject {
    // Toni owns files and communication; Sig remains the main orchestrator.
    let owner = CompanionAvatar.toni
    @Published private(set) var phase = FileReceptionPhase.idle { didSet { if phase != oldValue { onPhaseChange?(phase) } } }
    @Published private(set) var position = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var attached: [FileReference] = []
    @Published private(set) var status = "Drop it here."
    @Published private(set) var replay = 0
    var onPhaseChange: ((FileReceptionPhase) -> Void)?
    var onAbandonDrag: (() -> Void)?
    private let files: FilesViewModel
    private let reader: any FileDropReading
    private let pause: @Sendable (Duration) async throws -> Void
    private let shouldAnimate: @MainActor () -> Bool
    private var sequence: Int?
    private var generation = 0
    private var action: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    init(files: FilesViewModel, reader: any FileDropReading = NativeFileDropReader(),
         pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, shouldAnimate: @escaping @MainActor () -> Bool = { true }) {
        self.files = files; self.reader = reader; self.pause = pause; self.shouldAnimate = shouldAnimate
    }
    var receiving: Bool { phase == .hovering || phase == .receiving || phase == .processing }
    var animation: CompanionAnimation {
        switch phase { case .hovering: .fileOpen; case .receiving: .fileReceive; case .processing: .fileProcessing; default: .idle }
    }
    func enter(sequence id: Int, position: CGPoint) {
        exitTask?.cancel()
        if sequence != id {
            generation += 1; action?.cancel(); sequence = id; replay += 1
            status = "Drop it here. Your original stays in place."; phase = .hovering
        }
        move(sequence: id, position: position)
    }
    func move(sequence id: Int, position point: CGPoint) {
        guard sequence == id, phase == .hovering, point.x.isFinite, point.y.isFinite else { return }
        // Subpixel quantization avoids redundant updates while following both axes.
        let point = CGPoint(x: (min(1, max(0, point.x)) * 1000).rounded() / 1000,
                            y: (min(1, max(0, point.y)) * 1000).rounded() / 1000)
        if position != point { position = point }
    }
    func exit(sequence id: Int) {
        guard sequence == id, phase == .hovering else { return }
        exitTask?.cancel()
        exitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self, self.sequence == id, self.phase == .hovering else { return }
            self.sequence = nil; self.onAbandonDrag?(); self.phase = self.attached.isEmpty ? .idle : .ready
        }
    }
    func receive(sequence id: Int, pasteboard: String, changeCount: Int) -> Bool {
        guard sequence == id, phase == .hovering else { return false }
        let reader = reader
        start { try await reader.read(pasteboard: pasteboard, changeCount: changeCount) }
        return true
    }
    func receive(_ urls: [URL]) {
        generation += 1; action?.cancel(); sequence = nil
        start { urls }
    }
    private func start(_ input: @escaping @Sendable () async throws -> [URL]) {
        exitTask?.cancel(); generation += 1; let version = generation
        action?.cancel(); replay += 1; status = "Keeping it nearby…"; phase = .receiving
        let clock = ContinuousClock.now
        action = Task { [weak self] in
            guard let self else { return }
            do {
                let urls = try await input()
                guard !urls.isEmpty, urls.count <= 40, urls.allSatisfy(\.isFileURL) else { throw FileToolError.unsupported }
                var refs: [FileReference] = []
                for url in urls {
                    try Task.checkCancellation()
                    let reference = try await self.files.access.reference(for: url)
                    if !refs.contains(where: { $0.resourceID == reference.resourceID }) { refs.append(reference) }
                    try Task.checkCancellation()
                }
                guard self.generation == version else { return }
                let elapsed = clock.duration(to: .now)
                let intake: Duration = self.shouldAnimate() ? .milliseconds(1300) : .zero
                if elapsed < intake { try await self.pause(intake - elapsed) }
                try Task.checkCancellation(); guard self.generation == version else { return }
                let kept = await self.files.addPrepared(refs, announce: false)
                try Task.checkCancellation(); guard self.generation == version else { return }
                guard !kept.isEmpty else { throw FileToolError.message(self.files.status) }
                self.attached = kept; self.sequence = nil; self.position = CGPoint(x: 0.5, y: 0.5)
                self.status = kept.count == refs.count ? "What should we do with \(kept.count == 1 ? "this file" : "these files")?" : "\(kept.count) files kept. The shelf has reached its limit."
                self.phase = .ready
                self.files.events.post(.fileReceived, key: "companion-drop:\(UUID())", title: kept.count == 1 ? "File received" : "\(kept.count) files received", detail: kept.prefix(3).map(\.name).joined(separator: ", "))
            } catch {
                guard !Task.isCancelled, self.generation == version else { return }
                self.sequence = nil; self.status = error.localizedDescription; self.phase = .failed
            }
        }
        // Show loading only if actual bookmark/persistence work outlasts intake.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard let self, self.generation == version, self.phase == .receiving else { return }
            self.phase = .processing
        }
    }
    func clear() { generation += 1; action?.cancel(); exitTask?.cancel(); sequence = nil; attached = []; phase = .idle }
    func cancel() { generation += 1; action?.cancel(); exitTask?.cancel(); sequence = nil; phase = attached.isEmpty ? .idle : .ready }
    func waitForAction() async { await action?.value }
}
