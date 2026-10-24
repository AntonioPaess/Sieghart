import SwiftUI

/// A rehearsal consumes events only inside its own visible target. It cannot
/// start microphone capture, install hooks or execute a model-generated action.
struct CompanionVoiceTutorial: View {
    let language: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holding = false
    @State private var sent = false
    @State private var interrupted = false
    @State private var start: CGPoint?
    @State private var end: CGPoint?
    @State private var pointer = CGPoint(x: 150, y: 90)
    @FocusState private var focused: Bool
    private var en: Bool { language.hasPrefix("en") }
    private var selected: CGRect? {
        guard let start, let end, abs(end.x-start.x) > 12, abs(end.y-start.y) > 12 else { return nil }
        return .init(x: min(start.x,end.x), y: min(start.y,end.y), width: abs(end.x-start.x), height: abs(end.y-start.y))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(en ? "A little rehearsal" : "Um ensaio rápido").font(.title2.weight(.semibold)); Spacer(); Button(en ? "Close" : "Fechar") { dismiss() } }
            Text(en ? "Hold Space in this area to rehearse listening. Drag around the text, then release Space to send. Press again to interrupt." : "Segure Espaço nesta área para ensaiar a escuta. Arraste em volta do texto e solte Espaço para enviar. Pressione de novo para interromper.").foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22).fill(CompanionStyle.edge.opacity(0.05))
                VStack(alignment: .leading, spacing: 8) {
                    Text(en ? "Text you can point at" : "Um texto para apontar").font(.title3.weight(.medium))
                    Text(en ? "The circumference is 2 × π × radius." : "A circunferência mede 2 × π × raio.")
                }.padding(35)
                if let selected { RoundedRectangle(cornerRadius: 8).stroke(.purple, style: StrokeStyle(lineWidth: 2, dash: [6,4])).background(.purple.opacity(0.08)).frame(width: selected.width, height: selected.height).position(x: selected.midX, y: selected.midY) }
                if holding {
                    HStack(spacing: 3) { CompanionCharacter(size: 32, avatar: .sig, animates: !reduceMotion, listening: true); Text(en ? "Listening" : "Escutando").font(.caption) }
                        .padding(6).background(.thinMaterial, in: Capsule()).position(x: min(450, pointer.x+65), y: min(200, pointer.y+25))
                }
            }.frame(height: 230).contentShape(Rectangle()).focusable().focused($focused)
                .onContinuousHover { if case .active(let point) = $0 { pointer = point } }
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in guard holding else { return }; start = value.startLocation; end = value.location }.onEnded { _ in })
                .onKeyPress(.space, phases: [.down, .repeat, .up]) { press in
                    if press.phase == .up { if holding { holding = false; sent = true }; return .handled }
                    if press.phase == .down { if sent { interrupted = true }; holding = true }
                    return .handled
                }
            HStack {
                Label(holding ? (en ? "Listening" : "Escutando") : interrupted ? (en ? "Reply interrupted" : "Resposta interrompida") : sent ? (en ? "Request sent" : "Pedido enviado") : (en ? "Ready" : "Pronto"), systemImage: holding ? "mic" : sent ? "checkmark.circle" : "keyboard")
                Spacer()
                Button(en ? "Hold to rehearse" : "Segure para ensaiar") {}.buttonStyle(.bordered)
                    .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in if sent { interrupted = true }; holding = true }.onEnded { _ in holding = false; sent = true })
            }
            if sent && !holding { Text(en ? "Example: π relates a circle's circumference to its diameter. Your selected area accompanied this request." : "Exemplo: π relaciona a circunferência ao diâmetro. A região que você marcou acompanhou esse pedido.").padding(14).background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)) }
            Text(en ? "Rehearsal only: no recording or speech. In daily use, hold your configured voice shortcut instead of Space." : "Este ensaio não grava nem fala. No uso real, segure o atalho de voz configurado em vez de Espaço.").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 580).onAppear { focused = true }
    }
}
