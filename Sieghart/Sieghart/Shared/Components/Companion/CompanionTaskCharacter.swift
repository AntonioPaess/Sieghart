import SwiftUI

struct CompanionTaskCharacter: View {
    @ObservedObject var events: CompanionEventCenter
    var avatar: CompanionAvatar
    var size: CGFloat
    var animates = true
    var working = false
    var supporting = false
    @Environment(\.islandPreview) private var preview
    @Environment(\.islandReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.companionMotionEnabled) private var preferenceMotion
    @State private var reaction: CompanionAnimation?
    @State private var greeting = true
    @State private var acknowledges = false
    @State private var replay = 0
    var body: some View {
        let moves = animates && preferenceMotion && !reduceMotion && !systemReduceMotion && !preview
        CompanionCharacter(size: size, avatar: avatar, animates: moves,
                           animation: supporting ? .idle : working ? .working : reaction ?? (greeting ? .hello : .idle), replay: replay)
            // Supporting characters acknowledge the actual event using cached
            // portraits. Only its owner gets a live SceneKit reaction.
            .rotationEffect(.degrees(supporting && acknowledges && moves ? (replay % 2 == 0 ? -3 : 3) : 0))
            .offset(y: supporting && acknowledges && moves ? -2 : 0)
            .animation(moves ? .easeInOut(duration: 0.3) : nil, value: acknowledges)
            .task(id: events.latest?.id) {
                guard !preview else { return }
                if let event = events.latest, !event.quiet, Date().timeIntervalSince(event.createdAt) < 5 {
                    greeting = false
                    replay += 1
                    reaction = event.owner == avatar ? event.animation : .understood
                    acknowledges = true
                }
                do { try await Task.sleep(for: .seconds(reaction?.duration ?? CompanionAnimation.hello.duration)) }
                catch { return }
                reaction = nil; acknowledges = false; greeting = false
            }
    }
}
