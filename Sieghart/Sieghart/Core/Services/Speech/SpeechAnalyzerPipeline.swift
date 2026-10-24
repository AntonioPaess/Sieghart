import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Snapshot emitted by the continuous `SpeechAnalyzer` pipeline (`AsyncSequence`).
/// Combines finalized segments with live volatile transcripts for real-time text morphing.
struct SpeechTranscriptSnapshot: Sendable, Equatable {
    let finalizedText: String
    let volatileText: String
    let isFinal: Bool
    let speechDetected: Bool
    let timestamp: TimeInterval

    var combinedText: String {
        let trimmedFinal = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVolatile = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFinal.isEmpty { return trimmedVolatile }
        if trimmedVolatile.isEmpty { return trimmedFinal }
        return trimmedFinal + " " + trimmedVolatile
    }
}

/// Pure state reducer that reconciles volatile and finalized `DictationTranscriber` segments
/// alongside native `SpeechDetector` (VAD) state.
struct SpeechTranscriptAccumulator: Sendable, Equatable {
    private(set) var finalizedSegments: [String] = []
    private(set) var volatileSegment: String = ""
    private(set) var speechDetected: Bool = false

    mutating func ingestTranscriberSegment(
        text: String,
        isVolatile: Bool,
        at timestamp: TimeInterval
    ) -> SpeechTranscriptSnapshot {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVolatile {
            volatileSegment = cleaned
            if !cleaned.isEmpty { speechDetected = true }
        } else {
            if !cleaned.isEmpty {
                finalizedSegments.append(cleaned)
            }
            volatileSegment = ""
        }
        return snapshot(isFinal: !isVolatile && !cleaned.isEmpty, at: timestamp)
    }

    mutating func ingestVAD(speechDetected: Bool, at timestamp: TimeInterval) -> SpeechTranscriptSnapshot {
        self.speechDetected = speechDetected
        return snapshot(isFinal: false, at: timestamp)
    }

    mutating func finalizePendingVolatile(at timestamp: TimeInterval) -> SpeechTranscriptSnapshot {
        if !volatileSegment.isEmpty {
            finalizedSegments.append(volatileSegment)
            volatileSegment = ""
        }
        speechDetected = false
        return snapshot(isFinal: true, at: timestamp)
    }

    mutating func reset() {
        finalizedSegments.removeAll()
        volatileSegment = ""
        speechDetected = false
    }

    func snapshot(isFinal: Bool, at timestamp: TimeInterval) -> SpeechTranscriptSnapshot {
        SpeechTranscriptSnapshot(
            finalizedText: finalizedSegments.joined(separator: " "),
            volatileText: volatileSegment,
            isFinal: isFinal,
            speechDetected: speechDetected,
            timestamp: timestamp
        )
    }
}

// Thread-safe audio buffer bridge feeding `AnalyzerInput` to `SpeechAnalyzer`.
@available(macOS 26.0, *)
final class SpeechAnalyzerAudioFeed: @unchecked Sendable {
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat?
    private let lock = NSLock()
    private var isOpen = true
    private let onLevel: @Sendable (SpeechAudioLevel) -> Void

