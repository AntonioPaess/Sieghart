import Combine
import Foundation

/// Connection controls share Ada's context service; construction never reads
/// credentials or contacts GitHub. Tests and previews default to no service.
@MainActor
final class AdaGitHubViewModel: ObservableObject {
    @Published private(set) var status = AdaGitHubStatus(
        connected: false, loading: false, login: nil,
        detail: "GitHub is not connected.", snapshot: nil)
    @Published var token = ""
    @Published private(set) var busy = false
    @Published private(set) var error: String?

    private let service: AdaGitHubContext?
    private var restored = false

    init(service: AdaGitHubContext? = nil) { self.service = service }

    static func production() -> AdaGitHubViewModel {
        AdaGitHubViewModel(service: AdaGitHubContext())
    }

    var canConnect: Bool { !busy && !token.isEmpty && service != nil }
    var isIsolated: Bool { service == nil }

    /// Call only when the user opens Ada or the GitHub connection controls.
    func restore() async {
        guard !restored, !busy, let service else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await service.restore()
            restored = true
        } catch { self.error = Self.description(for: error) }
        status = await service.status()
    }

    func connect() async {
        guard canConnect, let service else { return }
        busy = true
        error = nil
        let candidate = token
        defer { busy = false }
        do {
            try await service.connect(token: candidate)
            token = ""
            restored = true
        } catch { self.error = Self.description(for: error) }
        status = await service.status()
    }

    func disconnect() async {
        guard !busy, let service else { return }
        busy = true
        token = ""
        error = nil
        defer { busy = false }
        do {
            try await service.disconnect()
            restored = true
        } catch { self.error = Self.description(for: error) }
        status = await service.status()
    }

    func refresh() async {
        guard !busy, status.connected, let service else { return }
        busy = true
        error = nil
        defer { busy = false }
        do { try await service.refresh() }
        catch { self.error = Self.description(for: error) }
        status = await service.status()
    }

    func clearToken() { token = "" }

    private static func description(for error: Error) -> String {
        if error is CancellationError { return "GitHub request cancelled." }
        // Arbitrary transport descriptions can contain a credential or request.
        return (error as? AdaGitHubError)?.localizedDescription
            ?? "Could not connect to GitHub. Check your connection and try again."
    }
}
