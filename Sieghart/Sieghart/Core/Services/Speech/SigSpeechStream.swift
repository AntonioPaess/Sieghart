import Foundation

/// Consumes cumulative model snapshots once, retaining incomplete sentences.
/// A decimal point does not split a number into different spoken fragments.
struct SpeechSentenceBuffer {
    private(set) var committed = ""
    private(set) var latest = ""
    mutating func append(_ snapshot: String, final: Bool = false) -> [String] {
        guard snapshot.hasPrefix(committed), snapshot.count <= 16_000 else { return [] }
        latest = snapshot
        var remaining = String(snapshot.dropFirst(committed.count))
        var output: [String] = []
        while !remaining.isEmpty {
            let characters = Array(remaining)
            var boundary: Int?
            for index in characters.indices {
                let c = characters[index]
                let decimal = c == "." && index > 0 && index+1 < characters.count && characters[index-1].isNumber && characters[index+1].isNumber
                if !decimal, ".!?\n".contains(c), index >= 18,
                   index+1 == characters.count || characters[index+1].isWhitespace { boundary = index+1; break }
                if index >= 320, c.isWhitespace { boundary = index+1; break }
            }
            if boundary == nil, final { boundary = characters.count }
            guard let boundary else { break }
            let raw = String(characters.prefix(boundary))
            committed += raw
            remaining = String(characters.dropFirst(boundary))
            let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { output.append(sentence) }
        }
        return output
    }
}

/// Fetches the next sentence while the current one plays. Only one response
/// owns the player; cancellation invalidates both pending data and callbacks.
@MainActor final class SigSpeechStream {
    typealias Fallback = @MainActor (String, @escaping @MainActor () -> Void) -> Void
    private let provider: any NeuralSpeechProviding
    private let player: any NeuralSpeechPlaying
    private let language: String
    private let speaker: LocalChatPersona
    private let rate: Int
    private let volume: Float
    private let began: (@MainActor () -> Void)?
    private let fallback: Fallback
    private var pending: [String] = []
    private var ready: [(String, Data?)] = []
    private var fetching: Task<Void, Never>?
    private var active = true
    private var playing = false
    private var inputFinished = false
    private var buffer = SpeechSentenceBuffer()
    private var finished: (@MainActor () -> Void)?

    init(provider: any NeuralSpeechProviding, player: any NeuralSpeechPlaying, language: String,
         rate: Int, volume: Float, speaker: LocalChatPersona = .sig, began: (@MainActor () -> Void)? = nil, fallback: @escaping Fallback, finished: @escaping @MainActor () -> Void) {
        self.provider = provider; self.player = player; self.language = language
        self.rate = rate; self.volume = volume; self.fallback = fallback; self.finished = finished
        self.speaker = speaker; self.began = began
    }
    func append(_ text: String, final: Bool = false) {
        guard active else { return }
        pending += buffer.append(text, final: final)
        inputFinished = inputFinished || final
        fetchIfNeeded()
        completeIfDrained()
    }
    func cancel() {
        active = false; fetching?.cancel(); fetching = nil
        pending = []; ready = []; finished = nil; player.stop()
    }
    private func fetchIfNeeded() {
        guard active, fetching == nil, !pending.isEmpty else { return }
        fetching = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.active, !Task.isCancelled, !self.pending.isEmpty {
                let text = self.pending.removeFirst()
                let data: Data?
                do { data = try await self.provider.audio(for: text, language: self.language, rate: self.rate, speaker:self.speaker) }
                catch is CancellationError { return }
                catch { data = nil }
                guard self.active, !Task.isCancelled else { return }
                self.ready.append((text, data))
                self.playNext()
            }
            self.fetching = nil
            self.completeIfDrained()
        }
    }
    private func playNext() {
        guard active, !playing, !ready.isEmpty else { return }
        let item = ready.removeFirst()
        playing = true; began?()
        let completion: @MainActor () -> Void = { [weak self] in
            guard let self, self.active else { return }
            self.playing = false; self.playNext(); self.completeIfDrained()
        }
        if let data = item.1 {
            do { try player.play(data, volume: volume, onFinished: completion) }
            catch { fallback(item.0, completion) }
        } else { fallback(item.0, completion) }
    }
    private func completeIfDrained() {
        guard active, inputFinished, fetching == nil, pending.isEmpty, ready.isEmpty, !playing else { return }
        active = false
        let callback = finished; finished = nil; callback?()
    }
}
