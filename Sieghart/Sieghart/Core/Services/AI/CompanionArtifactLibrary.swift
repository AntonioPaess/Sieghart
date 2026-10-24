import AppKit
import Combine
import Foundation
import PDFKit
import UniformTypeIdentifiers

struct CompanionArtifact: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case text, code, diagram, research, document }
    let id: UUID
    let sourceID: String
    var title: String
    var kind: Kind
    var content: String
    var filename: String
    var date: Date
    var diagram: CanvasDiagram?
    var elements: [CanvasElement]? = nil
    var originalFilename: String? = nil
}

struct CompanionDocument: Sendable {
    let name: String
    let pages: [String]
    let truncated: Bool
    var originalData: Data? = nil
    var originalExtension: String? = nil
    var text: String { pages.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n\n") }
    static func read(_ url: URL) throws -> Self {
        let scope = url.startAccessingSecurityScopedResource(); defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 10_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let limit = url.pathExtension.lowercased() == "pdf" ? 10_000_000 : 128_000
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(data: data), !pdf.isLocked, (1...200).contains(pdf.pageCount) else { throw CocoaError(.fileReadCorruptFile) }
            var pages: [String] = [], budget = 120_000, truncated = false
            for i in 0..<pdf.pageCount {
                let text = pdf.page(at: i)?.string ?? ""
                let slice = String(text.prefix(min(12_000, budget)))
                truncated = truncated || slice.count < text.count
                pages.append(slice); budget -= slice.count
                if budget <= 0 { truncated = truncated || i < pdf.pageCount - 1; break }
            }
            guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            return .init(name: url.lastPathComponent, pages: pages, truncated: truncated, originalData: data, originalExtension: "pdf")
        }
        let extensions: Set<String> = ["txt", "md", "csv", "json", "swift", "py", "js", "ts", "html", "css", "xml", "yaml", "yml", "log"]
        guard extensions.contains(url.pathExtension.lowercased()), (values.fileSize ?? Int.max) <= 128_000 else { throw CocoaError(.fileReadUnsupportedScheme) }
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return .init(name: url.lastPathComponent, pages: [text], truncated: false, originalData: data, originalExtension: url.pathExtension.lowercased())
    }
}

