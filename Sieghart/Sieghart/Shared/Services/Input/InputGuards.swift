import AppKit
import ApplicationServices
import Carbon

struct ClickDebounceSample: Equatable, Sendable {
    var button: Int
    var phase: MouseButtonPhase
    var location: CGPoint
    var timestampNs: UInt64
}

struct ClickDebounceState: Equatable, Sendable {
    static let windowRange: ClosedRange<Int> = 15...100
    private var lastReleaseNs: [Int: UInt64] = [:]
    private var lastLocation: [Int: CGPoint] = [:]
    private(set) var suppressedButtons: Set<Int> = []

    mutating func reset() {
        lastReleaseNs = [:]; lastLocation = [:]; suppressedButtons = []
    }

    mutating func shouldSuppress(_ sample: ClickDebounceSample, enabled: Bool, windowMs: Int) -> Bool {
        let clampedMs = UInt64(min(max(windowMs, Self.windowRange.lowerBound), Self.windowRange.upperBound))
        let thresholdNs = clampedMs * 1_000_000
        switch sample.phase {
        case .up:
            if suppressedButtons.remove(sample.button) != nil { return true }
            lastReleaseNs[sample.button] = sample.timestampNs
            lastLocation[sample.button] = sample.location
            return false
        case .dragged:
            return suppressedButtons.contains(sample.button)
        case .down:
            guard enabled else { return false }
            if let prevNs = lastReleaseNs[sample.button],
               let prevPt = lastLocation[sample.button],
               sample.timestampNs >= prevNs,
               sample.timestampNs - prevNs <= thresholdNs,
               hypot(sample.location.x - prevPt.x, sample.location.y - prevPt.y) <= 2.0 {
                suppressedButtons.insert(sample.button)
                return true
            }
            lastLocation[sample.button] = sample.location
            return false
        }
    }
}

enum KeyEventPhase: Sendable, Equatable {
    case down, up, flagsChanged
}

struct KeyGuardSample: Equatable, Sendable {
    var keyCode: UInt16
    var phase: KeyEventPhase
    var isRepeat: Bool = false
    var flags: UInt64 = 0
    var characters: String = ""
    var timestampNs: UInt64 = 0
    var frontmostPID: Int32 = 0
    var frontmostAppName: String = "App"
}

struct KeyDebounceState: Equatable, Sendable {
    static let windowRange: ClosedRange<Int> = 15...80
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    private var lastEventNs: [UInt16: UInt64] = [:]
    private(set) var suppressedKeys: Set<UInt16> = []

    mutating func reset() {
        lastEventNs = [:]; suppressedKeys = []
    }

    mutating func shouldSuppress(_ sample: KeyGuardSample, enabled: Bool, windowMs: Int) -> Bool {
        guard !Self.modifierKeyCodes.contains(sample.keyCode) else { return false }
        let clampedMs = UInt64(min(max(windowMs, Self.windowRange.lowerBound), Self.windowRange.upperBound))
        let thresholdNs = clampedMs * 1_000_000
        switch sample.phase {
        case .flagsChanged:
            return false
        case .up:
            if suppressedKeys.remove(sample.keyCode) != nil { return true }
            lastEventNs[sample.keyCode] = sample.timestampNs
            return false
        case .down:
            guard enabled, !sample.isRepeat else { return false }
            if let prevNs = lastEventNs[sample.keyCode],
               sample.timestampNs >= prevNs,
               sample.timestampNs - prevNs <= thresholdNs {
                suppressedKeys.insert(sample.keyCode)
                return true
            }
            lastEventNs[sample.keyCode] = sample.timestampNs
            return false
        }
    }
}

enum SuperKeyTrigger: String, CaseIterable, Codable, Sendable {
    case f18, rightOption, capsLock
    var title: String {
        switch self {
        case .f18: "F18"
        case .rightOption: "Right Option"
        case .capsLock: "Caps Lock"
        }
    }
    var keyCode: UInt16 {
        switch self {
        case .f18: 79
        case .rightOption: 61
        case .capsLock: 57
        }
    }
    func conflicts(with chords: [ShortcutChord]) -> Bool {
        chords.contains { $0.keyCode == UInt32(keyCode) && $0.flags.isEmpty }
    }
}

struct SuperKeyState: Equatable, Sendable {
    static let hyperFlags: UInt64 = CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskShift.rawValue
    private(set) var isHeld = false

    mutating func reset() { isHeld = false }

    mutating func process(_ sample: KeyGuardSample, enabled: Bool, trigger: SuperKeyTrigger) -> (consume: Bool, flags: UInt64) {
        guard enabled else { isHeld = false; return (false, sample.flags) }
        if sample.keyCode == trigger.keyCode {
            switch sample.phase {
            case .down:
                isHeld = true; return (true, sample.flags)
            case .up:
                isHeld = false; return (true, sample.flags)
            case .flagsChanged:
                if trigger == .capsLock {
                    isHeld = (sample.flags & CGEventFlags.maskAlphaShift.rawValue) != 0
                } else if trigger == .rightOption {
                    isHeld = (sample.flags & CGEventFlags.maskAlternate.rawValue) != 0
                }
                return (false, sample.flags)
            }
        }
        guard isHeld, sample.phase == .down || sample.phase == .up else { return (false, sample.flags) }
        return (false, sample.flags | Self.hyperFlags)
    }
}

