import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
    var nativeAppearance: NSAppearance? { self == .light ? NSAppearance(named: .aqua) : self == .dark ? NSAppearance(named: .darkAqua) : nil }
}

enum WidgetSize: String, CaseIterable, Identifiable {
    case small = "Small", medium = "Medium", large = "Large"
    var id: String { rawValue }
    var scale: CGFloat { self == .small ? 0.85 : self == .large ? 1.2 : 1 }
}

enum IslandRailAction: String, CaseIterable, Identifiable {
    case tools = "All tools", timer = "Timers", calendar = "Calendar", clipboard = "Clipboard", preferences = "Preferences", audio = "Audio", ai = "AI agents", avatars = "Avatars", voice = "Speak", companion = "Companion", system = "System", keepAwake = "Keep awake", displayPower = "Display & power", none = "Hidden"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .tools: "square.grid.2x2"
        case .timer: "timer"
        case .calendar: "calendar"
        case .clipboard: "doc.on.clipboard"
        case .preferences: "gearshape"
        case .audio: "speaker.wave.2"
        case .ai: "sparkles"
        case .avatars: "person.crop.square"
        case .voice: "mic"
        case .companion: "face.smiling"
        case .system: "cpu"
        case .keepAwake: "cup.and.saucer"
        case .displayPower: "sun.max"
        case .none: "minus"
        }
    }
}
enum IslandRailPreset: String, CaseIterable, Identifiable {
    case essentials = "Essentials", focus = "Focus", work = "Work"
    var id: String { rawValue }
    var actions: [IslandRailAction] {
        switch self {
        case .essentials: [.tools, .timer, .clipboard, .preferences, .audio, .ai]
        case .focus: [.timer, .companion, .clipboard, .preferences, .audio, .voice]
        case .work: [.ai, .clipboard, .tools, .preferences, .audio, .voice]
        }
    }
}

enum IslandToolAction: String, CaseIterable, Identifiable {
    case companion = "Companion", audio = "Audio", ai = "AI agents", timer = "Timers"
    case clipboard = "Clipboard", calendar = "Calendar", avatars = "Avatars", system = "System"
    case keepAwake = "Keep awake", displayPower = "Display & power", preferences = "Preferences"

    var id: String { rawValue }
    static let defaultSelection: [Self] = [.companion, .audio, .ai, .timer, .clipboard,
                                            .calendar, .avatars, .system, .keepAwake, .displayPower]
    var symbol: String {
        switch self {
        case .companion: "face.smiling"
        case .audio: "speaker.wave.2"
        case .ai: "sparkles"
        case .timer: "timer"
        case .clipboard: "doc.on.clipboard"
        case .calendar: "calendar"
        case .avatars: "person.crop.square"
        case .system: "cpu"
        case .keepAwake: "cup.and.saucer"
        case .displayPower: "sun.max"
        case .preferences: "gearshape"
        }
    }
    var subtitle: String {
        switch self {
        case .companion: "Your companion"
        case .audio: "Apps & devices"
        case .ai: "Limits & activity"
        case .timer: "Three ways to time"
        case .clipboard: "Copies, kept nearby"
        case .calendar: "Events & reminders"
        case .avatars: "Find your companion"
        case .system: "Live readings"
        case .keepAwake: "On your terms"
        case .displayPower: "Screen and sleep"
        case .preferences: "Your workspace"
        }
    }
}
