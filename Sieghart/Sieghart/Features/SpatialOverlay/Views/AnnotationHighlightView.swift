import SwiftUI

/// Visual highlight frame rendered over a target screen element or window during semantic screen inspection.
struct ScreenAnnotationHighlight: Identifiable, Equatable, Sendable {
    let id: UUID
    let frame: CGRect
    let cursorPoint: CGPoint
    let elementRole: String
    let elementTitle: String
    let recognizedText: String
    let summary: String

    init(
        id: UUID = UUID(),
        frame: CGRect,
        cursorPoint: CGPoint,
        elementRole: String,
        elementTitle: String,
        recognizedText: String,
        summary: String
    ) {
        self.id = id
        self.frame = frame
        self.cursorPoint = cursorPoint
        self.elementRole = elementRole
        self.elementTitle = elementTitle
        self.recognizedText = recognizedText
        self.summary = summary
    }
}

/// Translucent blue/yellow spatial frame highlighting the UI element or screen region being analyzed by Sig.
struct AnnotationHighlightView: View {
    let highlight: ScreenAnnotationHighlight
    var opacity: Double = 1.0
    @State private var pulse = false

    private let primaryBlue = Color(red: 0.22, green: 0.62, blue: 1.0)
    private let accentYellow = Color(red: 1.0, green: 0.84, blue: 0.26)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            primaryBlue.opacity(0.14),
                            accentYellow.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [primaryBlue, accentYellow, primaryBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: pulse ? 2.6 : 2.0
                        )
                }
                .shadow(color: primaryBlue.opacity(0.45), radius: pulse ? 16 : 10)
                .frame(width: max(80, highlight.frame.width), height: max(44, highlight.frame.height))
                .position(x: highlight.frame.midX, y: highlight.frame.midY)

            HStack(spacing: 6) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentYellow)
                Text(highlight.elementTitle.isEmpty ? highlight.elementRole : highlight.elementTitle)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !highlight.recognizedText.isEmpty {
                    Text("· “\(highlight.recognizedText.prefix(48))”")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(primaryBlue.opacity(0.65), lineWidth: 1)
            }
            .position(
                x: highlight.frame.midX,
                y: max(28, highlight.frame.minY - 18)
            )
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Spatial blue cursor indicator showing where Sig's visual attention is anchored on screen.
struct BlueCursorView: View {
    let position: CGPoint
    var opacity: Double = 1.0
    @State private var ripple = false

    private let cursorBlue = Color(red: 0.18, green: 0.58, blue: 1.0)

    var body: some View {
        ZStack {
            Circle()
                .stroke(cursorBlue.opacity(0.55), lineWidth: 1.8)
                .frame(width: ripple ? 44 : 20, height: ripple ? 44 : 20)
                .opacity(ripple ? 0.15 : 0.85)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, cursorBlue],
                        center: .center,
                        startRadius: 1,
                        endRadius: 9
                    )
                )
                .frame(width: 14, height: 14)
                .shadow(color: cursorBlue.opacity(0.8), radius: 8)
        }
        .position(position)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                ripple = true
            }
        }
    }
}
