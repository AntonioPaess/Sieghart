import AVFoundation
import Combine
import Foundation

/// System speech with a slightly lower tone and a calm pace by default.
struct SigVoiceConfiguration: Sendable, Equatable, Codable {
    var voiceIdentifier: String? = nil
    var pitchCents: Float = -100
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.94
    var volume: Float = 0.85
    var enabled: Bool = true

    static let sieg = SigVoiceConfiguration(voiceIdentifier: "microsoft.online.antonio", pitchCents: 0, rate: AVSpeechUtteranceDefaultSpeechRate * 0.97)

    var normalized: Self {
        var result = self
        result.pitchCents = pitchCents.isFinite ? min(300, max(-400, pitchCents)) : -100
        result.rate = rate.isFinite ? min(0.65, max(0.30, rate)) : AVSpeechUtteranceDefaultSpeechRate * 0.94
        result.volume = volume.isFinite ? min(1, max(0, volume)) : 0.85
        if result.voiceIdentifier?.isEmpty == true { result.voiceIdentifier = nil }
        return result
    }
}

struct SigVoiceOption: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let language: String
    let quality: Int
}

@MainActor enum SigVoiceCatalog {
    static let antonio = "microsoft.online.antonio"
    static let naturalMalePortuguese = "com.apple.siri.natural.Nando"

    static func installedOptions() -> [SigVoiceOption] {
        [SigVoiceOption(id: antonio, name: "Antônio · online", language: "pt-BR", quality: 4)] + AVSpeechSynthesisVoice.speechVoices()
            .filter { ["pt-BR", "pt-PT", "en-US"].contains($0.language)
                && !$0.voiceTraits.contains(.isNoveltyVoice)
                && AVSpeechSynthesisVoice(identifier: $0.identifier) != nil }
            .map { SigVoiceOption(id: $0.identifier, name: $0.identifier == naturalMalePortuguese ? "Nando · natural" : $0.name,
                         language: $0.language, quality: $0.quality.rawValue) }
            .sorted { left, right in
                let order = ["pt-BR": 0, "pt-PT": 1, "en-US": 2]
                if left.language != right.language { return (order[left.language] ?? 3) < (order[right.language] ?? 3) }
                if left.quality != right.quality { return left.quality > right.quality }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    static func resolve(identifier: String?, language: String) -> AVSpeechSynthesisVoice? {
        if let identifier, let selected = AVSpeechSynthesisVoice(identifier: identifier),
           selected.language.prefix(2) == language.prefix(2) { return selected }
        if language.hasPrefix("pt") {
            for identifier in [naturalMalePortuguese, "com.apple.eloquence.pt-BR.Reed", "com.apple.eloquence.pt-BR.Eddy"] {
                if let voice = AVSpeechSynthesisVoice(identifier: identifier) { return voice }
            }
        }
        return AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.prefix(2) == language.prefix(2) && !$0.voiceTraits.contains(.isNoveltyVoice) }
    }
}

@MainActor
protocol SigVoiceSynthesizing: AnyObject {
    var speaker: LocalChatPersona { get set }
    var supportsStreaming: Bool { get }
    var isSpeaking: Bool { get }
    var isPreparingAudio: Bool { get }
    var lastSpokenText: String? { get }
    var configuration: SigVoiceConfiguration { get set }
    func speak(_ text: String, language: String, onFinished: (@MainActor () -> Void)?)
    func beginStreaming(language: String, onFinished: (@MainActor () -> Void)?)
    func appendStreaming(_ snapshot: String)
    func finishStreaming(_ text: String, language: String)
    func stop()
}

extension SigVoiceSynthesizing {
    var isPreparingAudio: Bool { false }
    var speaker: LocalChatPersona { get { .sig } set {} }
    var supportsStreaming: Bool { false }
    func speak(_ text: String, language: String) { speak(text, language: language, onFinished: nil) }
    func beginStreaming(language: String, onFinished: (@MainActor () -> Void)?) { stop() }
    func appendStreaming(_ snapshot: String) {}
    func finishStreaming(_ text: String, language: String) { speak(text, language: language) }
}

/// Own the sample bytes before leaving AVSpeechSynthesizer's callback. No
/// framework-owned mutable buffer crosses into an asynchronous playback task.
struct SigVoicePCMChunk: Sendable {
    let sampleRate: Double
    let channels: AVAudioChannelCount
    let commonFormat: AVAudioCommonFormat
    let interleaved: Bool
    let frames: AVAudioFrameCount
    let samples: [Data]

