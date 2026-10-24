import SwiftUI

struct KeepAwakeInlineCard: View {
    @ObservedObject var model: KeepAwakeViewModel
    let receipt: LocalChatUtilityReceipt
    @Environment(\.locale) private var locale
    private var en: Bool { locale.language.languageCode?.identifier == "en" }
    private var current: Bool { model.enabled && model.request.end == receipt.deadline }
    private var remaining: String {
        guard let seconds = model.remaining, current else { return current ? "∞" : "—" }
        let value = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(current ? .mint : .secondary)
                Text("Keep Awake").font(.callout.weight(.semibold))
                Spacer()
                Circle().fill(current && model.holding ? Color.mint : Color.secondary).frame(width: 6, height: 6)
                Text(current ? (model.holding ? (en ? "Active" : "Ativo") : (en ? "Waiting" : "Aguardando")) : (en ? "Ended" : "Encerrado")).font(.caption)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(remaining).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                Spacer()
                if current { Button(en ? "Stop" : "Encerrar") { model.stop() }.buttonStyle(.bordered) }
            }
            if current, let remaining = model.remaining {
                let progress = min(1, max(0, 1 - remaining / Double(max(1, model.request.minutes) * 60)))
                GeometryReader { bounds in
                    Capsule().fill(.mint.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.mint).frame(width: bounds.size.width * progress)
                        }
                }.frame(height: 4)
                    .accessibilityLabel(en ? "Elapsed time" : "Tempo decorrido")
                    .accessibilityValue("\(Int(progress * 100))%")
            }
            Text(current ? (model.holding ? (en ? "Your Mac is being kept awake." : "Seu Mac está sendo mantido acordado.") : (en ? "Waiting for your configured power or app conditions." : "Aguardando as condições de energia ou apps que você definiu.")) : (en ? "This session is no longer active." : "Este período não está mais ativo."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: 390, alignment: .leading)
            .background(Color.mint.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.mint.opacity(0.18)))
            .accessibilityElement(children: .combine)
    }
}
