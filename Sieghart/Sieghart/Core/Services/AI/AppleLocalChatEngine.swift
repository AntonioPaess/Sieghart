import Foundation
import FoundationModels

@MainActor final class AppleLocalChatEngine: LocalChatGenerating {
    private var configuration: AppleChatConfiguration
    private let github: AdaGitHubContext?
    init(configuration: AppleChatConfiguration = .init(), github: AdaGitHubContext? = nil) {
        self.configuration = configuration; self.github = github
    }
    func configure(_ configuration: AppleChatConfiguration) { self.configuration = configuration }
    var modelName: String {
        guard #available(macOS 27.0, *), configuration.mode == .onDevice,
              SystemLanguageModel.default.isAvailable else { return configuration.label }
        return SystemLanguageModel.default.variant.displayName + " · On this Mac"
    }
    var readiness: LocalChatReadiness {
        if let reason = AppleChatEligibility.currentPrerequisite(for: configuration.mode) { return reason }
        guard #available(macOS 27.0, *) else { return .unavailable("The new Apple Foundation Models require macOS 27 or later.") }
        if configuration.mode == .privateCloudThinking {
            let model = PrivateCloudComputeLanguageModel()
            guard model.capabilities.contains(.reasoning), model.capabilities.contains(.toolCalling) else {
                return .unavailable("Apple's cloud model does not currently provide the reasoning and tools required by Ada.")
            }
            switch model.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible): return .unavailable("Apple Private Cloud Compute requires an Apple Intelligence eligible device and region.")
            case .unavailable(.systemNotReady): return .unavailable("Apple Private Cloud Compute is not ready. Check Apple Intelligence and your network connection.")
            @unknown default: return .unavailable("Apple Private Cloud Compute is currently unavailable.")
            }
        }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            guard model.variant == .core3 || model.variant == .coreAdvanced3 else {
                return .unavailable("The new AFM 3 model is not installed or ready. Update Apple Intelligence; Ada will not use the previous model.")
            }
            guard model.capabilities.contains(.toolCalling) else { return .unavailable("The installed Apple model does not provide Ada's required tool support.") }
            return .available
        case .unavailable(.deviceNotEligible): return .unavailable("This Mac or region does not support the on-device Apple Intelligence model.")
        case .unavailable(.appleIntelligenceNotEnabled): return .unavailable("Enable Apple Intelligence in System Settings to use the new on-device model.")
        case .unavailable(.modelNotReady): return .unavailable("Apple Intelligence is preparing its new on-device model. Try again when it is ready.")
        @unknown default: return .unavailable("The on-device Apple model is unavailable. Check Apple Intelligence in System Settings.")
        }
    }
    func generate(history: [LocalChatMessage], persona: LocalChatPersona,
                  onSnapshot: @escaping @MainActor (String) -> Void) async throws -> String {
        let status = readiness
        guard status.available else { throw LocalChatError.unavailable(status.reason ?? "Apple chat is unavailable.") }
        guard #available(macOS 27.0, *) else { throw LocalChatError.unavailable("The new Apple Foundation Models require macOS 27 or later.") }
        let context = try LocalChatContext.prepare(history)
        let selection = configuration
        let connected = await github?.status().connected ?? false
        let instructions = AdaAgentInstructions.make(persona: persona, githubConnected: connected)
        let tools: [any Tool] = github.map { [AdaGitHubTool(context: $0)] } ?? []
        let definitions = tools.map { Transcript.ToolDefinition(tool: $0) }
        func segment(_ text: String) -> [Transcript.Segment] { [.text(.init(content: text))] }
        func entries(_ past: [LocalChatMessage]) -> [Transcript.Entry] {
            [.instructions(.init(segments: segment(instructions), toolDefinitions: definitions))] + past.map {
                $0.role == .user ? .prompt(.init(segments: segment($0.text))) : .response(.init(assetIDs: [], segments: segment($0.text)))
            }
        }
        var past = context.past
        let outputBudget = selection.mode == .privateCloudThinking ? 4_096 : 1_024
        let session: LanguageModelSession
        // Sessions exist only during an explicit turn; no idle prewarming or old-model fallback.
        if selection.mode == .privateCloudThinking {
            let model = PrivateCloudComputeLanguageModel()
            let capacity = try await model.contextSize
            // PCC has its own tokenizer. A conservative byte budget includes tool
            // schemas/results and thinking output instead of pretending local token
            // counts measure cloud tokens. The framework enforces the actual limit.
            while instructions.utf8.count + past.reduce(0, { $0 + $1.text.utf8.count }) + context.prompt.text.utf8.count + outputBudget + 6_144 > capacity {
                guard past.count >= 2 else { throw LocalChatError.contextLimit }; past.removeFirst(2)
            }
            session = LanguageModelSession(model: model, tools: tools, transcript: Transcript(entries: entries(past)))
        } else {
            let model = SystemLanguageModel.default
            // Count actual instructions, tool definitions and complete turns using
            // this model's tokenizer, then reserve room for the answer and tool data.
            while try await model.tokenCount(for: entries(past) + [.prompt(.init(segments: segment(context.prompt.text)))]) + outputBudget + 1_280 > model.contextSize {
                guard past.count >= 2 else { throw LocalChatError.contextLimit }; past.removeFirst(2)
            }
            session = LanguageModelSession(model: model, tools: tools, transcript: Transcript(entries: entries(past)))
        }
        let thinking: ContextOptions.ReasoningLevel? = selection.mode == .onDevice ? nil : {
            switch selection.reasoning { case .light: .light; case .moderate: .moderate; case .deep: .deep }
        }()
        do {
            var final = ""
            let stream = session.streamResponse(to: context.prompt.text,
                options: GenerationOptions(temperature: 0.25, maximumResponseTokens: outputBudget),
                contextOptions: ContextOptions(reasoningLevel: thinking))
            for try await response in stream {
                try Task.checkCancellation()
                guard response.content.utf8.count <= 16_384 else { throw LocalChatError.generationFailed("The Apple model's reply was too long. Try a more focused question.") }
                final = response.content
                onSnapshot(final)
            }
            try Task.checkCancellation()
            guard !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalChatError.emptyResponse }
            return final
        } catch let error as LanguageModelError {
            switch error {
            case .contextSizeExceeded: throw LocalChatError.contextLimit
            case .rateLimited: throw LocalChatError.generationFailed("Apple's usage limit was reached. Try again later or choose the on-device mode in Ada settings.")
            case .unsupportedCapability: throw LocalChatError.generationFailed("The selected Apple model does not support this capability. Check the model and thinking mode in Ada settings.")
            default: throw LocalChatError.generationFailed(error.localizedDescription)
            }
        }
    }
}

@MainActor final class UnavailableLocalChatEngine: LocalChatGenerating {
    var readiness: LocalChatReadiness { .unavailable("Apple model is not enabled in this preview.") }
    func generate(history: [LocalChatMessage], persona: LocalChatPersona,
                  onSnapshot: @escaping @MainActor (String) -> Void) async throws -> String {
        throw LocalChatError.unavailable(readiness.reason!)
    }
}