    init?(copying buffer: AVAudioPCMBuffer) {
        let format = buffer.format
        guard buffer.frameLength > 0, format.channelCount > 0, format.sampleRate > 0 else { return nil }
        let byteCount = Int(buffer.frameLength) * Int(format.streamDescription.pointee.mBytesPerFrame)
        guard byteCount > 0 else { return nil }
        var samples: [Data] = []
        for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            guard let data = audioBuffer.mData, audioBuffer.mDataByteSize >= byteCount else { return nil }
            samples.append(Data(bytes: data, count: byteCount))
        }
        guard !samples.isEmpty else { return nil }
        self.sampleRate = format.sampleRate
        self.channels = format.channelCount
        self.commonFormat = format.commonFormat
        self.interleaved = format.isInterleaved
        self.frames = buffer.frameLength
        self.samples = samples
    }

    func makeBuffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: commonFormat, sampleRate: sampleRate,
                                         channels: channels, interleaved: interleaved),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let destination = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard destination.count == samples.count else { return nil }
        for (index, data) in samples.enumerated() {
            guard let target = destination[index].mData,
                  destination[index].mDataByteSize >= data.count else { return nil }
            data.copyBytes(to: UnsafeMutableRawBufferPointer(start: target, count: data.count))
        }
        return buffer
    }
}

/// The mixer converts to the output device; player and pitch keep the speech
/// buffer's exact channel count and sample rate (often mono at 22.05 kHz).
@MainActor
final class SigVoicePlaybackGraph {
    enum PlaybackError: Error { case incompatibleBuffer }
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let pitch = AVAudioUnitTimePitch()
    private let format: AVAudioFormat

    init(format: AVAudioFormat, pitchCents: Float) {
        self.format = format
        pitch.pitch = pitchCents
        pitch.rate = 1
        engine.attach(player)
        engine.attach(pitch)
        engine.connect(player, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
    }

    func schedule(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void) throws {
        guard buffer.frameLength > 0, buffer.format.isEqual(format),
              player.outputFormat(forBus: 0).isEqual(buffer.format) else { throw PlaybackError.incompatibleBuffer }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in completion() }
        if !player.isPlaying { player.play() }
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}

/// Synthesizes Sig's custom voice using `AVSpeechSynthesizer` routed through `AVAudioEngine`
/// with a user-adjustable `AVAudioUnitTimePitch` node.
/// Lazily initializes hardware audio output only when speaking, never touching microphone input.
@MainActor
final class SigVoiceSynthesizer: ObservableObject, SigVoiceSynthesizing {
    @Published var speaker: LocalChatPersona = .sig
    var supportsStreaming: Bool { true }
    @Published private(set) var isPreparingAudio = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var lastSpokenText: String?
    @Published private(set) var lastPlaybackIssue: String?
    @Published private(set) var activeVoiceIdentifier: String?
    @Published private(set) var activePitchCents: Float = -100
    @Published var configuration: SigVoiceConfiguration {
        didSet {
            if !configuration.normalized.enabled { stop() }
            playbackGraph?.pitch.pitch = configuration.normalized.pitchCents
            activePitchCents = configuration.normalized.pitchCents
        }
    }

    private let neuralService: any NeuralSpeechProviding
    private let neuralPlayer: any NeuralSpeechPlaying
    private var synthesizer: AVSpeechSynthesizer?
    private var playbackGraph: SigVoicePlaybackGraph?
    private var playbackTask: Task<Void, Never>?
    private var utteranceID = UUID()
    private var synthesisFinished = false
    private let playsHardwareAudio: Bool
    private var pendingBuffers = 0
    private var speechCompletion: (@MainActor () -> Void)?
    private var speechStream: SigSpeechStream?
    private var streamCompletion: (@MainActor () -> Void)?
    private var streaming = false
    private var streamLanguage = "pt-BR"
    private var streamSpeaker: LocalChatPersona = .sig