struct QuitProtectionState: Equatable, Sendable {
    static let quitKeyCode: UInt16 = 12  // Q
    static let closeKeyCode: UInt16 = 13 // W
    static let minConfirmDelayNs: UInt64 = 80_000_000
    static let confirmWindowNs: UInt64 = 1_500_000_000
    struct Pending: Equatable, Sendable {
        let keyCode: UInt16
        let pid: Int32
        let timestampNs: UInt64
    }
    private(set) var pending: Pending?

    mutating func reset() { pending = nil }

    mutating func evaluate(_ sample: KeyGuardSample, enabled: Bool, protectClose: Bool) -> (intercepted: Bool, hint: String?) {
        guard enabled, sample.phase == .down, sample.frontmostPID > 0 else { return (false, nil) }
        let cmdOnlyMask = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
        guard (sample.flags & cmdOnlyMask) == CGEventFlags.maskCommand.rawValue else { return (false, nil) }
        let isQuit = sample.keyCode == Self.quitKeyCode
        let isClose = protectClose && sample.keyCode == Self.closeKeyCode
        guard isQuit || isClose else { return (false, nil) }
        if sample.isRepeat {
            return (true, nil)
        }
        if let current = pending,
           current.keyCode == sample.keyCode,
           current.pid == sample.frontmostPID,
           sample.timestampNs >= current.timestampNs,
           (sample.timestampNs - current.timestampNs) >= Self.minConfirmDelayNs,
           (sample.timestampNs - current.timestampNs) <= Self.confirmWindowNs {
            pending = nil
            return (false, "Confirmed \(isQuit ? "⌘Q" : "⌘W") in \(sample.frontmostAppName).")
        }
        pending = Pending(keyCode: sample.keyCode, pid: sample.frontmostPID, timestampNs: sample.timestampNs)
        let label = isQuit ? "⌘Q to quit" : "⌘W to close window in"
        return (true, "Press \(label) \(sample.frontmostAppName) again within 1.5s to confirm.")
    }
}

struct TextSnippet: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var trigger: String
    var replacement: String
    var enabled = true

    static func validate(trigger: String, replacement: String, existing: [TextSnippet], ignoringID: UUID? = nil) -> String? {
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...32).contains(cleanTrigger.count) else {
            return "Trigger must be between 2 and 32 characters."
        }
        guard !cleanTrigger.contains(where: \.isWhitespace) else {
            return "Trigger cannot contain spaces or line breaks."
        }
        let cleanReplacement = replacement.trimmingCharacters(in: .newlines)
        guard (1...500).contains(cleanReplacement.count) else {
            return "Replacement text must be between 1 and 500 characters."
        }
        guard !cleanReplacement.localizedCaseInsensitiveContains(cleanTrigger) else {
            return "Replacement cannot contain the trigger itself."
        }
        if existing.contains(where: { $0.id != ignoringID && $0.trigger.caseInsensitiveCompare(cleanTrigger) == .orderedSame }) {
            return "A snippet with this trigger already exists."
        }
        return nil
    }
}

struct SnippetExpansionRequest: Equatable, Sendable {
    let trigger: String
    let replacement: String
    let pid: Int32
}

struct SnippetMatcher: Equatable, Sendable {
    static let maxBufferLength = 32
    static let resetKeyCodes: Set<UInt16> = [36, 48, 53, 123, 124, 125, 126] // Return, Tab, Escape, Arrows
    static let backspaceKeyCode: UInt16 = 51
    private(set) var buffer = ""

    mutating func reset() { buffer = "" }

    mutating func feed(_ sample: KeyGuardSample, enabled: Bool, snippets: [TextSnippet]) -> SnippetExpansionRequest? {
        guard enabled, sample.phase == .down else { return nil }
        let blockingFlags = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
        if (sample.flags & blockingFlags) != 0 {
            buffer = ""; return nil
        }
        if Self.resetKeyCodes.contains(sample.keyCode) {
            buffer = ""; return nil
        }
        if sample.keyCode == Self.backspaceKeyCode {
            if !buffer.isEmpty { buffer.removeLast() }
            return nil
        }
        guard !sample.characters.isEmpty, sample.characters.allSatisfy({ !$0.isNewline }) else { return nil }
        buffer.append(sample.characters)
        if buffer.count > Self.maxBufferLength {
            buffer = String(buffer.suffix(Self.maxBufferLength))
        }
        for snippet in snippets where snippet.enabled && !snippet.trigger.isEmpty {
            if buffer.hasSuffix(snippet.trigger) {
                buffer = ""
                return SnippetExpansionRequest(trigger: snippet.trigger, replacement: snippet.replacement, pid: sample.frontmostPID)
            }
        }
        return nil
    }
}

struct InputGuardsOptions: Equatable, Sendable {
    var clickDebounceEnabled = false
    var clickDebounceMs = 35
    var keyDebounceEnabled = false
    var keyDebounceMs = 30
    var superKeyEnabled = false
    var superKeyTrigger: SuperKeyTrigger = .f18
    var quitProtectionEnabled = false
    var protectCloseWindow = false
    var snippetsEnabled = false
    var snippets: [TextSnippet] = []

    var keyboardEnabled: Bool {
        keyDebounceEnabled || superKeyEnabled || quitProtectionEnabled || (snippetsEnabled && snippets.contains(where: \.enabled))
    }
    var enabled: Bool {
        clickDebounceEnabled || keyboardEnabled
    }
}
