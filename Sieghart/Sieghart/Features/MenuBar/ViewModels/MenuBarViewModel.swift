import SwiftUI

enum MenuPage: String, CaseIterable {
    case companion = "Companion", calendar = "Calendar", timers = "Timers", ai = "AI", audio = "Audio", clipboard = "Clipboard", avatars = "Team", system = "System", keepAwake = "Keep awake", displayPower = "Display & power"
    case desktop = "Windows", files = "Files", capture = "Capture"
    var symbol: String { switch self { case .desktop: "macwindow.on.rectangle"; case .companion: "face.smiling"; case .calendar: "calendar"; case .timers: "timer"; case .ai: "sparkles"; case .audio: "speaker.wave.2"; case .clipboard: "doc.on.clipboard"; case .avatars: "person.crop.square"; case .system: "cpu"; case .keepAwake: "cup.and.saucer"; case .displayPower: "sun.max"; case .files: "tray"; case .capture: "viewfinder" } }
}
@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var page: MenuPage
    init(initialPage: String = "Companion") { page = MenuPage(rawValue: initialPage) ?? .companion }
}
