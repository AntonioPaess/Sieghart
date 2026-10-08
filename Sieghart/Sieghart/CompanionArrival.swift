import SwiftUI

// Time-based choreography keeps dropped frames from changing the trajectory.
// Opening starts at zero velocity; the damped arrival settles rather than
// snapping between PNGs or replaying an idle loop as a welcome gesture.
struct CompanionEntranceMotion: Equatable {
    var opacity: Double = 1
    var offset: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation: Double = 0
    var eyeOpen: CGFloat = 1
    static func sample(elapsed: Double, reducedMotion: Bool = false) -> Self {
        guard !reducedMotion else { return Self() }
        let t = max(0, elapsed)
        func smooth(_ value: Double) -> Double { let x = min(1, max(0, value)); return x * x * (3 - 2 * x) }
        let spring = exp(-6 * t) * (cos(11 * t) + 6.0 / 11 * sin(11 * t))
        let welcome = sin(.pi * smooth((t - 0.5) / 0.8))
        return Self(opacity: smooth(t / 0.24), offset: CGFloat(-0.58 * spring - 0.065 * welcome),
                    scaleX: CGFloat(1 - 0.14 * spring + 0.02 * welcome), scaleY: CGFloat(1 - 0.14 * spring - 0.018 * welcome),
                    rotation: -7 * spring + 3 * welcome, eyeOpen: CGFloat(0.08 + 0.92 * smooth((t - 0.12) / 0.32)))
    }
}

struct CompanionArrivalView: View {
    var avatar: CompanionAvatar
    var animates = true
    var previewElapsed: Double? = nil
    var size: CGFloat = 154
    @State private var started = Date()
    @State private var gaze = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.islandReduceMotion) private var reducedMotion
    private var moves: Bool { animates && !systemReducedMotion && !reducedMotion }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !moves || previewElapsed != nil)) { context in
            let elapsed = previewElapsed ?? context.date.timeIntervalSince(started)
            let pose = CompanionEntranceMotion.sample(elapsed: elapsed, reducedMotion: !moves)
            GeometryReader { geometry in
              ZStack {
                Ellipse().fill(avatar.tint.opacity(0.1)).frame(width: size * 0.62, height: 13).blur(radius: 10).offset(y: size * 0.42)
                CompanionCharacter(size: size, avatar: avatar, animates: moves, gaze: gaze, previewTime: previewElapsed == nil ? nil : 20 + elapsed, entrance: pose)
              }.frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): gaze = CompanionGaze.sample(point: point, in: geometry.size)
                    case .ended: gaze = .zero
                    }
                }
            }.frame(height: 220)
        }
        .onAppear { started = Date() }
        .onChange(of: avatar) { _, _ in started = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(avatar.name), your companion")
    }
}

// Center in the actual layout: a fixed x-coordinate biased wide views to the right.
enum CompanionGaze {
    static func sample(point: CGPoint, in size: CGSize) -> CGSize {
        CGSize(width: min(4, max(-4, (point.x - size.width / 2) / max(1, size.width / 8))),
               height: min(3, max(-3, (point.y - size.height / 2) / max(1, size.height / 6))))
    }
}
