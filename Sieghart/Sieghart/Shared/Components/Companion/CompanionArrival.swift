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
    var offsetX: CGFloat = 0
    var wave: CGFloat = 0
    var waveAngle: Double = 0
    var joy = false
    static func sample(elapsed: Double, reducedMotion: Bool = false) -> Self {
        guard !reducedMotion else { return Self() }
        let t = max(0, elapsed)
        func smooth(_ value: Double) -> Double { let x = min(1, max(0, value)); return x * x * (3 - 2 * x) }
        let fall = smooth((t - 0.12) / 0.42)
        let landing = t > 0.54 ? exp(-7 * (t - 0.54)) * sin(15 * (t - 0.54)) : 0
        let slide = smooth((t - 0.95) / 0.5) * (1 - smooth((t - 2.6) / 0.7))
        let wave = smooth((t - 1.4) / 0.2) * (1 - smooth((t - 2.45) / 0.25))
        return Self(opacity: smooth((t - 0.06) / 0.2), offset: CGFloat(-1.1 * (1 - fall) + 0.22 * landing),
                    scaleX: CGFloat(0.8 + 0.2 * fall + 0.14 * landing), scaleY: CGFloat(0.8 + 0.2 * fall - 0.17 * landing),
                    rotation: -5 * (1 - fall) - 7 * slide + 3 * landing, eyeOpen: CGFloat(0.08 + 0.92 * smooth((t - 0.42) / 0.3)),
                    offsetX: CGFloat(-0.32 * slide), wave: CGFloat(wave), waveAngle: sin((t - 1.4) * 14) * 23 * wave, joy: wave > 0.5)
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

struct WelcomeContentPhase: ViewModifier {
    var started: Date?
    var animates: Bool
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: started == nil || !animates)) { context in
            let time = started.map { context.date.timeIntervalSince($0) } ?? 10
            content.opacity(animates && started != nil ? Self.dock(time) : 1)
        }
    }
    static func dock(_ time: Double) -> Double {
        let t = min(1, max(0, (time - 3.15) / 0.9))
        return t * t * (3 - 2 * t)
    }
}

struct CompanionIslandGreeting: View {
    var avatar: CompanionAvatar
    var started: Date
    var previewElapsed: Double? = nil
    var onTouch: () -> Void = {}
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: previewElapsed != nil)) { context in
            let time = previewElapsed ?? context.date.timeIntervalSince(started)
            let dock = WelcomeContentPhase.dock(time)
            GeometryReader { geometry in
                CompanionInteraction(action: onTouch) {
                    CompanionCharacter(size: 96, avatar: avatar, animates: true, previewTime: previewElapsed.map { 20 + $0 }, entrance: CompanionEntranceMotion.sample(elapsed: time))
                }
                .opacity(1 - dock)
                .position(x: geometry.size.width / 2 - (geometry.size.width / 2 - 62) * dock, y: geometry.size.height / 2)
                .accessibilityLabel("Your companion is saying hello")
            }
        }
    }
}
