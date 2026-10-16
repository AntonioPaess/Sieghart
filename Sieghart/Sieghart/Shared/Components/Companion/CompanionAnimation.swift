import SwiftUI

private struct CompanionMotionEnabledKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var companionMotionEnabled: Bool { get { self[CompanionMotionEnabledKey.self] } set { self[CompanionMotionEnabledKey.self] = newValue } }
}

// Motion identifiers are shared by the runtime and the in-app rehearsal surface.
enum CompanionAnimation: Int, CaseIterable, Identifiable, Sendable {
    case launch = 1
    case cursor = 2
    case miniLook = 3
    case breathing = 4
    case blink = 5
    case touch = 6
    case annoyed = 7
    case dizzy = 8
    case working = 9
    case thinking = 10
    case searching = 11
    case approval = 12
    case question = 13
    case failure = 14
    case completed = 15
    case rateLimit = 16
    case sleeping = 17
    case love = 18
    case surprised = 19
    case proud = 20
    case wink = 21
    case yawn = 22
    case happy = 23
    case listening = 24
    case compactListening = 25
    case voiceThinking = 26
    case speaking = 27
    case listeningEnd = 28
    case dance = 29
    case fileHover = 30
    case fileOpen = 31
    case fileReceive = 32
    case fileProcessing = 33
    case uploadProgress = 34
    case uploadComplete = 35
    case fileReturn = 36
    case accessoryInertia = 37
    case accessoryChange = 38
    case flyOut = 39
    case alert = 40
    case interrupted = 41
    case badgeChange = 42
    case hello = 43
    case gulp = 44
    case voiceEnd = 45
    case idle = 46
    case waking = 47
    case stroll = 48
    case understood = 49
    var id: Int { rawValue }
    var title: String { Self.titles[rawValue - 1] }
    var duration: Double { self == .fileOpen ? 0.5 : self == .fileReceive ? 1.3 : Self.durations[rawValue - 1] }
    var holdsFinalPose: Bool { self == .fileOpen }
    var continuous: Bool { [2,3,4,5,9,10,11,12,13,16,17,24,25,26,27,29,33,37,46,48].contains(rawValue) }
    var showsLoading: Bool { [.working,.thinking,.searching,.voiceThinking,.fileProcessing].contains(self) }
    static func resolve(voice: CompanionVoicePhase, mood: CompanionMood, listening: Bool = false, strolling: Bool = false) -> Self {
        switch voice {
        case .preparing, .thinking: return .voiceThinking
        case .listening: return .listening
        case .working: return .working
        case .success: return .understood
        case .failure: return .failure
        case .inactive: break
        }
        if listening { return .listening }
        switch mood {
        case .happy: return .happy
        case .annoyed: return .annoyed
        case .asleep: return .sleeping
        case .waking: return .waking
        case .startled: return .surprised
        case .understood: return .understood
        case .celebrating: return .completed
        case .idle: return strolling ? .stroll : .idle
        }
    }
    private static let titles = ["Launch greeting", "Follow the cursor", "Independent gaze", "Breathe", "Double blink", "Touch", "Annoyed", "Dizzy", "Working", "Thinking", "Searching", "Await approval", "Question", "Error", "Task complete", "Usage limit", "Sleep", "Affection", "Surprise", "Proud", "Wink", "Yawn", "Happy", "Listening", "Compact listening", "Think after voice", "Speaking", "Finish listening", "Dance", "Follow a file", "Open receiver", "Receive a file", "Process a file", "Upload progress", "Upload complete", "Choose destination", "Accessory inertia", "Change accessory", "Fly out & return", "Return for an alert", "Interrupted greeting", "Exchange badge", "Short hello", "Receive quickly", "Finish conversation", "Idle", "Wake up", "Stroll", "Understood"]
    private static let durations: [Double] = [5.2, 3, 3, 3, 3, 3, 3, 3.3, 4, 3, 3, 3, 3, 3, 3, 3, 4.5, 3, 3, 3, 3, 3, 3, 4, 3, 3, 4, 3, 6, 3, 3, 3, 3, 4, 3, 3, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3]
}
