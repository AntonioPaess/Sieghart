import AppKit
import SwiftUI

/// Full-screen transparent non-activating panel that floats across all Spaces and ignores mouse events by default.
final class SpatialCanvasPanel: NSPanel {
    init(screenFrame: NSRect) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .fullScreenDisallowsTiling,
            .stationary,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Full-screen spatial overlay rendering animated vector paths (`Trim` 0.0 -> 1.0 with laser glow)
/// and semantic screen inspection highlights (`AnnotationHighlightView` & `BlueCursorView`).
struct SpatialCanvasOverlay: View {
    @ObservedObject var viewModel: SpatialOverlayViewModel

    private let laserCyan = Color(red: 0.32, green: 0.86, blue: 1.0)
    private let laserPurple = Color(red: 0.78, green: 0.52, blue: 1.0)
    private let laserGold = Color(red: 1.0, green: 0.78, blue: 0.28)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear

                if let document = viewModel.generatedCanvas {
                    GeneratedCanvasView(document: document, progress: viewModel.strokeProgress, opacity: viewModel.overlayOpacity)
                }
                if let drawing = viewModel.activeDrawing {
                    let targetRect = resolvedCanvasRect(for: drawing, in: proxy.size)
                    let vectorPath = VectorDrawingInterpreter.path(for: drawing.shape, in: targetRect)
                    let trimmedPath = vectorPath.trimmedPath(from: 0.0, to: viewModel.strokeProgress)

                    ZStack {
                        // Outer ambient laser glow
                        trimmedPath
                            .stroke(
                                LinearGradient(
                                    colors: [laserCyan.opacity(0.65), laserPurple.opacity(0.65), laserGold.opacity(0.65)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: 8)

                        // Core crisp vector stroke
                        trimmedPath
                            .stroke(
                                LinearGradient(
                                    colors: [.white, laserCyan, laserPurple],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: laserCyan.opacity(0.85), radius: 10)

                        // Laser pen tip while actively tracing
                        if viewModel.strokeProgress > 0.01 && viewModel.strokeProgress < 0.99,
                           let tip = trimmedPath.currentPoint {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 12, height: 12)
                                .shadow(color: laserCyan, radius: 12)
                                .position(tip)
                        }

                        ForEach(drawing.labels(in: targetRect), id: \.text) { label in
                            SpatialVectorLabelView(label: label)
                                .id(drawing.id)
                        }

                        // Caption badge below the drawing
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(laserCyan)
                            Text("Sig · \(drawing.shape.displayTitle)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(laserCyan.opacity(0.5), lineWidth: 0.8)
                        }
                        .position(x: targetRect.midX, y: min(proxy.size.height - 40, targetRect.maxY + 26))
                    }
                    .opacity(viewModel.overlayOpacity)
                }

                if let highlight = viewModel.activeHighlight {
                    AnnotationHighlightView(
                        highlight: highlight,
                        opacity: viewModel.overlayOpacity
                    )
                    BlueCursorView(
                        position: highlight.cursorPoint,
                        opacity: viewModel.overlayOpacity
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private func resolvedCanvasRect(for drawing: SpatialVectorDrawing, in size: CGSize) -> CGRect {
        let width = drawing.canvasRect.width > 0 ? drawing.canvasRect.width : 320
        let height = drawing.canvasRect.height > 0 ? drawing.canvasRect.height : 320
        if drawing.canvasRect.origin != .zero {
            return drawing.canvasRect
        }
        return CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.45,
            width: width,
            height: height
        )
    }
}

private struct SpatialVectorLabelView: View {
    let label: SpatialVectorLabel
    @State private var reveal: CGFloat = 0

    var body: some View {
        Text(label.text)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
            .mask { Rectangle().scaleEffect(x: reveal, anchor: .leading) }
            .shadow(color: .cyan.opacity(0.9), radius: 6)
            .rotationEffect(.degrees(label.rotationDegrees))
            .position(label.position)
            .task {
                do {
                    try await Task.sleep(for: .seconds(SpatialOverlayViewModel.strokeDuration))
                    withAnimation(.easeOut(duration: 0.35)) { reveal = 1 }
                } catch { /* Removing the drawing cancels its pending label. */ }
            }
    }
}
