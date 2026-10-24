import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", calendar = "Calendar", focus = "Timers", activation = "Activation", appearance = "Appearance", dynamicIsland = "Dynamic Island", aiLimits = "AI agents", audio = "Audio", clipboard = "Clipboard", system = "System", keepAwake = "Keep awake", displayPower = "Display & power"
    var id: String { rawValue }
    case desktop = "Windows", files = "Files", capture = "Capture", agentRoom = "Ada’s room"
    func title(english: Bool) -> String {
        if english { return self == .overview ? "Home" : self == .agentRoom ? "Conversations" : rawValue }
        switch self {
        case .overview: return "Início"
        case .agentRoom: return "Conversas"
        case .calendar: return "Agenda"
        case .focus: return "Timers"
        case .activation: return "Ativação"
        case .appearance: return "Aparência"
        case .dynamicIsland: return "Widget"
        case .aiLimits: return "Uso de IA"
        case .audio: return "Áudio"
        case .clipboard: return "Área de transferência"
        case .system: return "Sistema"
        case .keepAwake: return "Keep Awake"
        case .displayPower: return "Tela e energia"
        case .desktop: return "Janelas"
        case .files: return "Biblioteca e arquivos"
        case .capture: return "Captura"
        }
    }
    static let workspaceSections: [Self] = [.overview, .agentRoom, .calendar, .focus, .files, .capture, .clipboard]
    static let preferenceSections: [Self] = [.activation, .appearance, .dynamicIsland, .audio, .aiLimits, .system, .keepAwake, .displayPower, .desktop]
    func subtitle(english: Bool) -> String {
        switch self {
        case .overview: english ? "Your people, conversations and next steps, together." : "Sua equipe, suas conversas e seus próximos passos, juntos."
        case .agentRoom: english ? "Start with Sieg. Bring a specialist into the conversation when you need one." : "Comece com o Sieg e conte com um especialista quando precisar."
        case .calendar: english ? "A clear view of your commitments and reminders." : "Seus compromissos e lembretes, em uma visão clara."
        case .focus: english ? "One thing at a time. Choose your pace." : "Uma coisa de cada vez. Escolha seu ritmo."
        case .files: english ? "Keep useful documents and finished work within reach." : "Seus documentos e resultados úteis, sempre por perto."
        case .capture: english ? "Save a moment, highlight a detail, read what's on screen." : "Guarde uma imagem, destaque um detalhe e leia o que está na tela."
        case .clipboard: english ? "Find and reuse what you've copied on this Mac." : "Encontre e reutilize o que você copiou neste Mac."
        case .activation: english ? "Choose how to call Sieg, speak and interact." : "Escolha como chamar o Sieg, falar e interagir."
        case .appearance: english ? "A space that fits your day, with your companions close by." : "Um espaço com a sua cara e seus companheiros por perto."
        case .dynamicIsland: english ? "Arrange your floating companion and quick controls." : "Organize seu companheiro flutuante e os controles rápidos."
        case .audio: english ? "Your sound devices and app volume, in one place." : "Dispositivos de som e volume dos apps, no mesmo lugar."
        case .aiLimits: english ? "Understand your usage, limits and recent activity." : "Acompanhe seu uso, os limites e a atividade recente."
        case .system: english ? "A clear view of how your Mac is doing." : "Uma visão clara de como o seu Mac está funcionando."
        case .keepAwake: english ? "Keep your Mac awake for as long as you need." : "Mantenha seu Mac acordado pelo tempo que você precisar."
        case .displayPower: english ? "Make your screen and power settings comfortable." : "Ajuste a tela e a energia para o seu dia."
        case .desktop: english ? "Make room for your work. Arrange windows and spaces." : "Dê espaço ao seu trabalho. Organize janelas e áreas de trabalho."
        }
    }
    var symbol: String {
        switch self {
        case .desktop: "macwindow.on.rectangle"
        case .overview: "square.grid.2x2"
        case .calendar: "calendar"
        case .focus: "timer"
        case .activation: "keyboard"
        case .appearance: "slider.horizontal.3"
        case .dynamicIsland: "rectangle.topthird.inset.filled"
        case .aiLimits: "chart.bar.xaxis"
        case .agentRoom: "bubble.left.and.bubble.right"
        case .audio: "speaker.wave.2"
        case .system: "cpu"
        case .keepAwake: "cup.and.saucer"
        case .displayPower: "sun.max"
        case .clipboard: "doc.on.clipboard"
        case .files: "tray"
        case .capture: "viewfinder"
        }
    }
}

@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published var section: AppSection
    init(section: AppSection = .overview) { self.section = section }
}
