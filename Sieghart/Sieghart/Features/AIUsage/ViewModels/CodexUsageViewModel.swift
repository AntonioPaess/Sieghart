import Combine
import Darwin
import Foundation

@MainActor
final class CodexUsageViewModel: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "integrations.codexUsage")
            generation += 1
            if !enabled { bucket = nil; updatedAt = nil; errorMessage = nil }
        }
    }
    @Published private(set) var bucket: CodexQuotaBucket?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    private var generation = 0
    private let defaults: UserDefaults
    private let load: @Sendable () throws -> CodexUsageResponse

    init(defaults: UserDefaults = .standard, load: @escaping @Sendable () throws -> CodexUsageResponse = { try LocalCodexUsage.fetch() }) {
        self.defaults = defaults; self.load = load
        enabled = defaults.bool(forKey: "integrations.codexUsage")
    }

    func refresh(force: Bool = false) async {
        guard enabled, !isRefreshing else { return }
        let expired = [bucket?.primary, bucket?.secondary].compactMap { $0?.resetDate }.contains { $0 <= Date() }
        if !force, !expired, let updatedAt, Date().timeIntervalSince(updatedAt) < 300 { return }
        isRefreshing = true
        let requestGeneration = generation, load = self.load
        defer { isRefreshing = false }
        do {
            let response = try await Task.detached(priority: .utility) { try load() }.value
            guard enabled, generation == requestGeneration, !Task.isCancelled else { return }
            guard let result = response.codex else { throw CodexUsageError.invalidResponse }
            bucket = result; updatedAt = Date(); errorMessage = nil
        } catch {
            guard enabled, generation == requestGeneration, !Task.isCancelled else { return }
            errorMessage = (error as? CodexUsageError)?.errorDescription ?? CodexUsageError.unavailable.errorDescription
        }
    }

    func refreshWhileVisible() async {
        guard enabled else { return }
        while !Task.isCancelled && enabled {
            await refresh()
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
    }
}
