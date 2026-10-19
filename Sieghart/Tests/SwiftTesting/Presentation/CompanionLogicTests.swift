import Foundation
import SwiftUI
import Testing

extension LogicTests {
    @Suite(.tags(.logic, .interactions)) struct CompanionMotionTests {
        @Test("G04.06 · Every avatar keeps finite mood poses and deterministic Reduce Motion", arguments: CompanionAvatar.allCases)
        func moodSamples(_ avatar: CompanionAvatar) {
            for mood: CompanionMood in [.idle, .happy, .annoyed, .asleep, .waking, .startled, .understood, .celebrating] {
                let still = CompanionMotion.sample(time: 0, size: 24, avatar: avatar, mood: mood, listening: true, strolling: true, animates: false)
                let later = CompanionMotion.sample(time: 100, size: 24, avatar: avatar, mood: mood, listening: true, strolling: true, animates: false)
                #expect(still == later)
                let moving = CompanionMotion.sample(time: 0.14, size: 24, avatar: avatar, mood: mood, listening: false, strolling: false, animates: true)
                #expect(moving.eyeOpen.isFinite && moving.scaleX > 0 && moving.scaleY > 0)
            }
            let asleepA = CompanionMotion.sample(time: 0.2, size: 96, avatar: avatar, mood: .asleep, listening: false, strolling: false, animates: true)
            let asleepB = CompanionMotion.sample(time: 1.5, size: 96, avatar: avatar, mood: .asleep, listening: false, strolling: false, animates: true)
            #expect(asleepA != asleepB && asleepA.eyeOpen == 0.07 && asleepB.eyeOpen == 0.07)
        }
        @Test("G04.06 · Blink closes and reopens") func blink() {
            let closed = CompanionMotion.sample(time: 0.14, size: 42, avatar: .sig, mood: .idle, listening: false, strolling: false, animates: true)
            let open = CompanionMotion.sample(time: 0.28, size: 42, avatar: .sig, mood: .idle, listening: false, strolling: false, animates: true)
            #expect(closed.eyeOpen < 0.05 && open.eyeOpen == 1)
        }

        @Test("G04.06 · Distinct voice phases, continuity, cancellation and settled success", arguments: CompanionAvatar.allCases, [CGFloat(24), 60, 96])
        func voiceGestures(_ avatar: CompanionAvatar, _ size: CGFloat) {
            let listen = CompanionVoiceMotion.sample(phase: .listening, elapsed: 0.4, size: size, avatar: avatar, animates: true)
            let think = CompanionVoiceMotion.sample(phase: .thinking, elapsed: 0.4, size: size, avatar: avatar, animates: true)
            let win = CompanionVoiceMotion.sample(phase: .success, elapsed: 0.55, size: size, avatar: avatar, animates: true)
            #expect(listen.loading == 0 && think.loading == 1 && win.loading == 0)
            #expect(listen != think && think != win)
            #expect(abs(win.rotation) < 6 && abs(win.offset.height) < size * 0.05)
            if avatar == .ada { #expect(listen.rotation == 0 && think.rotation == 0 && win.rotation == 0) }
            if avatar == .rita || avatar == .sig { #expect(win.wink > 0.8) }
            for phase in [CompanionVoicePhase.preparing, .listening, .thinking, .working, .success, .failure] {
                #expect(CompanionVoiceMotion.sample(phase: phase, elapsed: 0.2, size: size, avatar: avatar, animates: false)
                        == CompanionVoiceMotion.sample(phase: phase, elapsed: 3.8, size: size, avatar: avatar, animates: false))
            }
            let settled = CompanionVoiceMotion.sample(phase: .success, elapsed: 1.2, size: size, avatar: avatar, animates: true)
            #expect(settled == CompanionVoiceMotion.sample(phase: .success, elapsed: 5, size: size, avatar: avatar, animates: true))
            var animator = CompanionVoiceAnimator()
            animator.transition(to: .listening, at: 0, size: size, avatar: avatar, animates: true)
            let before = animator.sample(at: 0.6, size: size, avatar: avatar, animates: true)
            animator.transition(to: .thinking, at: 0.6, size: size, avatar: avatar, animates: true)
            #expect(before == animator.sample(at: 0.6, size: size, avatar: avatar, animates: true))
            animator.transition(to: .success, at: 1, size: size, avatar: avatar, animates: true)
            let gesture = animator.sample(at: 1.45, size: size, avatar: avatar, animates: true)
            animator.transition(to: .inactive, at: 1.45, size: size, avatar: avatar, animates: true)
            #expect(gesture == animator.sample(at: 1.45, size: size, avatar: avatar, animates: true))
            #expect(animator.sample(at: 2, size: size, avatar: avatar, animates: true) == CompanionVoicePose())
            animator.transition(to: .working, at: 2, size: size, avatar: avatar, animates: true)
            let working = animator.sample(at: 3, size: size, avatar: avatar, animates: true)
            animator.transition(to: .working, at: 3, size: size, avatar: avatar, animates: true)
            #expect(working == animator.sample(at: 3, size: size, avatar: avatar, animates: true))
        }
    }

    @Suite(.tags(.logic, .interactions)) struct CompanionActivityTests {
        @Test("G04.07 · Explicit voice wins over background work/loading") func priority() {
            #expect(CompanionActivity.phase(voice: .inactive, isLoading: true) == .thinking)
            #expect(CompanionActivity.phase(voice: .inactive, hasActiveTask: true) == .working)
            #expect(CompanionActivity.phase(voice: .inactive) == .inactive)
            for phase in [CompanionVoicePhase.preparing, .listening, .thinking, .working, .success, .failure] {
                #expect(CompanionActivity.phase(voice: phase, isLoading: true, hasActiveTask: true) == phase)
            }
        }
        @Test("G04.07 · Ada loading contour remains stepped without curves") func steppedLoading() {
            let badge = CompanionLoadingShape(avatar: .ada).path(in: CGRect(x: 0, y: 0, width: 28, height: 28))
            var segments = 0
            badge.forEach { element in
                switch element {
                case .move, .line, .closeSubpath: segments += 1
                default: Issue.record("Arcade loading contour must not contain curves")
                }
            }
            #expect(segments > 12)
        }
    }

    @Suite(.tags(.logic, .companions)) struct CompanionIdentityTests {
        @Test("G05.01 · Fixed six identities, five specialists and bilingual introduction") func identities() {
            #expect(CompanionAvatar.allCases == [.sig, .rita, .ada, .gantt, .elinor, .toni])
            #expect(CompanionAvatar.specialists.count == 5 && !CompanionAvatar.specialists.contains(.sig))
            #expect(CompanionIntroductionCopy.forMember(.rita).headline == "Breathe with me.")
            #expect(CompanionIntroductionCopy.forMember(.rita, language: .portuguese).headline == "Respira comigo.")
            let opening = CompanionIntroductionCopy.forIntroduction(at: CompanionTeamFormation.dockTime)
            let closing = CompanionIntroductionCopy.forIntroduction(at: CompanionTeamFormation.returnTime)
            #expect(opening.headline != closing.headline && !opening.role.contains("orchestrator"))
            #expect(closing.role == "Your orchestrator")
            #expect(CompanionIntroductionCopy.forIntroduction(at: CompanionTeamFormation.specialistStart).headline == CompanionIntroductionCopy.forMember(.rita).headline)
            #expect(CompanionIntroductionCopy.forIntroduction(at: CompanionTeamFormation.returnTime, language: .portuguese).role == "Seu orquestrador")
        }
    }
    @Suite(.tags(.logic, .companions)) struct CompanionAnimationTests {
        @Test("G05.02 · Animation catalog and voice/mood resolution") func catalog() {
            #expect(CompanionAnimation.allCases.count == 49)
            #expect(CompanionAnimation.resolve(voice: .inactive, mood: .idle) == .idle)
            #expect(!CompanionAnimation.idle.showsLoading && !CompanionAnimation.listening.showsLoading)
            #expect(CompanionAnimation.fileOpen.holdsFinalPose && !CompanionAnimation.fileOpen.continuous)
            #expect(CompanionAnimation.fileProcessing.continuous && CompanionAnimation.fileReceive.duration == 1.3)
            #expect(CompanionAnimation.resolve(voice: .thinking, mood: .asleep) == .voiceThinking)
            #expect(CompanionAnimation.resolve(voice: .success, mood: .idle) == .understood)
            #expect(CompanionAnimation.resolve(voice: .inactive, mood: .asleep) == .sleeping)
            #expect(CompanionAnimation.resolve(voice: .inactive, mood: .celebrating) == .completed)
        }
    }
    @Suite(.tags(.logic, .companions)) struct FileIntakePoseTests {
        @Test("G05.03 · Intake trajectory bounds at 240 samples per second", arguments: Array(0...312))
        func intakeBounds(_ frame: Int) {
            let motion = rigFileIntake(time: Double(frame) / 240)
            #expect(motion.scaleX > 0.9 && motion.scaleX < 1.1 && motion.scaleY >= 0.89 && motion.scaleY <= 1.05)
            #expect(motion.fileOpacity >= 0 && motion.fileOpacity <= 1 && motion.suction >= 0 && motion.suction <= 1)
        }
    }
    @Suite(.tags(.logic, .companions)) struct TeamFormationTests {
        @Test("G05.06 · Presentation order and approved opening geometry") func opening() {
            let intro = CompanionTeamFormation.specialistStart
            #expect(CompanionTeamFormation.activeMember(at: CompanionTeamFormation.dockTime + 0.8) == nil)
            #expect(CompanionTeamFormation.activeMember(at: intro + 0.3) == .rita)
            #expect(CompanionTeamFormation.activeMember(at: intro + 3.3) == .ada)
            #expect(CompanionTeamFormation.activeMember(at: CompanionTeamFormation.returnTime + 0.3) == nil)
            let layout = CompanionHomeLayout()
            #expect(layout.hero == CGPoint(x: 62, y: 48) && layout.dock(0).y == 131)
            let opening = CompanionOpeningLayout(home: layout)
            for index in 0..<5 {
                let p = CompanionTeamFormation.position(index: index, time: 7.3)
                #expect(abs(hypot(p.x - Double(opening.center.x), p.y - Double(opening.center.y)) - 112 * opening.scale) < 0.001)
            }
        }
        @Test("G05.07 · Distinct greetings, unique queue slots, resting positions and selective waiting") func queue() {
            let greetings = CompanionAvatar.allCases.map { rigIdentityHelloPose($0, 0.9) }
            #expect(Set(greetings.map { "\($0.y):\($0.sy):\($0.pitch):\($0.wink):\($0.roll)" }).count == 6)
            for turn in 0...6 {
                let slots = CompanionAvatar.allCases.compactMap { CompanionTeamFormation.dockSlot(member: $0, turn: turn) }
                #expect(Set(slots) == Set(0..<5))
                #expect(slots.count == 5)
            }
            let layout = CompanionHomeLayout()
            for index in 0..<5 {
                let p = CompanionTeamFormation.position(index: index, time: 30)
                #expect(abs(p.x - Double(layout.dock(index).x)) < 0.001 && p.y == Double(layout.dock(index).y) && p.dock == 1)
            }
            let waiting = CompanionAvatar.allCases.map { rigWaitingPose($0, 0.35) }
            #expect(Set(waiting.map { "\($0.y):\($0.roll):\($0.pitch):\($0.wink):\($0.open)" }).count == 6)
            #expect(CompanionTeamFormation.waitingTime(member: .ada, time: CompanionTeamFormation.specialistStart + 1.3) != nil)
            #expect(CompanionTeamFormation.waitingTime(member: .gantt, time: CompanionTeamFormation.specialistStart + 1.3) == nil)
        }
    }
}