@MainActor final class CompanionArtifactLibrary: ObservableObject {
    @Published private(set) var items: [CompanionArtifact] = []
    @Published private(set) var issue: String?
    let directory: URL?
    private var validStorage = true
    init(directory: URL? = nil) {
        self.directory = directory
        guard let directory else { return }
        let url = directory.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: 4_000_001) ?? Data()
            let saved = try JSONDecoder().decode([CompanionArtifact].self, from: data)
            guard data.count <= 4_000_000, Self.valid(saved) else { throw CocoaError(.fileReadCorruptFile) }
            items = saved
        } catch { validStorage = false; issue = "A biblioteca não pôde ser lida. Os arquivos originais foram preservados." }
    }
    static var productionDirectory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sieghart/Artifacts") }
    func report(_ error: Error) { issue = error.localizedDescription }
    func saveCanvas(_ canvas: GeneratedCanvas) {
        guard (try? canvas.validated()) != nil else { return }
        let kind: CompanionArtifact.Kind = canvas.isCode ? .code : .diagram
        let ext = canvas.isCode ? Self.codeExtension(canvas.codeLanguage) : "svg"
        let content = canvas.isCode ? canvas.code : CanvasSVGExporter.render(canvas)
        upsert(sourceID: "canvas.\(canvas.id)", title: canvas.title, kind: kind, content: content, ext: ext, diagram: canvas.diagram, elements: canvas.elements)
    }
    func saveTask(_ task: CompanionTaskRecord) {
        guard task.state == .completed, task.kind != .canvas, !task.fullResult.isEmpty else { return }
        upsert(sourceID: "task.\(task.id)", title: String(task.request.prefix(100)), kind: task.kind == .research ? .research : .text, content: task.fullResult, ext: "md")
    }
    @discardableResult func importDocument(_ url: URL) async throws -> CompanionDocument {
        let document = try await Task.detached(priority: .userInitiated) { try CompanionDocument.read(url) }.value
        saveDocument(document)
        return document
    }
    func saveDocument(_ document: CompanionDocument) {
        upsert(sourceID: "document.\(UUID())", title: document.name, kind: .document, content: document.text, ext: "txt", original: document.originalData, originalExtension: document.originalExtension)
    }
    private func upsert(sourceID: String, title: String, kind: CompanionArtifact.Kind, content: String, ext: String, diagram: CanvasDiagram? = nil, elements: [CanvasElement]? = nil, original: Data? = nil, originalExtension: String? = nil) {
        guard validStorage, content.utf8.count <= 500_000, title.count <= 160 else { return }
        let existing = items.first { $0.sourceID == sourceID }
        if let existing, existing.content == content, existing.title == title, existing.diagram == diagram, existing.elements == elements { return }
        let id = existing?.id ?? UUID()
        let record = CompanionArtifact(id: id, sourceID: sourceID, title: title, kind: kind, content: content,
            filename: "\(id).\(ext)", date: Date(), diagram: diagram, elements: elements, originalFilename: originalExtension.map { "\(id).\($0)" })
        var next = items.filter { $0.id != id }; next.insert(record, at: 0)
        guard Self.valid(next) else { issue = "A biblioteca está cheia. Os resultados existentes foram preservados."; return }
        do {
            if let directory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let data = try JSONEncoder().encode(next)
                guard data.count <= 4_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
                if let original, let filename = record.originalFilename { try original.write(to: directory.appendingPathComponent(filename), options: .atomic) }
                if record.originalFilename != record.filename { try Data(content.utf8).write(to: directory.appendingPathComponent(record.filename), options: .atomic) }
                try data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
            }
            items = next
        } catch { issue = "Não foi possível salvar o resultado: \(error.localizedDescription)" }
    }
    func url(for item: CompanionArtifact) -> URL? {
        guard items.contains(where: { $0.id == item.id && $0.filename == item.filename }), let directory,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.originalFilename ?? item.filename).path) else { return nil }
        return directory.appendingPathComponent(item.originalFilename ?? item.filename)
    }
    func export(_ item: CompanionArtifact) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = Self.safeTitle(item.originalFilename != nil ? (item.title as NSString).deletingPathExtension : item.title) + "." + ((item.originalFilename ?? item.filename) as NSString).pathExtension
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if item.originalFilename != nil, let source = url(for: item) { try Data(contentsOf: source).write(to: destination, options: .atomic) }
            else { try Data(item.content.utf8).write(to: destination, options: .atomic) }
        }
        catch { issue = error.localizedDescription }
    }
    static func safeTitle(_ title: String) -> String {
        let clean = title.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted).joined(separator: " ")
        return String(clean.trimmingCharacters(in: .whitespaces).prefix(80)).isEmpty ? "Sieg" : String(clean.prefix(80))
    }
    private static func valid(_ values: [CompanionArtifact]) -> Bool {
        let outputTypes = ["txt", "md", "svg", "swift", "py", "js", "ts", "json", "html", "css", "c", "cpp", "java"]
        let inputTypes = ["pdf", "txt", "md", "csv", "json", "swift", "py", "js", "ts", "html", "css", "xml", "yaml", "yml", "log"]
        return values.count <= 100 && Set(values.map(\.id)).count == values.count && values.allSatisfy { item in
            let ext = (item.filename as NSString).pathExtension
            let originalValid = item.originalFilename.map { name in
                let type = (name as NSString).pathExtension
                return name == item.id.uuidString + "." + type && inputTypes.contains(type)
            } ?? true
            let graphValid = item.diagram.map { (try? $0.validated()) != nil } ?? true
            let vectorValid = item.elements.map { elements in
                elements.count <= 48 && elements.allSatisfy { element in
                    element.points.count <= 96 && element.text.count <= 400 && element.points.allSatisfy { point in point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y) }
                }
            } ?? true
            return originalValid && graphValid && vectorValid && item.content.utf8.count <= 500_000 && item.title.count <= 160 && !item.title.isEmpty && item.filename == item.id.uuidString + "." + ext && outputTypes.contains(ext)
        }
    }
    private static func codeExtension(_ name: String) -> String {
        ["swift": "swift", "python": "py", "javascript": "js", "typescript": "ts", "json": "json", "html": "html", "css": "css", "c": "c", "c++": "cpp", "java": "java"][name.lowercased()] ?? "txt"
    }
}

