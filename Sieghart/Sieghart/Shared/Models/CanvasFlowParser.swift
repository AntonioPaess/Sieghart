import Foundation

/// Parses a bounded, inert flowchart subset. The source is data: no JavaScript,
/// HTML renderer, Mermaid runtime, click callbacks or code execution is used.
enum CanvasFlowParser {
    static func parse(_ source: String) throws -> CanvasDiagram {
        guard source.utf8.count <= 14_000 else { throw SpatialContentError.invalidContent }
        var value = source.trimmingCharacters(in:.whitespacesAndNewlines)
        if value.hasPrefix("```") {
            let lines = value.components(separatedBy:.newlines)
            guard lines.count >= 3, lines.last?.trimmingCharacters(in:.whitespaces) == "```" else { throw SpatialContentError.invalidContent }
            value = lines.dropFirst().dropLast().joined(separator:"\n")
        }
        var lines = value.components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty}
        guard let header = lines.first, ["flowchart TD","flowchart TB","flowchart LR","graph TD","graph LR"].contains(header) else { throw SpatialContentError.invalidContent }
        lines.removeFirst()
        let declarations: [(String,CanvasDiagram.Node.Kind)] = [
            (#"([A-Za-z][A-Za-z0-9_]{0,31})\s*\(\[\"([^\"\n]{1,180})\"\]\)"#,.terminal),
            (#"([A-Za-z][A-Za-z0-9_]{0,31})\s*\{\"([^\"\n]{1,180})\"\}"#,.decision),
            (#"([A-Za-z][A-Za-z0-9_]{0,31})\s*\[\"([^\"\n]{1,180})\"\]"#,.process)
        ]
        var nodes: [CanvasDiagram.Node] = [], links: [CanvasDiagram.Link] = []
        for raw in lines {
            if raw.hasPrefix("%%") { continue }
            var line = raw.hasSuffix(";") ? String(raw.dropLast()) : raw
            var declarationsOnLine: [(NSTextCheckingResult,CanvasDiagram.Node.Kind)] = []
            for (pattern,kind) in declarations {
                let regex = try NSRegularExpression(pattern:pattern)
                declarationsOnLine += regex.matches(in:line,range:NSRange(line.startIndex...,in:line)).map { ($0,kind) }
            }
            var replacements: [(NSRange,String)] = []
            for (match,kind) in declarationsOnLine.sorted(by:{$0.0.range.location < $1.0.range.location}) {
                    guard let idRange = Range(match.range(at:1),in:line), let labelRange = Range(match.range(at:2),in:line) else { throw SpatialContentError.invalidContent }
                    let id = String(line[idRange]), label = String(line[labelRange]).replacingOccurrences(of:"<br/>",with:"\\n").replacingOccurrences(of:"<br>",with:"\\n")
                    let parts = label.components(separatedBy:"\\n")
                    let node = CanvasDiagram.Node(id:id,title:parts[0],detail:parts.dropFirst().joined(separator:" "),kind:kind)
                    if let previous = nodes.first(where:{$0.id == id}) { guard previous == node else { throw SpatialContentError.invalidContent } }
                    else { nodes.append(node) }
                    replacements.append((match.range,id))
            }
            for (range,id) in replacements.reversed() {
                    guard let range = Range(range,in:line) else { throw SpatialContentError.invalidContent }
                    line.replaceSubrange(range,with:id)
            }
            if line.range(of:#"^[A-Za-z][A-Za-z0-9_]{0,31}$"#,options:.regularExpression) != nil { continue }
            let pattern = #"^([A-Za-z][A-Za-z0-9_]{0,31})\s*-->\s*(?:\|([^|\n]{1,40})\|\s*)?([A-Za-z][A-Za-z0-9_]{0,31})$"#
            let regex = try NSRegularExpression(pattern:pattern)
            guard let match = regex.firstMatch(in:line,range:NSRange(line.startIndex...,in:line)),
                  let from = Range(match.range(at:1),in:line), let to = Range(match.range(at:3),in:line) else { throw SpatialContentError.invalidContent }
            let label = Range(match.range(at:2),in:line).map { String(line[$0]) } ?? ""
            links.append(.init(from:String(line[from]),to:String(line[to]),label:label))
        }
        return try CanvasDiagram(arrangement:.flow,nodes:nodes,links:links).validated()
    }
}
