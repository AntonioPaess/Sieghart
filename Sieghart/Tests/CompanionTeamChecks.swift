import AppKit
import SceneKit
import SwiftUI

@main struct CompanionTeamChecks {
    @MainActor static func main() throws {
        precondition(CompanionAvatar.allCases == [.sig, .rita, .ada, .gantt, .elinor, .toni])
        precondition(CompanionAvatar.specialists.count == 5 && !CompanionAvatar.specialists.contains(.sig))
        let suite = "Sieghart.TeamChecks.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["All tools", "Avatars", "Clipboard", "Preferences", "Speak", "Audio"], forKey: "island.rails")
        let prefs = CompanionPreferences(defaults: defaults)
        precondition(prefs.avatar == .sig && prefs.railActions[1] == .companion && prefs.railActions[2] == .clipboard,
                     "Legacy Team rails migrate to Companion; Sig remains the principal")
        precondition(prefs.introductionLanguage == .english, "Introduction defaults to English regardless of system/speech language")
        precondition(CompanionIntroductionCopy.forMember(.rita).headline == "Breathe with me.")
        prefs.introductionLanguage = .portuguese
        precondition(CompanionPreferences(defaults: defaults).introductionLanguage == .portuguese)
        precondition(CompanionIntroductionCopy.forMember(.rita, language: .portuguese).headline == "Respira comigo.")
        let opening = CompanionIntroductionCopy.forIntroduction(at: CompanionTeamFormation.dockTime)
        let closing = CompanionIntroductionCopy.forIntroduction(at: CompanionTeamFormation.returnTime)
        precondition(opening.headline != closing.headline && !opening.role.contains("orchestrator"), "Sig first introduces the team, then himself on returning")
        precondition(closing.role == "Your orchestrator")
        precondition(CompanionIntroductionCopy.forIntroduction(at: CompanionTeamFormation.specialistStart).headline == CompanionIntroductionCopy.forMember(.rita).headline)
        precondition(CompanionIntroductionCopy.forIntroduction(at: CompanionTeamFormation.returnTime, language: .portuguese).role == "Seu orquestrador")
        precondition(CompanionAnimation.allCases.count == 49)
        precondition(CompanionAnimation.resolve(voice: .inactive, mood: .idle) == .idle)
        precondition(!CompanionAnimation.idle.showsLoading && !CompanionAnimation.listening.showsLoading)
        precondition(CompanionAnimation.fileOpen.holdsFinalPose && !CompanionAnimation.fileOpen.continuous)
        precondition(CompanionAnimation.fileProcessing.continuous && CompanionAnimation.fileReceive.duration == 1.3)
        precondition(CompanionAnimation.resolve(voice: .thinking, mood: .asleep) == .voiceThinking)
        precondition(CompanionAnimation.resolve(voice: .success, mood: .idle) == .understood)
        precondition(CompanionAnimation.resolve(voice: .inactive, mood: .asleep) == .sleeping)
        precondition(CompanionAnimation.resolve(voice: .inactive, mood: .celebrating) == .completed)
        for member in CompanionAvatar.allCases {
            let coordinator = CompanionScene.Coordinator(member)
            for frame in 0...312 {
                let motion = rigFileIntake(time: Double(frame) / 240)
                precondition(motion.scaleX > 0.9 && motion.scaleX < 1.1 && motion.scaleY >= 0.89 && motion.scaleY <= 1.05)
                precondition(motion.fileOpacity >= 0 && motion.fileOpacity <= 1 && motion.suction >= 0 && motion.suction <= 1)
            }
            coordinator.actor.update(id: CompanionAnimation.fileReceive.rawValue, t: 0.16, duration: 1.3, global: 0.16)
            precondition(coordinator.actor.slot.position.y <= coordinator.actor.bounds.maxY - 5, "The aperture stays inside the body silhouette")
            let earlyDepth = coordinator.actor.file.position.z
            coordinator.actor.update(id: CompanionAnimation.fileReceive.rawValue, t: 0.37, duration: 1.3, global: 0.37)
            precondition(coordinator.actor.file.position.z < earlyDepth, "The file moves behind the top aperture instead of through the front face")
            coordinator.actor.update(id: CompanionAnimation.fileReceive.rawValue, t: 1.3, duration: 1.3, global: 1.3)
            precondition(coordinator.actor.file.opacity == 0 && coordinator.actor.slot.opacity == 0 && coordinator.actor.model.marker?.opacity == 0)
            coordinator.update(CompanionScene(avatar: member, animation: .fileOpen, time: 0, animates: true, gaze: nil, replay: 0))
            coordinator.update(CompanionScene(avatar: member, animation: .fileOpen, time: 2, animates: true, gaze: nil, replay: 0))
            precondition(coordinator.actor.slot.opacity > 0.9 && coordinator.actor.file.opacity == 0, "Hover holds the receiver open without a fake second file or an endless render loop")
            precondition(coordinator.actor.halo.renderingOrder < 0
                         && coordinator.actor.halo.geometry?.firstMaterial?.readsFromDepthBuffer == false,
                         "Every active character draws its light below the opaque silhouette")
            func render(_ animation: CompanionAnimation, _ time: Double, animates: Bool = true) {
                coordinator.update(CompanionScene(avatar: member, animation: animation, time: time, animates: animates, gaze: nil, replay: 0))
            }
            render(.idle, 100); render(.idle, 101)
            precondition(coordinator.actor.model.marker?.opacity == 0)
            render(.thinking, 101); render(.thinking, 101.6)
            let before = coordinator.actor.lastPose
            precondition(before.loading > 0.9)
            let badge = coordinator.actor.model.marker!
            let progress = coordinator.actor.model.loadingProgress!
            let badgeMeshes = badge.childNodes.map { ObjectIdentifier($0.geometry!) }
            let phase = progress.value(forKey: "phase") as! Float
            render(.thinking, 101.8)
            precondition(badge.eulerAngles.z == 0 && badge.scale.x == 1, "Loading keeps the badge still and sweeps its inner contour")
            precondition((progress.value(forKey: "phase") as! Float) != phase)
            precondition(badge.childNodes.map { ObjectIdentifier($0.geometry!) } == badgeMeshes, "Loading never rebuilds its stroke mesh")
            render(.thinking, 101.6)
            render(.idle, 101.6)
            precondition(coordinator.actor.lastPose.loading == before.loading)
            precondition(coordinator.actor.lastPose.gaze == before.gaze)
            render(.idle, 101.9)
            precondition(coordinator.actor.model.marker?.opacity == 0, "Cancellation removes the activity marker")
            render(.sleeping, 102); render(.sleeping, 102.4)
            let sleeping = coordinator.actor.lastPose
            render(.sleeping, 103.7)
            precondition(sleeping.sy != coordinator.actor.lastPose.sy)
            precondition(coordinator.actor.lastPose.open < 0.06, "Sleep keeps eyes closed while breathing")
            render(.sleeping, 104, animates: false)
            let still = coordinator.actor.lastPose
            render(.sleeping, 108, animates: false)
            precondition(still.sy == coordinator.actor.lastPose.sy && still.open == coordinator.actor.lastPose.open)
            render(.cursor, 109)
            coordinator.update(CompanionScene(avatar: member, animation: .cursor, time: 110, animates: true, gaze: CGSize(width: -4, height: 0), replay: 0))
            precondition(coordinator.actor.lastPose.gaze.width == -4)
            precondition(coordinator.actor.cursor.opacity == 0, "Hover cannot draw a second mouse pointer")
            coordinator.update(CompanionScene(avatar: member, animation: .cursor, time: 110.1, animates: true, gaze: CGSize(width: 4, height: 0), replay: 0))
            precondition(coordinator.actor.lastPose.gaze.width == 4)
            precondition(coordinator.actor.cursor.opacity == 0)
            // Continuous eye openness/gaze/wink must reuse persistent meshes.
            let rig = coordinator.actor.model
            rig.updateEyes(open: 1, joy: 0, gaze: .zero, wink: 0, anger: 0)
            let meshes = rig.eyeCache.count
            for i in 0..<360 {
                rig.updateEyes(open: Double(i % 61) / 60, joy: 0,
                               gaze: CGSize(width: sin(Double(i)), height: 0),
                               wink: Double(i % 41) / 40, anger: 0)
            }
            precondition(rig.eyeCache.count == meshes, "Blinks cannot allocate new eye geometry")
            for animation in CompanionAnimation.allCases {
                for t in [0.0, 0.7, 1.8, animation.duration] {
                    let actor = coordinator.actor
                    actor.update(id: animation.rawValue, t: t, duration: animation.duration, global: t, continuous: animation.continuous)
                    let p = actor.lastPose
                    precondition([p.x,p.y,p.sx,p.sy,p.sz,p.roll,p.yaw,p.open,p.opacity,p.loading].allSatisfy { $0.isFinite })
                    precondition(p.opacity <= 0 ? (p.sx >= 0 && p.sy >= 0) : (p.sx > 0 && p.sy > 0))
                    if member == .ada || member == .gantt { precondition(abs(p.sx - p.sy) < 0.00001) }
                }
            }
        }
        let intro = CompanionTeamFormation.specialistStart
        precondition(CompanionTeamFormation.activeMember(at: CompanionTeamFormation.dockTime + 0.8) == nil, "Sig is introduced after the team has settled")
        precondition(CompanionTeamFormation.activeMember(at: intro + 0.3) == .rita)
        precondition(CompanionTeamFormation.activeMember(at: intro + 3.3) == .ada)
        precondition(CompanionTeamFormation.activeMember(at: CompanionTeamFormation.returnTime + 0.3) == nil)
        let layout = CompanionHomeLayout()
        precondition(layout.hero == CGPoint(x: 62, y: 48) && layout.dock(0).y == 131)
        let team = CompanionTeamScene.Coordinator()
        team.update(time: 2.2, animates: true)
        precondition(team.agents.allSatisfy { $0.root.isHidden }, "Sig falls and greets before the others emerge")
        let reference = rigGreetPose(2.2, compact: CompanionGreetingLayout())
        precondition(abs(Double(team.greeting.model.root.parent!.scale.x) - Double(layout.size.width / 640)) < 0.00001)
        precondition(abs(Double(team.greeting.halo.scale.x) - reference.hb * rigGASP * 4.2) < 0.001,
                     "The opening preserves the full reference halo instead of clipping it to the hero slot")
        team.update(time: 4.4, animates: true)
        precondition(team.agents.allSatisfy { $0.root.isHidden }, "The full fall/wave/light transition finishes before the team emerges")
        team.update(time: 6.0, animates: true)
        precondition(team.agents.allSatisfy { !$0.root.isHidden }, "All five emerge before the introductions")
        for index in 0..<5 {
            let p = CompanionTeamFormation.position(index: index, time: 7.3)
            let opening = CompanionOpeningLayout(home: layout)
            precondition(abs(hypot(p.x - Double(opening.center.x), p.y - Double(opening.center.y)) - 112 * opening.scale) < 0.001, "The approved reveal retains its 112-unit circle and uniform scale")
        }
        team.update(time: 8.2, animates: true)
        team.update(time: 9.1, animates: true)
        team.update(time: 9.7, animates: true)
        precondition(team.greeting.halo.renderingOrder < team.greeting.model.head.renderingOrder
                     && team.greeting.halo.geometry?.firstMaterial?.readsFromDepthBuffer == false,
                     "The light composites below the silhouette without a depth-cut border")
        let blue = (team.greeting.halo.geometry!.firstMaterial!.multiply.contents as! NSColor).usingColorSpace(.sRGB)!
        precondition(blue.blueComponent > blue.redComponent, "The greeting carries the concept's warm-to-blue light transition")
        team.update(time: CompanionTeamFormation.dockTime + 2, animates: true)
        for (index, agent) in team.agents.enumerated() {
            let target = layout.scene(layout.dock(index))
            precondition(abs(agent.root.position.x-target.x) < 0.001 && abs(agent.root.position.y-target.y) < 0.001)
        }
        let settledUpdates = team.agentPoseUpdates
        team.update(time: CompanionTeamFormation.dockTime + 2.3, animates: true)
        precondition(team.agentPoseUpdates == settledUpdates, "Settled miniatures do not dirty SceneKit geometry or transforms every frame")
        let greetings = CompanionAvatar.allCases.map { rigIdentityHelloPose($0, 0.9) }
        precondition(Set(greetings.map { "\($0.y):\($0.sy):\($0.pitch):\($0.wink):\($0.roll)" }).count == 6, "Each identity has a distinct greeting")
        for (index, member) in CompanionAvatar.specialists.enumerated() {
            let time = intro + 0.7 + Double(index) * 3
            team.update(time: time, animates: true)
            precondition(CompanionTeamFormation.activeMember(at: time) == member)
            let hero = layout.scene(layout.hero)
            precondition(team.agents.filter { abs($0.root.position.x-hero.x) < 0.001 && abs($0.root.position.y-hero.y) < 0.001 }.count == 1)
            precondition(team.agents.filter { !$0.root.isHidden }.count == 5)
            let sigRoot = team.greeting.model.root.parent!
            precondition(!sigRoot.isHidden && sigRoot.opacity == 1, "Sig remains visible and joins the back of the queue")
            for (memberIndex, character) in CompanionAvatar.allCases.enumerated() {
                let root = memberIndex == 0 ? sigRoot : team.agents[memberIndex - 1].root
                let slot = CompanionTeamFormation.dockSlot(member: character, turn: index + 1)
                let expected = layout.scene(slot.map(layout.dock) ?? layout.hero)
                precondition(abs(root.position.x - expected.x) < 0.001 && abs(root.position.y - expected.y) < 0.001, "Every queue member advances one slot")
            }
        }
        for t in [0.0, 1.8, 5.4, 6.8, 10.3, 14, 20, 26, 30] { team.update(time: t, animates: true) }
        for (index, member) in team.agents.enumerated() {
            let p = CompanionTeamFormation.position(index: index, time: 30)
            precondition(abs(p.x - Double(layout.dock(index).x)) < 0.001 && p.y == Double(layout.dock(index).y) && p.dock == 1)
            let target = layout.scene(layout.dock(index))
            precondition(abs(member.root.position.x - target.x) < 0.001 && abs(member.root.position.y - target.y) < 0.001)
            precondition(member.root.opacity == 1 && member.activity.isHidden)
        }
        team.update(time: 0, animates: false)
        precondition(team.agents.allSatisfy { $0.root.opacity == 1 && !$0.root.isHidden }, "Reduce Motion presents the complete team immediately")
        for turn in 0...6 {
            let slots = CompanionAvatar.allCases.compactMap { CompanionTeamFormation.dockSlot(member: $0, turn: turn) }
            precondition(Set(slots) == Set(0..<5), "A complete queue has one hero and five unique dock slots")
        }
        let waiting = CompanionAvatar.allCases.map { rigWaitingPose($0, 0.35) }
        precondition(Set(waiting.map { "\($0.y):\($0.roll):\($0.pitch):\($0.wink):\($0.open)" }).count == 6)
        precondition(CompanionTeamFormation.waitingTime(member: .ada, time: intro + 1.3) != nil)
        precondition(CompanionTeamFormation.waitingTime(member: .gantt, time: intro + 1.3) == nil, "Waiting reactions do not animate the entire dock at once")
        let circle = rigStroke(Path(ellipseIn: CGRect(x: 20, y: 20, width: 40, height: 40)), color: .white)
        precondition(circle.childNodes.isEmpty && circle.geometry != nil, "Static accessory segments use one mesh")
        let portrait = CompanionPortraitView(frame: CGRect(x: 0, y: 0, width: 38, height: 38))
        let artwork = NSImage(size: CGSize(width: 512, height: 512))
        for pixels in [512, 1024] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
            bitmap.size = artwork.size; artwork.addRepresentation(bitmap)
        }
        portrait.configure(image: artwork, animates: true)
        portrait.layout()
        let imageLayer = portrait.layer!.sublayers!.first!
        precondition(CompanionArtwork.fullResolutionPixels(in: artwork)!.width == 1024, "The source retains its full Retina resolution")
        let display = imageLayer.contents as! CGImage
        precondition(display.width == 76 && display.height == 76, "A 38-point portrait is prefiltered once at its exact Retina backing size")
        portrait.layout()
        precondition((imageLayer.contents as! CGImage) === display, "Unchanged layout reuses the raster without repeated downsampling")
        precondition(imageLayer.contentsScale == 2 && imageLayer.minificationFilter == .linear)
        precondition(portrait.layer?.sublayers?.first?.animation(forKey: "breath") == nil, "Detached portraits do not animate")
        let view = CompanionRenderView(frame: .zero)
        view.animationEnabled = true
        precondition(!view.isPlaying && !view.rendersContinuously, "Detached scenes do not consume display ticks")
        precondition(!view.acceptsFirstResponder && view.hitTest(.zero) == nil && view.acceptsFirstMouse(for: nil))
        print("PASS: six fixed identities, migration, 294 character/motion pairs, interruption continuity, fixed loading badge/mesh, live sleep/gaze, team-first greeting, six distinct hellos, spotlight return, docking and reduced motion")
    }
}