enum CanvasSVGExporter {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
    static func render(_ canvas: GeneratedCanvas) -> String {
        if let diagram = canvas.diagram { return render(diagram, title: canvas.title) }
        var result = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1200\" height=\"1000\" viewBox=\"0 0 1200 1000\"><rect width=\"1200\" height=\"1000\" fill=\"#101421\"/><text x=\"60\" y=\"60\" fill=\"white\" font-family=\"system-ui\" font-size=\"28\">\(escape(canvas.title))</text>"
        let colors: [CanvasInk: String] = [.cyan: "#7cd4ed", .purple: "#c3a3ee", .gold: "#f6d17d", .white: "#ffffff", .green: "#91d6b1", .red: "#ee8995"]
        for element in canvas.elements {
            let points = element.points.map { CGPoint(x: 100+$0.x*1000, y: 120+$0.y*800) }
            guard let first = points.first else { continue }
            let color = colors[element.ink] ?? "white"
            let style = "fill=\"\(element.filled ? color : "none")\" fill-opacity=\"0.25\" stroke=\"\(color)\" stroke-width=\"3\""
            if element.kind == .text {
                result += "<text x=\"\(first.x)\" y=\"\(first.y)\" fill=\"\(color)\" font-family=\"system-ui\" font-size=\"20\">\(escape(element.text))</text>"
            } else if element.kind == .rectangle || element.kind == .ellipse, points.count >= 2 {
                let a = points[0], b = points[1], w = abs(b.x-a.x), h = abs(b.y-a.y)
                if element.kind == .rectangle { result += "<rect x=\"\(min(a.x,b.x))\" y=\"\(min(a.y,b.y))\" width=\"\(w)\" height=\"\(h)\" \(style)/>" }
                else { result += "<ellipse cx=\"\((a.x+b.x)/2)\" cy=\"\((a.y+b.y)/2)\" rx=\"\(w/2)\" ry=\"\(h/2)\" \(style)/>" }
            } else if element.kind == .bezier, points.count >= 4 {
                result += "<path d=\"M \(first.x) \(first.y) C \(points[1].x) \(points[1].y), \(points[2].x) \(points[2].y), \(points[3].x) \(points[3].y)\" \(style)/>"
            } else {
                let tag = element.kind == .polygon ? "polygon" : "polyline"
                result += "<\(tag) points=\"\(points.map { "\($0.x),\($0.y)" }.joined(separator: " "))\" \(style)/>"
            }
        }
        return result + "</svg>"
    }
    static func render(_ diagram: CanvasDiagram, title: String) -> String {
        let layout = CanvasDiagramLayout.make(diagram, in: CGRect(x: 90, y: 130, width: 1020, height: 950))
        var result = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1200\" height=\"1200\" viewBox=\"0 0 1200 1200\"><rect width=\"1200\" height=\"1200\" rx=\"30\" fill=\"#101421\"/><text x=\"60\" y=\"65\" fill=\"white\" font-family=\"system-ui,sans-serif\" font-size=\"28\">\(escape(title))</text><defs><marker id=\"arrow\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto-start-reverse\"><path d=\"M 0 0 L 10 5 L 0 10 z\" fill=\"#8cbced\"/></marker></defs>"
        for link in layout.connections {
            if link.waypoints.isEmpty {
                result += "<path d=\"M \(link.start.x),\(link.start.y) C \(link.control1.x),\(link.control1.y) \(link.control2.x),\(link.control2.y) \(link.end.x),\(link.end.y)\" fill=\"none\" stroke=\"#8cbced\" stroke-width=\"2\" marker-end=\"url(#arrow)\"/>"
            } else {
                result += "<polyline points=\"\(link.waypoints.map { "\($0.x),\($0.y)" }.joined(separator: " "))\" fill=\"none\" stroke=\"#8cbced\" stroke-width=\"2\" marker-end=\"url(#arrow)\"/>"
            }
            result += "<text x=\"\(link.label.x)\" y=\"\(link.label.y - 6)\" text-anchor=\"middle\" fill=\"#bacde9\" font-size=\"13\">\(escape(link.link.label))</text>"
        }
        for box in layout.boxes {
            let r = box.frame
            let stroke = box.node.emphasized == true ? "#f6d17d" : box.node.kind == .decision ? "#e9b373" : "#8cbced"
            result += "<rect x=\"\(r.minX)\" y=\"\(r.minY)\" width=\"\(r.width)\" height=\"\(r.height)\" rx=\"\(box.node.kind == .terminal ? 25 : 12)\" fill=\"#242f46\" stroke=\"\(stroke)\" stroke-width=\"\(box.node.emphasized == true ? 3 : 1)\"/>"
            let titleLines = wrapped(box.node.title, width: r.width - 24, fontSize: 14)
            let detailLines = wrapped(box.node.detail, width: r.width - 24, fontSize: 11)
            let height = CGFloat(titleLines.count * 17 + detailLines.count * 13 + (detailLines.isEmpty ? 0 : 5))
            var y = r.midY - height / 2 + 13
            for (lines, font, step) in [(titleLines, 14, 17), (detailLines, 11, 13)] {
                if font == 11 && !lines.isEmpty { y += 5 }
                for line in lines {
                    result += "<text x=\"\(r.midX)\" y=\"\(y)\" text-anchor=\"middle\" fill=\"white\" font-family=\"system-ui,sans-serif\" font-size=\"\(font)\">\(escape(line))</text>"
                    y += CGFloat(step)
                }
            }
        }
        return result + "</svg>"
    }
    private static func wrapped(_ value: String, width: CGFloat, fontSize: CGFloat) -> [String] {
        guard !value.isEmpty else { return [] }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
        var lines: [String] = [], current = ""
        for character in value {
            let candidate = current + String(character)
            if character == "\n" || (candidate as NSString).size(withAttributes: attributes).width > max(20, width) {
                lines.append(current); current = ""
            }
            if character != "\n" { current.append(character) }
        }
        if !current.isEmpty { lines.append(current) }
        if lines.count > 3 { lines = Array(lines.prefix(3)); lines[2] = String(lines[2].dropLast()) + "…" }
        return lines
    }
}
