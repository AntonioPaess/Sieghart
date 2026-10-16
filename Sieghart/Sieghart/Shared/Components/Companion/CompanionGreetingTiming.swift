// Greeting timing and rigPose adapted from Louis-CFM/coucou (MIT).
// Source commit 5cb2a27af352cf7319569920aac899efd42b54bc.
// Native runtime choreography; see THIRD_PARTY_NOTICES.md for the MIT notice.
import SwiftUI
struct CompanionGreetingLayout {
    var width: CGFloat = 360
    var height: CGFloat = 32
    var botCenterY: CGFloat = 20
}

// MARK: - Timing constants

enum CompanionGreetingTiming {
    static let pop0:     Double = 1.30
    static let pop1:     Double = 1.45
    static let content0: Double = 2.40
    static let tuck0:    Double = 2.45
    static let tuck1:    Double = 2.70
    static let badge:    Double = 2.72
    static let down0:    Double = 2.85
    static let down1:    Double = 3.45
    static let blink2:   Double = 3.70
    static let tint0:    Double = 3.85
    static let tint1:    Double = 4.15
    static let end:      Double = 4.60
    static let autoLeave:Double = 4.90
    static let COLLAPSE: Double = 0.34
}

// MARK: - Geometry constants (640×150 reference space)

let rigGC0     = CGPoint(x: 320, y: 90)
let rigGHB:    CGFloat = 58
let rigGASP:   CGFloat = 1.34
let rigGEAR_X: CGFloat = 40
let rigGEAR_HB:CGFloat = 17
let rigGCARD   = CGRect(x: 10, y: 36, width: 620, height: 104)
let rigGCARD_R:CGFloat = 20

// MARK: - Easing

enum CompanionEase {
    static func out(_ t: Double)    -> Double { 1 - pow(1 - t, 3) }
    static func easeIn(_ t: Double) -> Double { t * t * t }
    static func inOut(_ t: Double)  -> Double {
        t < 0.5 ? 4*t*t*t : 1 - pow(-2*t+2, 3)/2
    }
    static func back(_ t: Double)   -> Double {
        let c1=1.70158, c3=c1+1
        return 1 + c3*pow(t-1,3) + c1*pow(t-1,2)
    }
}

func rigGClamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
func rigGLerp(_ a: Double, _ b: Double, _ t: Double)  -> Double { a + (b - a) * t }
func rigGSeg(_ t: Double, _ a: Double, _ b: Double)   -> Double { rigGClamp((t-a)/(b-a), 0, 1) }
func rigGLerpF(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b-a)*t }

// MARK: - CompanionRigPose

enum CompanionGreetingEyes { case dot, happy, content }

struct CompanionGreetingPose {
    var hb, x, y, sx, sy, tilt: Double
    var eye: CompanionGreetingEyes; var open, eyeRoll: Double
    var lookX, lookY: Double
    var handL, handR, wave: Double
    var badge, tint, halo, haloBlue, minis, fx: Double
    var header, card: Double
    var iw, ih: Double
}

// MARK: - Particle data (seeded LCG, seed=7)

struct CompanionWarpStreak { let xNorm, speed, len, thick, alpha, t0: Double }
struct CompanionRingDot    { let a, j, s, al: Double }

let rigGreetParticles: (warps: [CompanionWarpStreak], ring: [CompanionRingDot]) = {
    var seed: UInt32 = 7
    func rnd() -> Double {
        seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
        return Double(seed) / Double(0x7fff_ffff)
    }
    // ~70 white warp streaks for the fall-in (0 → 0.55 s)
    let warps = (0..<70).map { _ in
        CompanionWarpStreak(xNorm: rnd(),
                    speed: 400 + rnd() * 300,
                    len:   6   + rnd() * 16,
                    thick: 1   + rnd() * 0.5,
                    alpha: 0.25 + rnd() * 0.55,
                    t0:   rnd() * 0.35)
    }
    // Single burst ring at 0.45 s, ~90 dots, white
    let ring = (0..<90).map { _ in
        CompanionRingDot(a: rnd() * .pi * 2, j: (rnd()-0.5)*0.22,
                 s: 0.7+rnd()*0.9,   al: 0.45+rnd()*0.55)
    }
    return (warps, ring)
}()

// MARK: - CompanionRigPose computation

