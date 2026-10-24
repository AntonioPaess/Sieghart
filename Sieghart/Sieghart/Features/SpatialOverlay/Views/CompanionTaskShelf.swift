import SwiftUI
import AppKit

struct CompanionTaskShelf: View {
    @ObservedObject var journal: CompanionTaskJournal
    let language: String
    let resume: (UUID) -> Void
    let pause: (UUID) -> Void
    private var english: Bool { language.hasPrefix("en") }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(english ? "Your work with Sieg" : "Seu trabalho com o Sieg", systemImage: "tray.full")
                .font(.headline)
            if journal.tasks.isEmpty {
                Text(english ? "Research, diagrams and walkthroughs stay here so you can return to them." : "Pesquisas, diagramas e orientações ficam aqui para você retomar depois.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let issue = journal.storageIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
            ForEach(journal.tasks) { task in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        if !task.progress.isEmpty { Text(task.progress).font(.caption).foregroundStyle(.secondary) }
                        if !task.fullResult.isEmpty {
                            ScrollView { Text(task.fullResult).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                .frame(maxHeight: 230)
                            Button(english ? "Copy result" : "Copiar resultado") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(task.fullResult, forType: .string)
                            }
                        }
                        HStack {
                            if task.canResume {
                                Button(english ? "Resume" : "Retomar") { resume(task.id) }
                                    .buttonStyle(CompanionButtonStyle(primary: true))
                            }
                            if task.state == .running { Button(english ? "Pause" : "Pausar") { pause(task.id) } }
                            Text(task.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 8)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbol(task.kind)).foregroundStyle(CompanionStyle.accentInk)
                        Text(task.request).font(.callout.weight(.medium)).lineLimit(2)
                        Spacer()
                        Text(task.stateTitle(english: english)).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private func symbol(_ kind: CompanionTaskRecord.Kind) -> String {
        switch kind { case .research: "books.vertical"; case .canvas: "point.3.connected.trianglepath.dotted"; case .guidance: "arrow.triangle.turn.up.right.diamond"; case .specialist: "person.2"; case .workflow: "list.number" }
    }
}
