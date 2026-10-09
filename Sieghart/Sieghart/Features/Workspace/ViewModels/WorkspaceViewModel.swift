import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", focus = "Timers", activation = "Activation", appearance = "Appearance", dynamicIsland = "Dynamic Island", aiLimits = "AI agents", audio = "Audio", clipboard = "Clipboard", system = "System", keepAwake = "Keep awake", displayPower = "Display & power"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .focus: "timer"
        case .activation: "keyboard"
        case .appearance: "slider.horizontal.3"
        case .dynamicIsland: "rectangle.topthird.inset.filled"
        case .aiLimits: "chart.bar.xaxis"
        case .audio: "speaker.wave.2"
        case .system: "cpu"
        case .keepAwake: "cup.and.saucer"
        case .displayPower: "sun.max"
        case .clipboard: "doc.on.clipboard"
        }
    }
}

@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published var section: AppSection
    init(section: AppSection = .overview) { self.section = section }
}