func rigGreetPose(_ t: Double, compact: CompanionGreetingLayout) -> CompanionGreetingPose {
    // Island size (reference for clip / warp spread)
    let gx = rigGSeg(t, 0, 0.5)
    let g  = sin(.pi*gx/2) + 0.04*sin(.pi*gx)*gx
    let iw = rigGLerp(Double(compact.width - 160), 640, g)
    let ih = rigGLerp(Double(compact.height), 150, g)

    let GH = Double(rigGHB)   // 58
    let cx = Double(rigGC0.x) // 320
    let cy = Double(rigGC0.y) // 90

    // Body height: invisible before 0.20, grows 0.15→1.0 with back ease
    let hb: Double = t < 0.20 ? 0 : rigGLerp(GH * 0.15, GH, CompanionEase.back(rigGSeg(t, 0.20, 0.60)))

    // Landmark y positions (absolute, rigGC0-relative in multiples of GH)
    let restY   = cy
    let landY   = cy + 0.12 * GH   // landing: y=+0.12
    let peakY   = cy - 0.15 * GH   // bounce peak: y=−0.15
    let dipY    = cy + 0.36 * GH   // plunge low: y=+0.36
    let springY = cy - 0.10 * GH   // spring high: y=−0.10
    let sinkY   = cy + 0.30 * GH   // sink for tuck: y=+0.30

    // Landmark x positions
    let restX   = cx
    let drift1  = cx - 0.16 * GH
    let drift2  = cx - 0.45 * GH
    let drift3  = cx - 0.57 * GH
    let drift4  = cx - 0.85 * GH

    // --- X (lateral travel) ---
    var x: Double
    if t < 0.85 {
        x = restX
    } else if t < 1.20 {
        x = rigGLerp(restX,  drift1, CompanionEase.inOut(rigGSeg(t, 0.85, 1.20)))
    } else if t < 1.30 {
        x = rigGLerp(drift1, drift2, CompanionEase.easeIn(rigGSeg(t, 1.20, 1.30)))
    } else if t < 1.45 {
        x = rigGLerp(drift2, drift3, CompanionEase.inOut(rigGSeg(t, 1.30, 1.45)))
    } else if t < 2.40 {
        x = rigGLerp(drift3, drift4, CompanionEase.inOut(rigGSeg(t, 1.45, 2.40)))
    } else if t < 2.85 {
        x = drift4
    } else {
        x = rigGLerp(drift4, restX,  CompanionEase.inOut(rigGSeg(t, 2.85, 3.45)))
    }

    // --- Y (vertical travel, base without bob) ---
    var y: Double
    if t < 0.20 {
        y = Double(compact.botCenterY)
    } else if t < 0.60 {
        y = rigGLerp(Double(compact.botCenterY), landY, CompanionEase.easeIn(rigGSeg(t, 0.20, 0.60)))
    } else if t < 0.73 {
        y = rigGLerp(landY,   peakY,   CompanionEase.out(rigGSeg(t, 0.60, 0.73)))
    } else if t < 0.90 {
        y = rigGLerp(peakY,   restY,   CompanionEase.inOut(rigGSeg(t, 0.73, 0.90)))
    } else if t < 1.20 {
        y = restY
    } else if t < 1.30 {
        y = rigGLerp(restY,   dipY,    CompanionEase.easeIn(rigGSeg(t, 1.20, 1.30)))
    } else if t < 1.45 {
        y = rigGLerp(dipY,    springY, CompanionEase.out(rigGSeg(t, 1.30, 1.45)))
    } else if t < 1.60 {
        y = rigGLerp(springY, restY,   CompanionEase.inOut(rigGSeg(t, 1.45, 1.60)))
    } else if t < 2.40 {
        y = restY
    } else if t < 2.70 {
        y = rigGLerp(restY,   sinkY,   CompanionEase.inOut(rigGSeg(t, 2.40, 2.70)))
    } else if t < 2.85 {
        y = sinkY
    } else {
        y = rigGLerp(sinkY,   restY,   CompanionEase.inOut(rigGSeg(t, 2.85, 3.45)))
    }

    // Body bob: in phase with hand wave, active pop1 → tuck0, ramp-in 0.08 s
    if t >= CompanionGreetingTiming.pop1 && t < CompanionGreetingTiming.tuck0 {
        let w = t - CompanionGreetingTiming.pop1
        let rampIn = rigGClamp(w / 0.08, 0, 1)
        y += sin(w * 2 * .pi * 5.0) * 0.02 * GH * rampIn
    }

    // --- Scale ---
    var sx = 1.0, sy = 1.0

    // Landing squash (peak at 0.60, pulse 0.52→0.68)
    let landSqK = (t >= 0.52 && t < 0.68) ? sin(.pi * rigGSeg(t, 0.52, 0.68)) : 0
    // Bounce stretch (peak at 0.73, resolves 0.62→0.84)
    let bounceK  = (t >= 0.62 && t < 0.84) ? sin(.pi * rigGSeg(t, 0.62, 0.84)) : 0
    sx = 1.0 + 0.14 * landSqK - 0.10 * bounceK
    sy = 1.0 - 0.14 * landSqK + 0.18 * bounceK

    // Plunge squash (peaks at 1.30, pulse 1.18→1.42)
    let plungeK = (t >= 1.18 && t < 1.42) ? sin(.pi * rigGSeg(t, 1.18, 1.42)) : 0
    // Spring stretch (peak at 1.38, resolves 1.30→1.46)
    let springK = (t >= 1.30 && t < 1.46) ? sin(.pi * rigGSeg(t, 1.30, 1.46)) : 0
    sx += 0.12 * plungeK - 0.18 * springK
    sy -= 0.12 * plungeK - 0.25 * springK

    // Sink squash (peak at 2.70)
    let sinkK: Double
    if t >= 2.38 && t < 2.70 {
        sinkK = CompanionEase.inOut(rigGSeg(t, 2.38, 2.70))
    } else if t >= 2.70 && t < 2.85 {
        sinkK = 1 - CompanionEase.inOut(rigGSeg(t, 2.70, 2.85))
    } else {
        sinkK = 0
    }
    sx += 0.18 * sinkK
    sy -= 0.14 * sinkK

    // Micro squash at 3.70 (with blink)
    let microK = (t >= 3.70 && t < 3.82) ? sin(.pi * rigGSeg(t, 3.70, 3.82)) : 0
    sx += 0.08 * microK
    sy -= 0.07 * microK

    // --- Eyes ---
    var eye: CompanionGreetingEyes = .dot
    if t >= 0.55  && t < 0.80      { eye = .happy   }
    if t >= CompanionGreetingTiming.content0 && t < CompanionGreetingTiming.tuck1 { eye = .content }

    let blink: (Double) -> Double = { tb in
        let k = rigGSeg(t, tb, tb + 0.12)
        return (k > 0 && k < 1) ? 1 - sin(.pi * k) * 0.94 : 1
    }
    let openVal = min(blink(1.95), min(blink(3.05), blink(CompanionGreetingTiming.blink2)))

    // --- Look ---
    var lookX = 0.0, lookY = 0.0
    if t >= CompanionGreetingTiming.pop1 && t < CompanionGreetingTiming.content0 {         // wave: up-right
        lookX = 0.55; lookY = -0.45
    } else if t >= CompanionGreetingTiming.content0 && t < CompanionGreetingTiming.down0 { // tuck: down-left
        lookX = -0.3; lookY = 0.6
    } else if t >= CompanionGreetingTiming.down0 && t < CompanionGreetingTiming.down1 {    // slide: down-right (returning)
        lookX = 0.3;  lookY = 0.6
    } else if t >= CompanionGreetingTiming.down1 {
        let k = CompanionEase.inOut(rigGSeg(t, CompanionGreetingTiming.down1, CompanionGreetingTiming.down1 + 0.35))
        lookX = rigGLerp(0.3, 0, k); lookY = rigGLerp(0.6, 0, k)
    }

    // --- Hands ---
    let handL = t < CompanionGreetingTiming.tuck0
        ? CompanionEase.back(rigGSeg(t, CompanionGreetingTiming.pop0, CompanionGreetingTiming.pop0 + 0.14))
        : 1 - CompanionEase.easeIn(rigGSeg(t, CompanionGreetingTiming.tuck0, CompanionGreetingTiming.tuck1 - 0.03))
    let handR = t < CompanionGreetingTiming.tuck0
        ? CompanionEase.back(rigGSeg(t, CompanionGreetingTiming.pop0 + 0.04, CompanionGreetingTiming.pop0 + 0.18))
        : 1 - CompanionEase.easeIn(rigGSeg(t, CompanionGreetingTiming.tuck0 + 0.03, CompanionGreetingTiming.tuck1))
    let wave = (t >= CompanionGreetingTiming.pop1 && t < CompanionGreetingTiming.tuck0) ? t - CompanionGreetingTiming.pop1 : -1.0

    return CompanionGreetingPose(
        hb: hb, x: x, y: y, sx: sx, sy: sy, tilt: 0,
        eye: eye, open: openVal, eyeRoll: 0,
        lookX: lookX, lookY: lookY,
        handL: handL, handR: handR, wave: wave,
        badge:    CompanionEase.back(rigGSeg(t, CompanionGreetingTiming.badge, CompanionGreetingTiming.badge + 0.28)),
        tint:     0.6 * CompanionEase.inOut(rigGSeg(t, CompanionGreetingTiming.tint0, CompanionGreetingTiming.tint1)),
        halo:     CompanionEase.out(rigGSeg(t, 0.3, 0.7)),
        haloBlue: rigGSeg(t, CompanionGreetingTiming.tint0, CompanionGreetingTiming.tint1),
        minis: 0, fx: 1,
        header: rigGSeg(t, 0.35, 0.6), card: rigGSeg(t, 0.18, 0.45),
        iw: iw, ih: ih
    )
}

