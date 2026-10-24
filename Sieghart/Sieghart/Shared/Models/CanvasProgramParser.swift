import Foundation

/// Converts a small, non-executing Python-style algorithm description into
/// native control flow. Branches and loopbacks come from syntax, not guessed
/// model coordinates or hand-authored subject templates.
enum CanvasProgramParser {
    private struct Line { let indent:Int; let text:String }
    private indirect enum Statement {
        case action([String]), branch(String,[Statement],[Statement]), loop(String,[Statement]), result(String)
    }
    private struct Reader {
        let lines:[Line]
        var index = 0
        mutating func block(at indent:Int) throws -> [Statement] {
            var result: [Statement] = []
            while index < lines.count, lines[index].indent == indent {
                let text = lines[index].text
                if text == "else:" || text.hasPrefix("elif ") { break }
                if text.hasPrefix("if "), text.hasSuffix(":") {
                    result.append(try branch(at:indent,prefix:3))
                } else if text.hasPrefix("while "), text.hasSuffix(":") {
                    index += 1
                    let body = try child(of:indent)
                    result.append(.loop(String(text.dropFirst(6).dropLast()),body))
                } else if text == "return" || text.hasPrefix("return ") {
                    result.append(.result(text)); index += 1
                } else {
                    guard !text.hasSuffix(":"), !["for ","import ","from ","class ","def ","break","continue","raise "].contains(where:{text.hasPrefix($0)}) else { throw SpatialContentError.invalidContent }
                    if case .action(let values)? = result.last, values.count < 3 {
                        result.removeLast(); result.append(.action(values+[text]))
                    } else { result.append(.action([text])) }
                    index += 1
                }
            }
            return result
        }
        private mutating func child(of indent:Int) throws -> [Statement] {
            guard index < lines.count, lines[index].indent > indent else { throw SpatialContentError.invalidContent }
            let childIndent = lines[index].indent
            let result = try block(at:childIndent)
            guard !result.isEmpty, index == lines.count || lines[index].indent <= indent else { throw SpatialContentError.invalidContent }
            return result
        }
        private mutating func branch(at indent:Int,prefix:Int) throws -> Statement {
            let text = lines[index].text
            let condition = String(text.dropFirst(prefix).dropLast())
            index += 1
            let yes = try child(of:indent)
            var no: [Statement] = []
            if index < lines.count, lines[index].indent == indent {
                if lines[index].text == "else:" { index += 1; no = try child(of:indent) }
                else if lines[index].text.hasPrefix("elif "), lines[index].text.hasSuffix(":") { no = [try branch(at:indent,prefix:5)] }
            }
            return .branch(condition,yes,no)
        }
    }
    private struct Builder {
        var nodes: [CanvasDiagram.Node] = []
        var links: [CanvasDiagram.Link] = []
        let yes:String
        let no:String
        mutating func node(_ text:String, kind:CanvasDiagram.Node.Kind) throws -> String {
            guard nodes.count < 12 else { throw SpatialContentError.invalidContent }
            let id = "n\(nodes.count+1)", parts = text.components(separatedBy:"\n")
            let title = String(parts[0].prefix(72))
            let detail = (parts[0].count > 72 ? String(parts[0].dropFirst(72))+" " : "") + parts.dropFirst().joined(separator:"; ")
            guard !title.isEmpty,detail.count <= 120 else { throw SpatialContentError.invalidContent }
            nodes.append(.init(id:id,title:title,detail:detail,kind:kind)); return id
        }
        mutating func compile(_ statements:[Statement], next:String?) throws -> String {
            var continuation = next
            for statement in statements.reversed() {
                switch statement {
                case .result(let text): continuation = try node(text,kind:.terminal)
                case .action(let values):
                    guard let target = continuation else { throw SpatialContentError.invalidContent }
                    let id = try node(values.joined(separator:"\n"),kind:.process)
                    links.append(.init(from:id,to:target,label:"")); continuation = id
                case .branch(let condition,let positive,let negative):
                    let positiveID = try compile(positive,next:continuation)
                    let negativeID: String
                    if negative.isEmpty { guard let next = continuation else { throw SpatialContentError.invalidContent }; negativeID = next }
                    else { negativeID = try compile(negative,next:continuation) }
                    let id = try node(condition+"?",kind:.decision)
                    links += [.init(from:id,to:positiveID,label:yes),.init(from:id,to:negativeID,label:no)]
                    continuation = id
                case .loop(let condition,let body):
                    guard let exit = continuation else { throw SpatialContentError.invalidContent }
                    let id = try node(condition+"?",kind:.decision)
                    let bodyID = try compile(body,next:id)
                    links += [.init(from:id,to:bodyID,label:yes),.init(from:id,to:exit,label:no)]
                    continuation = id
                }
            }
            guard let continuation else { throw SpatialContentError.invalidContent }; return continuation
        }
    }
    static func parse(_ source:String,language:String) throws -> CanvasDiagram {
        guard source.utf8.count <= 12_000 else { throw SpatialContentError.invalidContent }
        var raw = source.trimmingCharacters(in:.whitespacesAndNewlines).components(separatedBy:.newlines)
        if raw.first?.trimmingCharacters(in:.whitespaces).hasPrefix("```") == true {
            guard raw.last?.trimmingCharacters(in:.whitespacesAndNewlines) == "```" else { throw SpatialContentError.invalidContent }
            raw = Array(raw.dropFirst().dropLast())
        }
        var lines: [Line] = []
        for line in raw {
            let text = line.trimmingCharacters(in:.whitespacesAndNewlines)
            if text.isEmpty || text.hasPrefix("#") { continue }
            guard !line.contains("\t"),line.count <= 180 else { throw SpatialContentError.invalidContent }
            lines.append(.init(indent:line.prefix(while:{$0 == " "}).count,text:text))
        }
        guard lines.count <= 48 else { throw SpatialContentError.invalidContent }
        var inputs: String?
        if let first = lines.first?.text, first.hasPrefix("def ") {
            if let begin = first.firstIndex(of:"("), let end = first.lastIndex(of:")"), begin < end {
                inputs = String(first[first.index(after:begin)..<end])
            }
            lines.removeFirst()
        }
        guard let minimum = lines.map(\.indent).min(), !lines.isEmpty else { throw SpatialContentError.invalidContent }
        lines = lines.map { .init(indent:$0.indent-minimum,text:$0.text) }
        var reader = Reader(lines:lines)
        var statements = try reader.block(at:0)
        if let inputs,!inputs.isEmpty { statements.insert(.action([(language.hasPrefix("en") ? "Inputs: " : "Entradas: ")+inputs]),at:0) }
        guard reader.index == lines.count else { throw SpatialContentError.invalidContent }
        var builder = Builder(yes:language.hasPrefix("en") ? "Yes" : "Sim",no:language.hasPrefix("en") ? "No" : "Não")
        let entry = try builder.compile(statements,next:nil)
        var queue = [entry], visited: Set<String> = [], ordered: [CanvasDiagram.Node] = []
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard visited.insert(id).inserted, let node = builder.nodes.first(where:{$0.id == id}) else { continue }
            ordered.append(node); queue += builder.links.filter{$0.from == id}.map(\.to)
        }
        guard ordered.count == builder.nodes.count else { throw SpatialContentError.invalidContent }
        let graph = CanvasDiagram(arrangement:.flow,nodes:ordered,links:builder.links)
        if graph.nodes.contains(where:{$0.kind == .decision}) { return try graph.validatedControlFlow(requiresIteration:lines.contains{$0.text.hasPrefix("while ")}) }
        return try graph.validated()
    }
}
