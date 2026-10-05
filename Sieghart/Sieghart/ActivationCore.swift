import AppKit
import AVFoundation
import Carbon
import Speech

@MainActor
final class ActivationController: ObservableObject {
    static var activeHotkeyOwner: ActivationController?
    static let keys: [(label: String, code: UInt32)] = [
        ("Off", 0), ("S", 1), ("D", 2), ("F", 3), ("G", 5), ("H", 4),
        ("J", 38), ("K", 40), ("L", 37), ("P", 35), ("V", 9), ("Space", 49)
    ]

    @Published var selectedKey: String {
        didSet { UserDefaults.standard.set(selectedKey, forKey: "activation.hotkey") ; registerHotkey() }
    }
    @Published private(set) var shortcutStatus = ""
    @Published private(set) var voiceStatus = "Voice is off"
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isPreparing = false
    @Published private(set) var awaitingVoiceConfirmation = false
    private var voiceRequestGeneration = 0

    private let assistant: AssistantViewModel
    private let notch: NotchWidgetController
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let audioEngine = AVAudioEngine()
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var stopTask: Task<Void, Never>?

    init(assistant: AssistantViewModel, notch: NotchWidgetController) {
        self.assistant = assistant
        self.notch = notch
        selectedKey = UserDefaults.standard.string(forKey: "activation.hotkey") ?? "S"
        registerHotkey()
    }

    private func registerHotkey() {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        guard let key = Self.keys.first(where: { $0.label == selectedKey }), key.label != "Off" else {
            shortcutStatus = "Shortcut off"
            return
        }
        Self.activeHotkeyOwner = self
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in ActivationController.activeHotkeyOwner?.notch.toggle() }
            return noErr
        }, 1, &eventType, nil, &handler)
        guard installStatus == noErr else {
            shortcutStatus = "Could not install keyboard shortcut"
            return
        }
        let identifier = EventHotKeyID(signature: 0x53494748, id: 1)
        let status = RegisterEventHotKey(key.code, UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotkey)
        shortcutStatus = status == noErr ? "Control + Option + \(key.label)" : "Shortcut unavailable; choose another key"
    }

    func toggleListening() {
        if isListening { finishListening(); return }
        if isPreparing { cancelVoiceCommand(); return }
        voiceRequestGeneration += 1
        let generation = voiceRequestGeneration
        isPreparing = true
        awaitingVoiceConfirmation = false
        transcript = ""
        voiceStatus = "Checking microphone and speech access…"
        notch.showVoice()
        Task { await startListening(generation: generation) }
    }

    private func startListening(generation: Int) async {
        guard !isListening, generation == voiceRequestGeneration else { return }
        defer { if generation == voiceRequestGeneration { isPreparing = false } }
        let speechAccess = await SpeechAuthorizationBridge.request()
        guard generation == voiceRequestGeneration else { return }
        guard speechAccess == .authorized else {
            voiceStatus = "Speech recognition access is needed in System Settings"
            return
        }
        let microphoneAccess = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == voiceRequestGeneration else { return }
        guard microphoneAccess else {
            voiceStatus = "Microphone access is needed in System Settings"
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            voiceStatus = "Speech recognition is unavailable"
            return
        }
        speechTask?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        speechRequest = request
        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            speechRequest = nil
            voiceStatus = "No microphone input is available"
            return
        }
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            request.append(buffer)
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            speechRequest = nil
            voiceStatus = "Could not start microphone: \(error.localizedDescription)"
            return
        }
        transcript = ""
        isListening = true
        voiceStatus = "Listening — say a focus command"
        notch.showVoice()
        speechTask = speechRecognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorMessage = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isListening, generation == self.voiceRequestGeneration else { return }
                if let text {
                    self.transcript = text
                    if isFinal {
                        self.finishListening()
                    }
                } else if let errorMessage {
                    self.stopListening()
                    self.voiceStatus = "Speech recognition stopped: \(errorMessage)"
                }
            }
        }
        stopTask?.cancel()
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.isListening else { return }
            self.finishListening()
        }
    }

    func finishListening() {
        guard isListening else { return }
        stopListening()
        awaitingVoiceConfirmation = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        voiceStatus = awaitingVoiceConfirmation ? "Review your spoken command." : "No speech heard. Try again when you’re ready."
        notch.showVoice()
    }

    func cancelVoiceCommand() {
        voiceRequestGeneration += 1
        isPreparing = false
        stopListening()
        awaitingVoiceConfirmation = false
        voiceStatus = "Voice is off"
        notch.show()
    }

    func confirmVoiceCommand() {
        guard awaitingVoiceConfirmation else { return }
        awaitingVoiceConfirmation = false
        applyVoiceCommand(transcript)
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        stopTask?.cancel()
        stopTask = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        speechRequest?.endAudio()
        speechRequest = nil
        speechTask?.cancel()
        speechTask = nil
        voiceStatus = "Voice is off"
    }

    private func applyVoiceCommand(_ text: String) {
        let command = text.lowercased()
        if command.contains("pause") || command.contains("stop timer") {
            assistant.pausePomodoroFromGesture()
            voiceStatus = "Timer paused"
            notch.showCurrentTask()
        } else if command.contains("start") || command.contains("resume") || command.contains("focus") {
            assistant.startPomodoroFromGesture()
            voiceStatus = "Timer started"
            notch.showCurrentTask()
        } else if command.contains("show") || command.contains("open") {
            notch.show()
            voiceStatus = "Sieghart shown"
        } else if command.contains("hide") || command.contains("close") {
            notch.hide()
            voiceStatus = "Sieghart hidden"
        } else {
            voiceStatus = text.isEmpty ? "No speech heard" : "Command not recognized. Try “start focus” or “pause timer”."
        }
    }
}
