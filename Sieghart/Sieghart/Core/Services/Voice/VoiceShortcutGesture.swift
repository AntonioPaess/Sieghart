import Foundation

/// Carbon and the event monitor may deliver the same gesture out of order.
/// A release is remembered even if its delayed press has not arrived yet.
struct VoiceShortcutGesture {
    private(set) var isHeld = false
    private(set) var pressTime = -Double.infinity
    private var releaseTime = -Double.infinity
    mutating func press(at time: TimeInterval) -> Bool {
        guard time.isFinite, !isHeld, time > releaseTime else { return false }
        isHeld = true; pressTime = time
        return true
    }
    mutating func release(at time: TimeInterval) -> Bool {
        guard time.isFinite else { return false }
        releaseTime = max(releaseTime, time)
        guard isHeld, time >= pressTime else { return false }
        isHeld = false
        return true
    }
    mutating func cancel() {
        releaseTime = max(releaseTime, pressTime)
        isHeld = false
    }
}

/// Hardware-state polling is only a fallback after the held state was actually
/// observed. Missing permission or an unreadable initial state cannot end a turn.
struct VoiceShortcutReleaseWatch {
    private var confirmed = false
    private var releasedSamples = 0
    mutating func observe(_ held: Bool?) -> Bool {
        guard let held else { releasedSamples = 0; return false }
        if held { confirmed = true; releasedSamples = 0; return false }
        guard confirmed else { return false }
        releasedSamples += 1
        return releasedSamples >= 3
    }
}
