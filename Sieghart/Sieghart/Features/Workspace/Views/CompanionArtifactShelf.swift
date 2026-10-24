import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct CompanionArtifactShelf: View {
    @ObservedObject var library: CompanionArtifactLibrary
    let language: String
    @Environment(\.islandPreview) private var preview
    @State private var selected: CompanionArtifact?
    @State private var search = ""
    private var en: Bool { language.hasPrefix("en") }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(en ? "Your library" : "Sua biblioteca").font(.title3.weight(.semibold))
                Spacer()
                Button(en ? "Import a document" : "Importar documento") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [.pdf, .plainText, .sourceCode, .json, .commaSeparatedText]
                    if panel.runModal() == .OK, let url = panel.url { Task { do { _ = try await library.importDocument(url) } catch { library.report(error) } } }
                }
            }
            if let issue = library.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
            if library.items.isEmpty {
                Text(en ? "Research, code, diagrams and imported documents will appear here." : "Pesquisas, códigos, diagramas e documentos importados ficam aqui.").foregroundStyle(.secondary).font(.callout)
            } else {
                if preview { Text(en ? "Find a result" : "Encontrar um resultado").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)) }
                else { TextField(en ? "Find a result" : "Encontrar um resultado", text: $search).textFieldStyle(.roundedBorder) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(library.items.filter { search.isEmpty || $0.title.localizedStandardContains(search) || $0.content.localizedStandardContains(search) }) { item in
                        Button { selected = item } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12).fill(CompanionStyle.accent.opacity(0.07))
                                    if let diagram = item.diagram {
                                        CanvasDiagramView(document: .init(title: item.title, spokenSummary: item.title, code: "", codeLanguage: "", elements: [], diagram: diagram), diagram: diagram, progress: 1)
                                            .frame(width: 600, height: 600).scaleEffect(0.18).frame(width: 120, height: 108).clipped()
                                    } else if let url = library.url(for: item), url.pathExtension.lowercased() == "pdf" { CompanionPDFThumbnail(url: url) }
                                    else { Image(systemName: symbol(item.kind)).font(.system(size: 30)).foregroundStyle(CompanionStyle.accentInk) }
                                }.frame(height: 110).clipped()
                                Text(item.title).font(.callout.weight(.medium)).lineLimit(2)
                                Text(item.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(CompanionStyle.edge.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).onDrag { library.url(for: item).flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider(object: item.content as NSString) }
                            .contextMenu {
                                Button(en ? "Export…" : "Exportar…") { library.export(item) }
                                if let url = library.url(for: item) { Button(en ? "Show in Finder" : "Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                            }
                    }
                }
            }
        }.sheet(item: $selected) { item in
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(item.title).font(.title2.weight(.semibold)); Spacer()
                    Button(en ? "Export…" : "Exportar…") { library.export(item) }
                    Button(en ? "Close" : "Fechar") { selected = nil }
                }
                if let url = library.url(for: item), url.pathExtension.lowercased() == "pdf" { CompanionPDFPreview(url: url) }
                else if let diagram = item.diagram {
                    CanvasDiagramView(document: .init(title: item.title, spokenSummary: item.title, code: "", codeLanguage: "", elements: [], diagram: diagram), diagram: diagram, progress: 1)
                } else if let elements = item.elements, !elements.isEmpty {
                    GeneratedCanvasView(document: .init(title: item.title, spokenSummary: item.title, code: "", codeLanguage: "", elements: elements), progress: 1, opacity: 1)
                } else { ScrollView { Text(item.content).font(item.kind == .code ? .system(.body, design: .monospaced) : .body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
            }.padding(24).frame(minWidth: 640, minHeight: 580)
        }
    }
    private func symbol(_ kind: CompanionArtifact.Kind) -> String {
        switch kind { case .code: "curlybraces"; case .diagram: "point.3.connected.trianglepath.dotted"; case .research: "books.vertical"; case .document: "doc.text"; case .text: "text.alignleft" }
    }
}
