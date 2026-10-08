import SwiftUI

enum MenuPage: String, CaseIterable {
    case companion = "Companion", timers = "Timers", ai = "AI", audio = "Audio", clipboard = "Clipboard", avatars = "Avatars", system = "System", keepAwake = "Keep awake", displayPower = "Display & power"
    var symbol: String { switch self { case .companion: "face.smiling"; case .timers: "timer"; case .ai: "sparkles"; case .audio: "speaker.wave.2"; case .clipboard: "doc.on.clipboard"; case .avatars: "person.crop.square"; case .system: "cpu"; case .keepAwake: "cup.and.saucer"; case .displayPower: "sun.max" } }
}
@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var page: MenuPage
    init(initialPage: String = "Companion") { page = MenuPage(rawValue: initialPage) ?? .companion }
}
