import SwiftUI

/// Coucou's explicit token connection pattern, backed by Sieg's own Keychain.
/// The parent presents this view and explicitly asks the model to restore once.
struct AdaGitHubConnectionView: View {
    @ObservedObject var model: AdaGitHubViewModel
    @Environment(\.islandPreview) private var preview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(CompanionStyle.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ada + GitHub").font(.system(size: 18, weight: .semibold))
                    Text("Your code, with a little context.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.busy { ProgressView().controlSize(.small) }
            }

            Text("Ada can read your repository overview, open pull requests, requested reviews and CI status when you ask about GitHub.")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 7) {
                Circle().fill(model.status.connected ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6).padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    if let login = model.status.login, model.status.connected {
                        Text("Connected as @\(login)").font(.system(size: 12, weight: .medium))
                    }
                    Text(model.status.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    if let snapshot = model.status.snapshot {
                        Text("Last updated \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if model.status.connected {
                HStack {
                    Button("Refresh GitHub") { Task { await model.refresh() } }
                        .disabled(model.busy)
                    Spacer()
                    Button("Disconnect", role: .destructive) { Task { await model.disconnect() } }
                        .disabled(model.busy)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal access token").font(.system(size: 11, weight: .medium))
                    if preview {
                        Text("Paste your GitHub token").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                            .padding(7).frame(maxWidth: .infinity, alignment: .leading).background(CompanionStyle.separator, in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        SecureField("Paste your GitHub token", text: $model.token)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .disabled(model.busy || model.isIsolated)
                            .onSubmit { Task { await model.connect() } }
                    }
                    Text("Allow read access to the repositories you want Ada to see. The token stays in Sieg’s Keychain and is never sent to the language model.")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if preview {
                            Text("Create a token on GitHub").font(.system(size: 11)).foregroundStyle(CompanionStyle.accent)
                        } else {
                            Link("Create a token on GitHub", destination: URL(string: "https://github.com/settings/tokens")!)
                                .font(.system(size: 11))
                        }
                        Spacer()
                        Button("Connect GitHub") { Task { await model.connect() } }
                            .disabled(!model.canConnect)
                    }
                }
            }

            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if model.isIsolated {
                Text("GitHub connections are disabled in this preview.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }

            Text("Read-only connection · Requires internet · Ada cannot merge PRs or change repositories.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 340, idealWidth: 420, maxWidth: 460)
        .onDisappear { model.clearToken() }
    }
}
