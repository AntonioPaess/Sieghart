import AppKit
import ApplicationServices
import Combine
import Foundation

/// High-level system automation command classified by safety.
enum SpatialSystemCommand: Equatable, Sendable {
    case openApp(name: String)
    case openWebURL(url: URL, browserApp: String?)
    case pressAccessibilityElement(label: String)
    case destructiveAction(title: String, detail: String, commandKey: String)

    var isDestructive: Bool {
        if case .destructiveAction = self { return true }
        return false
    }
}

/// Visual confirmation model presented in the Dynamic Island / Notch before running any destructive command.
struct PendingSystemConfirmation: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String
    let commandKey: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        commandKey: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.commandKey = commandKey
        self.createdAt = createdAt
    }
}

/// Execution result returned by `SystemCommandExecutor`.
enum SystemCommandExecutionResult: Equatable, Sendable {
    case executed(summary: String)
    case awaitingConfirmation(PendingSystemConfirmation)
    case cancelled(summary: String)
}

/// Executes system commands (`NSWorkspace.shared.openApplication`, native web navigation,
/// `AXUIElementPerformAction(kAXPressAction)`), enforcing visual Notch confirmation for destructive operations.
@MainActor
final class SystemCommandExecutor: ObservableObject {
    @Published private(set) var pendingConfirmation: PendingSystemConfirmation?
    @Published private(set) var lastExecutionSummary: String = ""
    @Published private(set) var confirmedCommandKeys: [String] = []

    private let appLauncher: @MainActor (String) async throws -> String
    private let urlOpener: @MainActor (URL, String?) async throws -> String
    private let axPresser: @MainActor (String) -> Bool
    private let sensitiveExecutor: (@MainActor (String) -> Bool)?

    init(
        appLauncher: @escaping @MainActor (String) async throws -> String = LocalAppLauncher.open,
        urlOpener: @escaping @MainActor (URL, String?) async throws -> String = SystemCommandExecutor.defaultOpenURL,
        axPresser: @escaping @MainActor (String) -> Bool = SystemCommandExecutor.defaultPressAXElement,
        sensitiveExecutor: (@MainActor (String) -> Bool)? = nil
    ) {
        self.appLauncher = appLauncher
        self.urlOpener = urlOpener
        self.axPresser = axPresser
        self.sensitiveExecutor = sensitiveExecutor
    }

