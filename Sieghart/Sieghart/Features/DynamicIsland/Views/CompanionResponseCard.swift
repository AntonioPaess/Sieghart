import AppKit
import SwiftUI

struct CompanionResponse: Identifiable, Equatable {
    enum Kind: String { case answer, screen, canvas, action, research, guidance }
    let id: UUID
    var kind: Kind
    var text: String
    var succeeded: Bool
    var speaker: LocalChatPersona
    init(id: UUID = UUID(), kind: Kind, text: String, succeeded: Bool = true, speaker: LocalChatPersona = .sig) {
        self.id = id; self.kind = kind; self.text = text; self.succeeded = succeeded
        self.speaker = speaker
    }
}

struct CompanionResponseCard: View {
    static let height: CGFloat = 164
    var needsScreenPermission = false
    var retryScreen: (() -> Void)? = nil
    let response: CompanionResponse
    let language: String
    let speaks: Bool
    let stop: () -> Void
    let dismiss: () -> Void
    let clearContext: () -> Void
    var reviewSummary: String? = nil
    var confirmReview: (() -> Void)? = nil
    var cancelReview: (() -> Void)? = nil
    @State private var copied = false
    @Environment(\.islandPreview) private var preview
    private var english: Bool { language.hasPrefix("en") }
    private var symbol: String {
        if !response.succeeded { return "exclamationmark.circle" }
        switch response.kind {
        case .answer: return "bubble.left.and.text.bubble.right"
        case .screen: return "viewfinder"
        case .canvas: return "point.3.connected.trianglepath.dotted"
        case .action: return "checkmark.circle"
        case .research: return "books.vertical"
        case .guidance: return "arrow.turn.down.right"
        }
    }
    private var title: String {
        if needsScreenPermission { return english ? "Screen access" : "Acesso à tela" }
        if !response.succeeded { return english ? "Let’s try again" : "Vamos tentar novamente" }
        let heading: String
        switch response.kind {
        case .answer: heading = english ? "Reply" : "Resposta"
        case .screen: heading = english ? "On your screen" : "Na sua tela"
        case .canvas: heading = english ? "Drawing" : "Desenho"
        case .action: heading = english ? "App action" : "Ação no app"
        case .research: heading = english ? "Research" : "Pesquisa"
        case .guidance: heading = english ? "Next step" : "Próximo passo"
        }
        return heading + " · " + response.speaker.title
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: needsScreenPermission ? "lock.open" : symbol)
                    .foregroundStyle(response.succeeded || needsScreenPermission ? CompanionStyle.accentInk : .orange)
                    .frame(width: 26, height: 26)
                    .background(CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(CompanionStyle.ink)
                Spacer(minLength: 4)
                if speaks {
                    Button(action: stop) { Image(systemName: "stop.fill").font(.system(size: 10)) }
                        .accessibilityLabel(english ? "Stop speaking" : "Parar fala")
                }
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .accessibilityLabel(english ? "Close reply" : "Fechar resposta")
            }.buttonStyle(CompanionButtonStyle(compact: true))
            Group {
                if preview { replyContent }
                else { ScrollView { replyContent }.scrollIndicators(.hidden) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let reviewSummary {
                HStack(spacing: 8) {
                    Button(english ? "Confirm action" : "Confirmar ação") { confirmReview?() }
                        .buttonStyle(CompanionButtonStyle(primary: true, compact: true)).help(reviewSummary)
                    Button(english ? "Cancel" : "Cancelar") { cancelReview?() }
                        .buttonStyle(CompanionButtonStyle(compact: true))
                }
            }
            HStack(spacing: 12) {
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(response.text, forType: .string)
                    copied = true
                } label: { Label(copied ? (english ? "Copied" : "Copiado") : (english ? "Copy" : "Copiar"), systemImage: copied ? "checkmark" : "doc.on.doc") }
                Spacer(minLength: 4)
                Button(action: clearContext) { Text(english ? "Clear context" : "Limpar contexto") }
            }.font(.system(size: 11)).foregroundStyle(CompanionStyle.muted).buttonStyle(.plain)
        }.padding(16).frame(height: Self.preferredHeight(needsScreenPermission: needsScreenPermission, reviewingAction: reviewSummary != nil))
            .modifier(WorkspaceSurface(radius: 18))
            .onChange(of: response.id) { _, _ in copied = false }
    }
    static func preferredHeight(needsScreenPermission: Bool, reviewingAction: Bool) -> CGFloat {
        (needsScreenPermission ? 244 : height) + (reviewingAction ? 38 : 0)
    }
    @ViewBuilder private var replyContent: some View {
        if needsScreenPermission { ScreenPermissionHelp(language: language, retry: retryScreen) }
        else {
            Text((try? AttributedString(markdown: response.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(response.text))
                .font(.system(size: 13)).foregroundStyle(CompanionStyle.ink.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
    }
}
