import SwiftUI
import UniformTypeIdentifiers

@MainActor enum AIProviderResources { static var bundle = Bundle.main }

struct ProviderMark: View {
    let provider: AIProvider
    var size: CGFloat = 30
    private var tint: Color {
        switch provider {
        case .codex: CompanionStyle.accentInk
        case .claude: Color(red: 0.85, green: 0.53, blue: 0.39)
        case .antigravity: Color(red: 0.34, green: 0.62, blue: 0.98)
        }
    }
    var body: some View {
        Image(provider.assetName, bundle: AIProviderResources.bundle).resizable().renderingMode(.template).scaledToFit()
            .foregroundStyle(tint)
            .padding(size * 0.18).frame(width: size, height: size)
            .background(CompanionStyle.background, in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}