    init(
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat?,
        onLevel: @escaping @Sendable (SpeechAudioLevel) -> Void
    ) {
        self.continuation = continuation
        self.targetFormat = targetFormat
        if let targetFormat, inputFormat != targetFormat {
            self.converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        } else {
            self.converter = nil
        }
        self.onLevel = onLevel
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard isOpen else {
            lock.unlock()
            return
        }
        let level = SpeechAudioLevel.measure(buffer, at: ProcessInfo.processInfo.systemUptime)
        if let converter, let targetFormat {
            let ratio = targetFormat.sampleRate / max(1, buffer.format.sampleRate)
            let capacity = AVAudioFrameCount(max(1, ceil(Double(buffer.frameLength) * ratio)))
            if let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) {
                var error: NSError?
                var provided = false
                converter.convert(to: converted, error: &error) { _, outStatus in
                    if provided {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    provided = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                if error == nil, converted.frameLength > 0 {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            }
        } else {
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        lock.unlock()
        if let level { onLevel(level) }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen else { return }
        isOpen = false
        continuation.finish()
    }
}

/// Native macOS 26+ continuous speech pipeline powered by `SpeechAnalyzer`,
/// `DictationTranscriber` (with volatile real-time streaming) and `SpeechDetector` (native VAD).
@available(macOS 26.0, *)
@MainActor
final class SpeechAnalyzerPipeline: VoiceCapturing {
    private var engine: AVAudioEngine?
    private var engineObserver: NSObjectProtocol?
    private var feed: SpeechAnalyzerAudioFeed?
    private var analyzer: SpeechAnalyzer?
    private var transcriberTask: Task<Void, Never>?
    private var detectorTask: Task<Void, Never>?
    private var analyzerStartTask: Task<Void, Never>?
    private var hasTap = false
    private var generation = 0
    private var accumulator = SpeechTranscriptAccumulator()
    private var streamContinuation: AsyncStream<SpeechTranscriptSnapshot>.Continuation?
    private(set) var latestSnapshot = SpeechTranscriptSnapshot(
        finalizedText: "",
        volatileText: "",
        isFinal: false,
        speechDetected: false,
        timestamp: 0
    )

    /// Exposes a real-time `AsyncSequence` of volatile and finalized transcript snapshots.
    func makeTranscriptStream() -> AsyncStream<SpeechTranscriptSnapshot> {
        streamContinuation?.finish()
        return AsyncStream { [weak self] continuation in
            self?.streamContinuation = continuation
        }
    }

    func prepareAccess() async throws {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined {
            guard await SpeechAuthorizationBridge.request() == .authorized else {
                throw VoiceCaptureFailure.speechAccess
            }
        } else if speechStatus != .authorized {
            throw VoiceCaptureFailure.speechAccess
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw VoiceCaptureFailure.microphoneAccess
            }
        } else if micStatus != .authorized {
            throw VoiceCaptureFailure.microphoneAccess
        }
    }

    func start(language: String, receive: @escaping @MainActor (VoiceCaptureEvent) -> Void) throws {
        cancel()
        let token = generation
        let requestedLocale = Locale(identifier: language)

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let hardware = input.inputFormat(forBus: 0)
        let naturalFormat = input.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0,
              naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
            cancel()
            throw VoiceCaptureFailure.inputUnavailable
        }

        let transcriber = DictationTranscriber(
            locale: requestedLocale,
            contentHints: [.shortForm],
            transcriptionOptions: [.punctuation],
            reportingOptions: [.volatileResults, .frequentFinalization],
            attributeOptions: [.audioTimeRange]
        )
        let detector = SpeechDetector(
            detectionOptions: .init(sensitivityLevel: .medium),
            reportResults: true
        )
        let modules: [any SpeechModule] = [transcriber, detector]
        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer
        self.accumulator.reset()

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let feed = SpeechAnalyzerAudioFeed(
            continuation: inputContinuation,
            inputFormat: naturalFormat,
            targetFormat: nil
        ) { @Sendable [weak self] level in
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                receive(.level(level))
            }
        }
        self.feed = feed

        input.installTap(onBus: 0, bufferSize: 1024, format: naturalFormat) { @Sendable buffer, _ in
            feed.append(buffer)
        }
        hasTap = true

        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                receive(.inputChanged)
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }

        transcriberTask = Task { @MainActor [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    let rawText = String(result.text.characters)
                    let isVolatile = CMTimeCompare(result.range.end, result.resultsFinalizationTime) > 0
                    let now = ProcessInfo.processInfo.systemUptime
                    let snapshot = self.accumulator.ingestTranscriberSegment(
                        text: rawText,
                        isVolatile: isVolatile,
                        at: now
                    )
                    self.latestSnapshot = snapshot
                    self.streamContinuation?.yield(snapshot)
                    let combined = snapshot.combinedText
                    if !combined.isEmpty {
                        receive(.recognition(text: combined, final: snapshot.isFinal))
                    }
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                receive(.failure(error.localizedDescription))
            }
        }

        detectorTask = Task { @MainActor [weak self] in
            do {
                for try await vadResult in detector.results {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    let snapshot = self.accumulator.ingestVAD(
                        speechDetected: vadResult.speechDetected,
                        at: now
                    )
                    self.latestSnapshot = snapshot
                    self.streamContinuation?.yield(snapshot)
                }
            } catch {
                // VAD stream termination does not fail recognition.
            }
        }

        analyzerStartTask = Task { @MainActor [weak self] in
            do {
                if let resolvedLocale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) {
                    _ = try? await AssetInventory.reserve(locale: resolvedLocale)
                }
                let compatibleFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: modules,
                    considering: naturalFormat
                )
                try await analyzer.prepareToAnalyze(in: compatibleFormat ?? naturalFormat)
                try await analyzer.start(inputSequence: inputStream)
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                receive(.failure(error.localizedDescription))
            }
        }
    }

    private func stopInput() {
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
        }
        engineObserver = nil
        engine?.stop()
        if hasTap {
            engine?.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
    }

    func finish() {
        stopInput()
        feed?.finish()
        feed = nil
        let currentAnalyzer = analyzer
        let token = generation
        Task { @MainActor [weak self] in
            try? await currentAnalyzer?.finalizeAndFinishThroughEndOfInput()
            guard let self, self.generation == token else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let snapshot = self.accumulator.finalizePendingVolatile(at: now)
            self.latestSnapshot = snapshot
            self.streamContinuation?.yield(snapshot)
        }
    }

    func cancel() {
        generation += 1
        stopInput()
        feed?.finish()
        feed = nil
        transcriberTask?.cancel()
        transcriberTask = nil
        detectorTask?.cancel()
        detectorTask = nil
        analyzerStartTask?.cancel()
        analyzerStartTask = nil
        let currentAnalyzer = analyzer
        analyzer = nil
        if let currentAnalyzer {
            Task { await currentAnalyzer.cancelAndFinishNow() }
        }
        accumulator.reset()
        streamContinuation?.finish()
        streamContinuation = nil
        engine = nil
    }
}