    init(
        configuration: SigVoiceConfiguration = .init(),
        playsHardwareAudio: Bool = false,
        neuralService: any NeuralSpeechProviding = EdgeNeuralSpeechService(),
        neuralPlayer: (any NeuralSpeechPlaying)? = nil
    ) {
        self.neuralService = neuralService
        self.neuralPlayer = neuralPlayer ?? SigNeuralAudioPlayer()
        self.configuration = configuration.normalized
        self.playsHardwareAudio = playsHardwareAudio
        self.activePitchCents = configuration.normalized.pitchCents
    }

    /// Inspects the effective pitch shift in cents.
    var configuredTimePitchCents: Float {
        playbackGraph?.pitch.pitch ?? configuration.normalized.pitchCents
    }

    func speak(_ text: String, language: String = "pt-BR", onFinished: (@MainActor () -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        let settings = configuration.normalized
        let speaker = self.speaker
        guard settings.enabled, !trimmed.isEmpty else { onFinished?(); return }
        speechCompletion = onFinished

        lastPlaybackIssue = nil
        activeVoiceIdentifier = settings.voiceIdentifier
        activePitchCents = settings.voiceIdentifier == SigVoiceCatalog.antonio ? 0 : settings.pitchCents
        lastSpokenText = trimmed
        isSpeaking = true

        guard playsHardwareAudio else {
            return
        }

        let requestID = utteranceID
        if settings.voiceIdentifier == SigVoiceCatalog.antonio {
            beginStreaming(language: language, onFinished: onFinished)
            appendStreaming(trimmed)
            finishStreaming(trimmed, language: language)
            return
        }
        isPreparingAudio = true
        speakSystem(trimmed, language: language, settings: settings, requestID: requestID)
    }

    func beginStreaming(language: String, onFinished: (@MainActor () -> Void)? = nil) {
        stop()
        isPreparingAudio = playsHardwareAudio
        streaming = true; streamCompletion = onFinished
        streamLanguage = language
        streamSpeaker = speaker
        lastSpokenText = nil
        let settings = configuration.normalized, id = utteranceID
        guard settings.enabled, playsHardwareAudio, settings.voiceIdentifier == SigVoiceCatalog.antonio else { return }
        speechStream = SigSpeechStream(provider: neuralService, player: neuralPlayer, language: language,
            rate: Int((settings.rate / AVSpeechUtteranceDefaultSpeechRate - 1) * 100), volume: settings.volume, speaker:streamSpeaker,
            began: { [weak self] in self?.isPreparingAudio = false },
            fallback: { [weak self] text, finished in
                guard let self, self.utteranceID == id else { return }
                self.synthesisFinished = false; self.pendingBuffers = 0
                self.speechCompletion = finished
                self.lastPlaybackIssue = language.hasPrefix("en") ? "Online voice unavailable. Using a voice from your Mac." : "Voz online indisponível. Usando uma voz do Mac."
                self.speakSystem(text, language: language, settings: settings, requestID: id)
            }, finished: { [weak self] in
                guard let self, self.utteranceID == id else { return }
                self.speechStream = nil; self.streaming = false; self.isSpeaking = false; self.isPreparingAudio = false
                let done = self.streamCompletion; self.streamCompletion = nil; done?()
            })
    }

    func appendStreaming(_ snapshot: String) {
        guard streaming, configuration.normalized.enabled else { return }
        lastSpokenText = snapshot; isSpeaking = !snapshot.isEmpty
        activeVoiceIdentifier = EdgeNeuralSpeechService.voice(for: streamLanguage,speaker:streamSpeaker)
        speechStream?.append(snapshot)
    }

    func finishStreaming(_ text: String, language: String) {
        guard streaming else { speak(text, language: language); return }
        lastSpokenText = text
        if let speechStream { speechStream.append(text, final: true) }
        else {
            let done = streamCompletion
            streaming = false; streamCompletion = nil
            speak(text, language: language, onFinished: done)
        }
    }

    private func speakSystem(_ text: String, language: String, settings: SigVoiceConfiguration, requestID: UUID) {
        let synthesizer = synthesizer ?? AVSpeechSynthesizer()
        self.synthesizer = synthesizer
        let utterance = AVSpeechUtterance(string: text)
        guard let voice = SigVoiceCatalog.resolve(identifier: settings.voiceIdentifier, language: language) else {
            lastPlaybackIssue = language.hasPrefix("en") ? "No installed voice is available for the selected language." : "Não há uma voz instalada disponível para o idioma escolhido."
            synthesisFinished = true; finishIfDrained(); return
        }
        utterance.voice = voice
        activeVoiceIdentifier = utterance.voice?.identifier
        utterance.rate = settings.rate
        utterance.volume = settings.volume
        // Pitch is applied once, in the playback graph, rather than twice.
        utterance.pitchMultiplier = 1.0

        let (stream, continuation) = AsyncStream<SigVoicePCMChunk>.makeStream()
        playbackTask = Task { @MainActor [weak self] in
            for await chunk in stream {
                guard !Task.isCancelled, let self, self.utteranceID == requestID else { return }
                self.enqueue(chunk, requestID: requestID)
            }
            guard !Task.isCancelled, let self, self.utteranceID == requestID else { return }
            self.synthesisFinished = true
            self.finishIfDrained()
        }
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer,
                  let chunk = SigVoicePCMChunk(copying: pcm) else {
                continuation.finish()
                return
            }
            continuation.yield(chunk)
        }
    }

