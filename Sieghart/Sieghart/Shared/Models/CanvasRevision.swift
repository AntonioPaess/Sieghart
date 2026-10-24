import Foundation
import CoreGraphics

enum CanvasRevision: Equatable, Sendable {
    case rename(String, String)
    case highlight(String)
    case move(String, Double, Double)

    static func parse(_ request: String) -> Self? {
        let text = SearchVoiceParser.requestText(request).trimmingCharacters(in: .whitespacesAndNewlines)
        func groups(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
        if let values = groups(#"^(?:troque|troca|renomeie|renomeia|mude|muda|rename|change)\s+(?:(?:a legenda|o texto|o nome|a etapa|the label|the node)\s+)?["“'](.{1,72}?)["”']\s+(?:por|para|to)\s+["“'](.{1,72}?)["”'][.!]?$"#) { return .rename(values[0], values[1]) }
        if let values = groups(#"^(?:destaque|destaca|highlight)\s+(?:(?:a etapa|o bloco|the node)\s+)?["“'](.{1,72}?)["”'][.!]?$"#) { return .highlight(values[0]) }
        if let values = groups(#"^(?:mova|move|mover)\s+["“'](.{1,72}?)["”']\s+(?:para\s+(?:a |o )?|to the\s+)(direita|esquerda|cima|baixo|right|left|top|bottom)[.!]?$"#) {
            let word = values[1].lowercased()
            return .move(values[0], ["direita", "right"].contains(word) ? 0.12 : ["esquerda", "left"].contains(word) ? -0.12 : 0,
                ["baixo", "bottom"].contains(word) ? 0.09 : ["cima", "top"].contains(word) ? -0.09 : 0)
        }
        return nil
    }
    func applying(to canvas: GeneratedCanvas) throws -> GeneratedCanvas {
        var updated = canvas
        let target: String
        switch self { case .rename(let name, _), .highlight(let name), .move(let name, _, _): target = name }
        func matches(_ value: String) -> Bool { value.folding(options: [.caseInsensitive,.diacriticInsensitive], locale: .init(identifier: "en_US")) == target.folding(options: [.caseInsensitive,.diacriticInsensitive], locale: .init(identifier: "en_US")) }
        if let graph = canvas.diagram {
            let matching = graph.nodes.indices.filter { matches(graph.nodes[$0].title) }
            guard matching.count == 1, let index = matching.first else { throw CanvasRevisionError.ambiguousTarget }
            var nodes = graph.nodes
            switch self {
            case .rename(_, let title): nodes[index].title = title
            case .highlight: nodes[index].emphasized = true
            case .move(_, let x, let y):
                let previous = nodes[index].offset ?? .init(x: 0, y: 0)
                nodes[index].offset = .init(x: previous.x+x, y: previous.y+y)
            }
            let diagram = try CanvasDiagram(arrangement: graph.arrangement, nodes: nodes, links: graph.links).validated()
            if case .move = self {
                let layout = CanvasDiagramLayout.make(diagram, in: .init(x: 80, y: 80, width: 1100, height: 1100))
                guard layout.boxes.allSatisfy({ a in !layout.boxes.contains { b in a.node.id != b.node.id && a.frame.intersects(b.frame) } }) else { throw CanvasRevisionError.overlap }
            }
            updated.diagram = diagram
        } else {
            let matching = canvas.elements.indices.filter { canvas.elements[$0].kind == .text && matches(canvas.elements[$0].text) }
            guard matching.count == 1, let index = matching.first else { throw CanvasRevisionError.ambiguousTarget }
            switch self {
            case .rename(_, let title): updated.elements[index].text = title
            case .highlight: updated.elements[index].ink = .gold
            case .move(_, let x, let y): updated.elements[index].points = updated.elements[index].points.map { .init(x: $0.x+x, y: $0.y+y) }
            }
        }
        return try updated.validated()
    }
}

enum CanvasRevisionError: LocalizedError {
    case ambiguousTarget, overlap
    var errorDescription: String? {
        switch self {
        case .ambiguousTarget: "Não encontrei uma única legenda com esse nome no desenho. Use o nome exato entre aspas."
        case .overlap: "Essa posição sobreporia outro bloco. O desenho foi preservado; escolha outra direção."
        }
    }
}
