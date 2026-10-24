import Foundation
import Combine

/// Barge-in uses recognized near-end words after system voice processing, not
/// raw speaker level alone. A repeated copy of Sieg's words is treated as echo.
struct ConversationInterruptionGate {
    private(set) var interrupted = false
    mutating func reset() { interrupted = false }
    static func isLikelyEcho(_ recognized: String, spoken: String) -> Bool {
        func words(_ text: String) -> Set<String> {
            Set(text.folding(options: [.caseInsensitive,.diacriticInsensitive], locale: .init(identifier: "en_US"))
                .components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty })
        }
        let incoming = words(recognized), outgoing = words(spoken)
        return !incoming.isEmpty && !outgoing.isEmpty && Double(incoming.intersection(outgoing).count)/Double(incoming.count) >= 0.8
    }
    mutating func shouldInterrupt(recognized: String, spoken: String, assistantBusy: Bool) -> Bool {
        guard assistantBusy, !interrupted else { return false }
        func words(_ text: String) -> [String] {
            text.folding(options: [.caseInsensitive,.diacriticInsensitive], locale: .init(identifier: "en_US"))
                .components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let incoming = words(recognized), outgoing = words(spoken)
        guard !incoming.isEmpty else { return false }
        let stopWords: Set<String> = ["pare","para","stop","chega","cancelar","cancela","cancel"]
        let explicitStop = incoming.count <= 3 && !Set(incoming).isDisjoint(with: stopWords)
        guard incoming.count >= 2 || explicitStop else { return false }
        let overlap = Set(incoming).intersection(Set(outgoing)).count
        if !outgoing.isEmpty, Double(overlap)/Double(Set(incoming).count) >= 0.8 { return false }
        interrupted = true; return true
    }
}

/// Explicit-session microphone ownership. Never starts from initialization,
/// app launch, a saved preference or a typed message.
@MainActor final class VoiceConversationController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isPreparing = false
    @Published private(set) var transcript = ""
    @Published private(set) var status = ""
    var onUtterance: (@MainActor (String) -> Void)?
    var onInterruption: (@MainActor () -> Void)?
    var assistantState: (@MainActor () -> (busy: Bool, spoken: String))?
    private let capture: any VoiceCapturing
    private let now: @MainActor () -> TimeInterval
    private var language = "en-US"
    private var session = VoiceCommandSession()
    private var gate = ConversationInterruptionGate()
    private var lifecycle: Task<Void,Never>?
    private var preparation: Task<Void,Never>?
    private var generation = UUID()
    private var captureID = UUID()
    private var startedAt: TimeInterval = 0
    private var lastActivityAt: TimeInterval = 0
    private var finalizing = false

    init(capture: any VoiceCapturing = NativeVoiceCapture(), now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.capture = capture; self.now = now
    }
    func start(language: String) {
        stop()
        self.language = language
        let id = generation
        isPreparing = true
        status = english ? "Preparing conversation…" : "Preparando conversa…"
        preparation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard self.generation == id, !Task.isCancelled else { return }
                try await self.capture.prepareAccess()
                guard self.generation == id, !Task.isCancelled else { return }
                self.capture.useVoiceProcessing(true)
                self.isPreparing = false; self.isActive = true
                self.startedAt = self.now(); self.lastActivityAt = self.startedAt
                try self.beginCapture()
                self.lifecycle = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                        guard let self, self.generation == id, self.isActive else { return }
                        self.checkEndpoint()
                    }
                }
            } catch {
                guard self.generation == id else { return }
                self.stop(); self.status = error.localizedDescription
            }
        }
    }
    func stop() {
        generation = UUID(); captureID = UUID()
        preparation?.cancel(); preparation = nil
        lifecycle?.cancel(); lifecycle = nil
        capture.cancel(); capture.useVoiceProcessing(false)
        session.cancel(); gate.reset(); finalizing = false
        isActive = false; isPreparing = false; transcript = ""
        status = english ? "Conversation ended" : "Conversa encerrada"
    }
    private var english: Bool { language.hasPrefix("en") }
    private func beginCapture() throws {
        guard isActive else { return }
        captureID = UUID(); let id = captureID
        session.start(at: now()); gate.reset(); finalizing = false; transcript = ""
        status = english ? "Microphone on · You can interrupt Sieg · Stop to end" : "Microfone ligado · Você pode interromper o Sieg · Pare para encerrar"
        try capture.start(language: language) { [weak self] event in
            guard let self, self.isActive, self.captureID == id else { return }
            switch event {
            case .level(let level):
                self.session.observe(decibels: level.decibels, duration: level.duration, at: level.time)
            case .recognition(let text, let final):
                self.transcript = text
                self.session.recognize(text, final: final, at: self.now())
                if !text.isEmpty { self.lastActivityAt = self.now() }
                let state = self.assistantState?() ?? (busy: false, spoken: "")
                if self.gate.shouldInterrupt(recognized: text, spoken: state.spoken, assistantBusy: state.busy) { self.onInterruption?() }
                if final {
                    if !self.finalizing { self.finishCapture() }
                    else { self.deliverFinal() }
                }
            case .inputChanged:
                self.stop(); self.status = self.english ? "Audio device changed. Start the conversation again." : "O dispositivo de áudio mudou. Inicie a conversa novamente."
            case .failure(let message):
                self.stop(); self.status = message
            }
        }
    }
    func checkEndpoint() {
        guard isActive else { return }
        let time = now(), state = assistantState?() ?? (busy: false, spoken: "")
        if state.busy { lastActivityAt = time }
        if time-startedAt >= 600 || time-lastActivityAt >= 60 {
            stop(); status = english ? "Conversation ended after inactivity or the session limit." : "Conversa encerrada por inatividade ou limite da sessão."; return
        }
        let decision = session.decision(at: time)
        switch decision {
        case .endAudio: finishCapture()
        case .noSpeech, .limitReached:
            // A recognizer request is bounded. Only a silent request is rotated;
            // partial unconfirmed actions are never dispatched.
            if transcript.isEmpty {
                capture.cancel()
                do { try beginCapture() } catch { stop(); status = error.localizedDescription }
            } else { finishCapture() }
        case .inputLost, .finalResultTimedOut:
            stop(); status = english ? "Couldn't finish hearing you. Start again; no partial command was run." : "Não consegui concluir a escuta. Inicie novamente; nenhum comando parcial foi executado."
        case .wait: break
        }
    }
    private func finishCapture() {
        guard !finalizing else { return }
        finalizing = true; session.endAudio(at: now()); capture.finish(); deliverFinal()
    }
    private func deliverFinal() {
        guard let text = session.takeFinalCommand() else { return }
        capture.cancel()
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = assistantState?() ?? (busy: false, spoken: "")
        if !cleaned.isEmpty, !(state.busy && ConversationInterruptionGate.isLikelyEcho(cleaned, spoken: state.spoken)) {
            let normalized = cleaned.folding(options: [.caseInsensitive,.diacriticInsensitive], locale: .init(identifier: "en_US"))
            if ["encerrar conversa","encerre a conversa","parar conversa","end conversation","stop conversation"].contains(normalized.trimmingCharacters(in: .punctuationCharacters)) { stop(); return }
            onUtterance?(cleaned)
        }
        guard isActive else { return }
        do { try beginCapture() } catch { stop(); status = error.localizedDescription }
    }
}