    private func enqueue(_ chunk: SigVoicePCMChunk, requestID: UUID) {
        isPreparingAudio = false
        guard let buffer = chunk.makeBuffer() else { stop(); return }
        if playbackGraph == nil {
            playbackGraph = SigVoicePlaybackGraph(format: buffer.format, pitchCents: configuration.normalized.pitchCents)
        }
        pendingBuffers += 1
        do {
            try playbackGraph?.schedule(buffer) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.utteranceID == requestID else { return }
                    self.pendingBuffers -= 1
                    self.finishIfDrained()
                }
            }
        } catch {
            stop()
        }
    }

    private func finishIfDrained() {
        guard synthesisFinished, pendingBuffers == 0 else { return }
        if speechStream == nil { isSpeaking = false; isPreparingAudio = false }
        playbackGraph?.stop()
        playbackTask = nil
        let completion = speechCompletion
        speechCompletion = nil
        completion?()
    }

    func stop() {
        // Invalidate callbacks before stopping nodes, which can invoke pending completions.
        utteranceID = UUID()
        speechStream?.cancel(); speechStream = nil; streaming = false; streamCompletion = nil
        speechCompletion = nil
        playbackTask?.cancel()
        playbackTask = nil
        if isSpeaking {
            _ = synthesizer?.stopSpeaking(at: .immediate)
        }
        neuralPlayer.stop()
        playbackGraph?.stop()
        playbackGraph = nil
        pendingBuffers = 0
        synthesisFinished = false
        isSpeaking = false; isPreparingAudio = false
    }
}

@MainActor protocol NeuralSpeechPlaying: AnyObject {
    func play(_ audio: Data, volume: Float, onFinished: @escaping @MainActor () -> Void) throws
    func stop()
}

@MainActor final class SigNeuralAudioPlayer: NSObject, NeuralSpeechPlaying, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: (@MainActor () -> Void)?
    func play(_ audio: Data, volume: Float, onFinished: @escaping @MainActor () -> Void) throws {
        stop()
        let next = try AVAudioPlayer(data: audio)
        next.volume = volume
        next.delegate = self
        completion = onFinished
        player = next
        guard next.prepareToPlay(), next.play() else { stop(); throw NeuralSpeechError.noAudio }
    }
    func stop() { completion = nil; player?.delegate = nil; player?.stop(); player = nil }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identity else { return }
            let finished = self.completion
            self.completion = nil
            self.player = nil
            finished?()
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        audioPlayerDidFinishPlaying(player, successfully: false)
    }
}
