import SwiftUI

struct CompanionRoutineShelf: View {
    @ObservedObject var routines: CompanionRoutines
    let language: String
    @State private var adding = false
    @State private var title = ""
    @State private var prompt = ""
    @State private var kind: CompanionRoutine.Kind = .briefing
    @State private var time = Date()
    private var en: Bool { language.hasPrefix("en") }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(en ? "Routines" : "Rotinas").font(.title3.weight(.semibold)); Spacer()
                Button(en ? "Add routine" : "Criar rotina") { adding = true }
            }
            Text(en ? "Daily research or calendar briefings while this Mac and the app are running. Results stay silent in your library." : "Pesquisas ou resumos diários da agenda enquanto este Mac e o app estão em funcionamento. Os resultados ficam na biblioteca, sem áudio.").font(.caption).foregroundStyle(.secondary)
            if let issue = routines.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
            ForEach(routines.items) { routine in
                HStack {
                    Toggle(routine.title, isOn: Binding(get: { routine.enabled }, set: { routines.setEnabled(routine.id, $0) })).toggleStyle(.switch)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(routine.nextRun, style: .time).font(.caption).monospacedDigit()
                        Text(routine.status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Button(en ? "Run now" : "Executar agora") { routines.runNow(routine.id) }.disabled(routines.activeID != nil)
                }.padding(12).background(CompanionStyle.edge.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            }
        }.sheet(isPresented: $adding) {
            VStack(alignment: .leading, spacing: 18) {
                Text(en ? "A daily routine" : "Uma rotina diária").font(.title2.weight(.semibold))
                TextField(en ? "Name" : "Nome", text: $title).textFieldStyle(.roundedBorder)
                Picker(en ? "Type" : "Tipo", selection: $kind) {
                    Text(en ? "Calendar briefing" : "Resumo da agenda").tag(CompanionRoutine.Kind.briefing)
                    Text(en ? "Web research" : "Pesquisa na web").tag(CompanionRoutine.Kind.research)
                }
                TextField(en ? "What should Sieg prepare?" : "O que o Sieg deve preparar?", text: $prompt, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                DatePicker(en ? "Time" : "Horário", selection: $time, displayedComponents: .hourAndMinute)
                Text(en ? "The routine is created switched off. Enable it when you want it to begin. Three consecutive failures pause it." : "A rotina é criada desligada. Ative quando quiser começar. Três falhas consecutivas a pausam.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(en ? "Cancel" : "Cancelar") { adding = false }; Spacer()
                    Button(en ? "Create routine" : "Criar rotina") {
                        let calendar = Calendar.current, parts = calendar.dateComponents([.hour, .minute], from: time)
                        var routine = CompanionRoutine(title: title, kind: kind, prompt: prompt, hour: parts.hour ?? 9, minute: parts.minute ?? 0, timezone: calendar.timeZone.identifier, language: language, nextRun: Date())
                        routine.nextRun = routine.following(Date()) ?? Date().addingTimeInterval(86400)
                        routines.add(routine); adding = false
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.padding(26).frame(width: 500)
        }
    }
}
