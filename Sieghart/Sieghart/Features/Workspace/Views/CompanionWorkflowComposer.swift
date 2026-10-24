import SwiftUI

struct CompanionWorkflowComposer: View {
    @ObservedObject var runner: CompanionWorkflowRunner
    let language: String
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var steps: [CompanionWorkflowStep] = [.init(persona: .ada), .init(persona: .toni)]
    @State private var error: String?
    private var en: Bool { language.hasPrefix("en") }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(en ? "Work in stages" : "Trabalho em etapas").font(.title2.weight(.semibold)); Spacer(); Button(en ? "Close" : "Fechar") { dismiss() } }
            Text(en ? "Choose who handles each step. Every completed result goes to the next person. This flow researches and writes; it does not click, send messages or run generated code." : "Escolha quem cuida de cada etapa. O resultado concluído passa para a próxima pessoa. Este fluxo pesquisa e escreve; não clica, envia mensagens ou executa código gerado.").font(.callout).foregroundStyle(.secondary)
            TextField(en ? "Task name" : "Nome da tarefa", text: $title).textFieldStyle(.roundedBorder)
            ScrollView {
                ForEach($steps) { $step in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker(en ? "Type" : "Tipo", selection: $step.kind) {
                                Text(en ? "Specialist" : "Especialista").tag(CompanionWorkflowStep.Kind.specialist)
                                Text(en ? "Web research" : "Pesquisa na web").tag(CompanionWorkflowStep.Kind.research)
                            }
                            if step.kind == .specialist { Picker(en ? "Person" : "Pessoa", selection: $step.persona) { ForEach(LocalChatPersona.allCases, id: \.self) { Text($0.title).tag($0) } } }
                            if steps.count > 2 { Button { steps.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain) }
                        }
                        TextField(en ? "What should this step deliver?" : "O que esta etapa deve entregar?", text: $step.request, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                    }.padding(14).background(CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
                }
            }
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            HStack {
                Button(en ? "Add step" : "Adicionar etapa") { steps.append(.init()) }.disabled(steps.count >= 6)
                Spacer()
                Button(en ? "Start task" : "Iniciar tarefa") {
                    do { try runner.start(title: title, steps: steps, language: language); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(CompanionButtonStyle(primary: true)).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !steps.allSatisfy(\.valid) || runner.activeID != nil)
            }
        }.padding(26).frame(width: 650, height: 620)
    }
}
