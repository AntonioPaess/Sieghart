import AppKit
import Combine

struct ScreenGuidancePlan: Equatable, Sendable, Codable {
    struct Step: Equatable, Sendable, Codable {
        let instruction: String
        let targetText: String
        let expectedText: String
    }
    let title: String
    let steps: [Step]
    func validated() throws -> Self {
        guard !title.isEmpty, title.count <= 120, (1...15).contains(steps.count),
              steps.allSatisfy({ !$0.instruction.isEmpty && $0.instruction.count <= 300 && !$0.targetText.isEmpty && $0.targetText.count <= 100 && $0.expectedText.count <= 100 })
        else { throw SpatialContentError.invalidContent }
        return self
    }
}

/// A click only requests verification. Advancement requires a newly observed
/// expected label or disappearance of the clicked target. Manual completion is
/// explicitly recorded as the user's acknowledgement, not automatic verification.
@MainActor final class ScreenWalkthrough: ObservableObject {
    @Published private(set) var plan: ScreenGuidancePlan?
    @Published private(set) var index = 0
    @Published private(set) var isVerifying = false
    @Published private(set) var status = ""
    private var reading: ScreenSemanticReading?
    private var target: ScreenTextRegion?
    private var monitors: [Any] = []
    private var task: Task<Void, Never>?
    private var runID = UUID()
    private let overlay: SpatialOverlayViewModel
    private let inspector: any ScreenSemanticInspecting
    private let managesWindows: Bool
    private var language = "pt-BR"
    var onStep: (@MainActor (String, Bool) -> Void)?
    var isActive: Bool { plan != nil }

    init(overlay: SpatialOverlayViewModel, managesWindows: Bool) {
        self.overlay = overlay; self.inspector = overlay.inspector; self.managesWindows = managesWindows
    }
    var checkpoint: WalkthroughCheckpoint? { plan.map { .init(plan: $0, index: index) } }
    func start(_ plan: ScreenGuidancePlan, reading: ScreenSemanticReading, language: String, from step: Int = 0) throws {
        cancel()
        let checked = try plan.validated()
        guard checked.steps.indices.contains(step) else { throw SpatialContentError.invalidContent }
        self.plan = checked; self.reading = reading; self.language = language; index = step
        overlay.confirmGuidance = { [weak self] in self?.confirmCurrentStep() }
        overlay.refreshGuidance = { [weak self] in self?.refresh() }
        showStep()
        guard managesWindows else { return }
        let receive: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                let point = NSEvent.mouseLocation
                self?.clicked(globalAppKitPoint: point)
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: receive) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { event in receive(event); return event }) { monitors.append(local) }
    }
    func cancel() {
        runID = UUID(); task?.cancel(); task = nil; isVerifying = false
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        plan = nil; reading = nil; target = nil
        overlay.endGuidance()
    }
    func clicked(globalAppKitPoint point: CGPoint) {
        guard let frame = reading?.screenFrame, let target, !isVerifying else { return }
        let local = CGPoint(x: point.x-frame.minX, y: frame.maxY-point.y)
        guard target.frame.insetBy(dx: -8, dy: -8).contains(local) else { return }
        verify(manual: false)
    }
    func confirmCurrentStep() { verify(manual: true) }
    func refresh() {
        guard isActive, !isVerifying else { return }
        let id = runID
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.runID == id, !Task.isCancelled else { return }
            self.isVerifying = true
            let fresh = await self.inspector.inspectAtCursor(query: "Refresh user-requested walkthrough")
            guard self.runID == id, !Task.isCancelled else { return }
            self.isVerifying = false
            if fresh.failure == nil { self.reading = fresh; self.showStep() }
            else { self.status = fresh.explanation(language: self.language); self.overlay.guidanceStatus = self.status }
        }
    }
    private func verify(manual: Bool) {
        guard let plan, index < plan.steps.count, let previous = reading, !isVerifying else { return }
        let id = runID, step = plan.steps[index]
        isVerifying = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            if !manual { do { try await Task.sleep(for: .milliseconds(450)) } catch { return } }
            guard self.runID == id, !Task.isCancelled else { return }
            let fresh = await self.inspector.inspectAtCursor(query: "Verify the user's walkthrough step")
            guard self.runID == id, !Task.isCancelled else { return }
            self.isVerifying = false
            guard fresh.failure == nil else { self.status = fresh.explanation(language: self.language); self.overlay.guidanceStatus = self.status; return }
            let expectedNow = Self.matches(step.expectedText, in: fresh.textRegions)
            let expectedBefore = Self.matches(step.expectedText, in: previous.textRegions)
            let targetGone = Self.matches(step.targetText, in: fresh.textRegions) == nil && !fresh.textRegions.isEmpty
            guard manual || (expectedNow != nil && expectedBefore == nil) || targetGone else {
                self.status = self.language.hasPrefix("en") ? "I haven't confirmed the change yet. Retry, refresh, or confirm the step yourself." : "Ainda não confirmei a mudança. Tente novamente, atualize a tela ou confirme a etapa."
                self.overlay.guidanceStatus = self.status; return
            }
            self.index += 1; self.reading = fresh
            if self.index >= plan.steps.count {
                let text = self.language.hasPrefix("en") ? "Walkthrough completed." : "Orientação concluída."
                self.cancel(); self.overlay.dismiss(); self.status = text; self.onStep?(text, true)
            } else { self.showStep(); self.onStep?(self.status, false) }
        }
    }
    private func showStep() {
        guard let plan, index < plan.steps.count, let reading else { return }
        let step = plan.steps[index]
        target = Self.matches(step.targetText, in: reading.textRegions)
        status = "\(index+1)/\(plan.steps.count) · \(step.instruction)"
        overlay.guidanceStatus = status
        if let target, let frame = reading.screenFrame {
            overlay.highlightGuidance(target, screenFrame: frame, title: plan.title, language: language)
        } else {
            overlay.hideGuidanceHighlight()
            status += language.hasPrefix("en") ? " The target isn't visible; navigate or scroll, then refresh." : " O alvo não está visível; navegue ou role a página e atualize."
            overlay.guidanceStatus = status
        }
    }
    static func matches(_ target: String, in regions: [ScreenTextRegion]) -> ScreenTextRegion? {
        func clean(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US")).trimmingCharacters(in: .whitespacesAndNewlines) }
        let value = clean(target)
        guard !value.isEmpty else { return nil }
        return regions.first { clean($0.text) == value }
            ?? regions.filter { clean($0.text).contains(value) }.min { $0.text.count < $1.text.count }
    }
}
