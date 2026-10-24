import AppKit
import SwiftUI

/// Floating circular widget (*Aqua Glass Sphere* with Sig orbiting and pulsing)
/// displayed while `BackgroundResearchAgent` runs a task in the background.
struct CircularResearchWidgetView: View {
    @ObservedObject var agent: BackgroundResearchAgent
    var size: CGFloat = 52
    var onTap: (() -> Void)? = nil
    @State private var orbitAngle: Double = 0
    @State private var pulseScale: CGFloat = 0.94

    private let aquaCyan = Color(red: 0.28, green: 0.84, blue: 1.0)
    private let aquaIndigo = Color(red: 0.56, green: 0.44, blue: 1.0)

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    // Pulsing outer aura
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [aquaCyan.opacity(0.65), aquaIndigo.opacity(0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: size * pulseScale, height: size * pulseScale)

                    // Aqua Glass Sphere core
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    aquaCyan.opacity(0.24),
                                    aquaIndigo.opacity(0.32)
                                ],
                                center: UnitPoint(x: 0.32, y: 0.28),
                                startRadius: 2,
                                endRadius: size * 0.55
                            )
                            .clipShape(Circle())
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.75), aquaCyan.opacity(0.45), .white.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        }
                        .shadow(color: aquaCyan.opacity(0.45), radius: 10, y: 3)
                        .frame(width: size - 6, height: size - 6)

                    // Sig mascot working inside the Aqua Glass Sphere
                    CompanionCharacter(size: size * 0.58, avatar: .sig, animates: false)

                    // Subtle orbital satellite
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .shadow(color: aquaCyan, radius: 4)
                        .offset(y: -(size * 0.44))
                        .rotationEffect(.degrees(orbitAngle))
                }
                .frame(width: size, height: size)

                if let topic = agent.activeTopic {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("PESQUISANDO EM BACKGROUND")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .foregroundStyle(aquaCyan)
                            Text("\(Int(agent.progress * 100))%")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Text(topic)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(agent.statusStep)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(aquaCyan.opacity(0.35), lineWidth: 0.9)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                orbitAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
            }
        }
        .accessibilityLabel("Pesquisa em segundo plano ativa")
    }
}

/// Interactive Artifact Card generated when the background research agent finishes (`agent-done`).
struct ResearchArtifactCardView: View {
    let artifact: ResearchArtifact
    var onOpenInAdaRoom: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    private let accentCyan = Color(red: 0.30, green: 0.82, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentCyan)
                Text(artifact.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(artifact.completionCue.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentCyan.opacity(0.18), in: Capsule())
                    .foregroundStyle(accentCyan)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(artifact.summary)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(artifact.bulletPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(accentCyan)
                            .frame(width: 4.5, height: 4.5)
                            .padding(.top, 5)
                        Text(point)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                if let onOpenInAdaRoom {
                    Button(action: onOpenInAdaRoom) {
                        Label("Abrir na Ada Room", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accentCyan.opacity(0.22), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(artifact.markdownRepresentation, forType: .string)
                } label: {
                    Label("Copiar Resumo", systemImage: "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accentCyan.opacity(0.55), Color.white.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}