    /// Parses natural-language system navigation, AX click, or destructive commands that are distinct from `FocusVoiceParser`.
    nonisolated static func parse(_ transcript: String) -> SpatialSystemCommand? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))

        // 1. Destructive command detection -> requires Notch visual confirmation
        let destructivePatterns: [(keywords: [String], title: String, detail: String, key: String)] = [
            (["esvaziar lixeira", "limpar lixeira", "empty trash"], "Esvaziar Lixeira", "Esta ação remove permanentemente os itens da Lixeira. Confirmar no Notch?", "empty-trash"),
            (["apagar arquivos temporarios", "excluir rascunhos", "delete temp files", "apague os arquivos"], "Excluir Arquivos", "Operação destrutiva detectada. Confirme visualmente no Notch antes de prosseguir.", "delete-files"),
            (["encerrar todos os apps", "fechar tudo", "force quit all"], "Encerrar Aplicativos", "Fechar aplicativos abertos pode descartar alterações não salvas.", "close-all-apps")
        ]
        for entry in destructivePatterns {
            if entry.keywords.contains(where: { normalized.contains($0) }) {
                return .destructiveAction(title: entry.title, detail: entry.detail, commandKey: entry.key)
            }
        }

        // 2. Native Web Navigation (e.g., "ir no youtube", "abrir youtube no safari", "go to youtube.com")
        let knownSites: [(triggers: [String], url: String)] = [
            (["ir no youtube", "ir para o youtube", "abrir o youtube", "abra o youtube", "ir no yt", "go to youtube", "open youtube"], "https://www.youtube.com"),
            (["ir no github", "ir para o github", "abrir o github", "go to github"], "https://github.com"),
            (["ir no developer apple", "abrir apple developer", "go to developer.apple.com"], "https://developer.apple.com")
        ]
        for site in knownSites {
            if site.triggers.contains(where: { normalized.contains($0) }),
               let url = URL(string: site.url) {
                let browser = normalized.contains("safari") ? "Safari" : nil
                return .openWebURL(url: url, browserApp: browser)
            }
        }

        // 3. Accessibility UI Click ("clique no botão X", "pressione o botão X", "click button X")
        let axPrefixes = ["clique no botao ", "clicar no botao ", "pressione o botao ", "click button ", "press button "]
        for prefix in axPrefixes where normalized.hasPrefix(prefix) {
            let target = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !target.isEmpty {
                return .pressAccessibilityElement(label: target)
            }
        }

        return nil
    }

    func execute(_ command: SpatialSystemCommand) async throws -> SystemCommandExecutionResult {
        switch command {
        case .openApp(let name):
            let launched = try await appLauncher(name)
            let summary = "Aplicativo \(launched) aberto"
            lastExecutionSummary = summary
            return .executed(summary: summary)

        case .openWebURL(let url, let browserApp):
            let summary = try await urlOpener(url, browserApp)
            lastExecutionSummary = summary
            return .executed(summary: summary)

        case .pressAccessibilityElement(let label):
            let pressed = axPresser(label)
            guard pressed else {
                let summary = "Não consegui acionar o elemento “\(label)”. Confira o alvo e a permissão de acessibilidade."
                lastExecutionSummary = summary
                return .cancelled(summary: summary)
            }
            let summary = "Ação de acessibilidade executada em “\(label)”"
            lastExecutionSummary = summary
            return .executed(summary: summary)

        case .destructiveAction(let title, let detail, let commandKey):
            guard sensitiveExecutor != nil else {
                let summary = "A operação \(title) não está disponível neste build. Nenhuma alteração foi feita."
                lastExecutionSummary = summary
                return .cancelled(summary: summary)
            }
            let confirmation = PendingSystemConfirmation(
                title: title,
                detail: detail,
                commandKey: commandKey
            )
            pendingConfirmation = confirmation
            lastExecutionSummary = "Aguardando confirmação no Notch: \(title)"
            return .awaitingConfirmation(confirmation)
        }
    }

    /// Confirms and runs the pending destructive operation from the Notch confirmation banner.
    func confirmPendingAction() -> SystemCommandExecutionResult {
        guard let pending = pendingConfirmation else {
            return .cancelled(summary: "Nenhuma operação pendente")
        }
        pendingConfirmation = nil
        guard sensitiveExecutor?(pending.commandKey) == true else {
            let summary = "A operação não foi executada: \(pending.title)."
            lastExecutionSummary = summary
            return .cancelled(summary: summary)
        }
        confirmedCommandKeys.append(pending.commandKey)
        let summary = "Confirmado e executado: \(pending.title)"
        lastExecutionSummary = summary
        return .executed(summary: summary)
    }

    /// Cancels the pending destructive operation from the Notch confirmation banner.
    func cancelPendingAction() -> SystemCommandExecutionResult {
        guard let pending = pendingConfirmation else {
            return .cancelled(summary: "Nenhuma operação pendente")
        }
        pendingConfirmation = nil
        let summary = "Operação cancelada com segurança: \(pending.title)"
        lastExecutionSummary = summary
        return .cancelled(summary: summary)
    }

    static func defaultOpenURL(_ url: URL, browserApp: String?) async throws -> String {
        if let browserApp,
           browserApp.caseInsensitiveCompare("Safari") == .orderedSame,
           let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: config)
            return "Abrindo \(url.host ?? url.absoluteString) no Safari"
        }
        _ = NSWorkspace.shared.open(url)
        return "Abrindo \(url.host ?? url.absoluteString)"
    }

    static func defaultPressAXElement(_ targetLabel: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let systemWide = AXUIElementCreateSystemWide()
        let mouse = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.maxY ?? 900
        var elementRef: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(mouse.x),
            Float(screenHeight - mouse.y),
            &elementRef
        )
        guard status == .success, let element = elementRef else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}
