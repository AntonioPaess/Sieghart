import Foundation
import CoreGraphics

struct CanvasDiagram: Equatable, Sendable, Codable {
    enum Arrangement: String, Codable, Sendable { case flow, cycle, hierarchy }
    struct Node: Identifiable, Equatable, Sendable, Codable {
        enum Kind: String, Codable, Sendable { case process, decision, terminal, note }
        let id: String
        var title: String
        let detail: String
        let kind: Kind
        var emphasized: Bool? = nil
        var offset: CanvasPoint? = nil
    }
    struct Link: Equatable, Sendable, Codable {
        let from: String
        let to: String
        let label: String
    }
    let arrangement: Arrangement
    let nodes: [Node]
    let links: [Link]

    func validated() throws -> Self {
        let ids = Set(nodes.map(\.id))
        guard (2...12).contains(nodes.count), ids.count == nodes.count,
              (1...20).contains(links.count),
              nodes.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 32 && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty && $0.title.count <= 72 && $0.detail.count <= 120 }),
              nodes.allSatisfy({ node in node.offset.map { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 0.5 && abs($0.y) <= 0.5 } ?? true }),
              links.allSatisfy({ ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to && $0.label.count <= 40 })
        else { throw SpatialContentError.invalidContent }
        guard Set(links.map { $0.from + "\u{0}" + $0.to }).count == links.count else { throw SpatialContentError.invalidContent }
        for node in nodes where node.kind == .decision {
            let outcomes = links.filter { $0.from == node.id }
            guard outcomes.count >= 2, outcomes.allSatisfy({ !$0.label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }),
                  Set(outcomes.map { $0.label.lowercased() }).count == outcomes.count else { throw SpatialContentError.invalidContent }
        }
        // Orphan blocks and invented destinations make an explanation misleading.
        var connected: Set<String> = [nodes[0].id]
        for _ in nodes.indices {
            for link in links where connected.contains(link.from) || connected.contains(link.to) {
                connected.insert(link.from); connected.insert(link.to)
            }
        }
        guard connected == ids else { throw SpatialContentError.invalidContent }
        if arrangement == .cycle {
            guard nodes.count <= 8 else { throw SpatialContentError.invalidContent }
            let placeholders: Set<String> = ["repeticao", "repetir", "repeat", "repetition", "ciclo", "cycle", "inicio", "fim", "start", "end", "restart", "recomeco"]
            guard !nodes.contains(where: { placeholders.contains($0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US")).trimmingCharacters(in: .whitespacesAndNewlines)) }) else { throw SpatialContentError.invalidContent }
            guard nodes.allSatisfy({ node in links.filter { $0.from == node.id }.count == 1 && links.filter { $0.to == node.id }.count == 1 }) else { throw SpatialContentError.invalidContent }
        }
        if arrangement == .hierarchy {
            guard links.count == nodes.count-1, nodes.filter({ node in !links.contains { $0.to == node.id } }).count == 1,
                  nodes.allSatisfy({ node in links.filter { $0.to == node.id }.count <= 1 }) else { throw SpatialContentError.invalidContent }
        }
        return self
    }

    var textRepresentation: String {
        nodes.map { "\($0.title)\($0.detail.isEmpty ? "" : ": " + $0.detail)" }.joined(separator: "\n")
        + "\n\n" + links.map { link in
            let source = nodes.first { $0.id == link.from }?.title ?? link.from
            let target = nodes.first { $0.id == link.to }?.title ?? link.to
            return "\(source) → \(target)\(link.label.isEmpty ? "" : " · " + link.label)"
        }.joined(separator: "\n")
    }

    func validatedControlFlow(requiresIteration: Bool) throws -> Self {
        _ = try validated()
        guard arrangement == .flow, let entry = nodes.first, nodes.contains(where:{$0.kind == .decision}) else { throw SpatialContentError.invalidContent }
        let terminals = Set(nodes.filter{$0.kind == .terminal}.map(\.id))
        guard !terminals.isEmpty, !links.contains(where:{$0.to == entry.id}),
              nodes.allSatisfy({ node in
                  let outgoing = links.filter{$0.from == node.id}.count
                  if node.kind == .terminal { return outgoing == 0 }
                  return node.kind == .decision ? outgoing == 2 : outgoing == 1
              }) else { throw SpatialContentError.invalidContent }
        var reachesExit = terminals
        for _ in nodes.indices { for link in links where reachesExit.contains(link.to) { reachesExit.insert(link.from) } }
        guard reachesExit.count == nodes.count else { throw SpatialContentError.invalidContent }
        if requiresIteration {
            var pending = Set(nodes.map(\.id))
            for _ in nodes.indices {
                let ready = pending.filter { id in !links.contains { $0.to == id && pending.contains($0.from) } }
                if ready.isEmpty { break }
                pending.subtract(ready)
            }
            guard !pending.isEmpty else { throw SpatialContentError.invalidContent }
        }
        return self
    }
}

/// Layout is deterministic app code. The model supplies meaning, never screen
/// coordinates. Every node stays readable and disjoint for any accepted graph.
struct CanvasDiagramLayout {
    struct Box { let node: CanvasDiagram.Node; let frame: CGRect }
    struct Connection {
        let link: CanvasDiagram.Link
        let start: CGPoint
        let end: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let label: CGPoint
        var waypoints: [CGPoint] = []
    }
    let boxes: [Box]
    let connections: [Connection]

    static func make(_ diagram: CanvasDiagram, in bounds: CGRect) -> Self {
        guard !diagram.nodes.isEmpty else { return .init(boxes: [], connections: []) }
        let count = diagram.nodes.count
        var frames: [String: CGRect] = [:]
        if diagram.arrangement == .cycle {
            let columns = count > 4 ? 3 : 2
            let width = min(240, bounds.width / CGFloat(columns) * 0.76)
            let height = min(108, bounds.height * 0.22)
            let rx = max(0, (bounds.width - width) * 0.48)
            let ry = max(0, (bounds.height - height) * 0.48)
            for (index, node) in diagram.nodes.enumerated() {
                let angle = CGFloat(index) / CGFloat(count) * .pi * 2 - .pi / 2
                let center = CGPoint(x: bounds.midX + cos(angle) * rx, y: bounds.midY + sin(angle) * ry)
                frames[node.id] = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
            }
        } else {
            // Stable topological levels preserve the direction of a process.
            var ranks: [String: Int] = [:]
            var remaining = diagram.nodes.map(\.id)
            for _ in 0..<count {
                let ready = remaining.filter { id in diagram.links.filter { $0.to == id }.allSatisfy { ranks[$0.from] != nil } }
                if ready.isEmpty { break }
                for id in ready {
                    ranks[id] = (diagram.links.filter { $0.to == id }.compactMap { ranks[$0.from] }.max().map { $0 + 1 }) ?? 0
                }
                remaining.removeAll { ready.contains($0) }
            }
            // Feedback loops remain visible; they do not prevent layout.
            for id in remaining { ranks[id] = (ranks.values.max() ?? -1) + 1 }
            let ordered = diagram.nodes.enumerated().sorted {
                let a = ranks[$0.element.id] ?? 0, b = ranks[$1.element.id] ?? 0
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
            let maxRank = ranks.values.max() ?? 0
            if maxRank <= 3 {
                let groups = (0...maxRank).flatMap { rank -> [[CanvasDiagram.Node]] in
                    let level = ordered.filter { ranks[$0.id] == rank }
                    return stride(from: 0, to: level.count, by: 3).map { Array(level[$0..<min($0+3, level.count)]) }
                }
                let rows = max(1, groups.count)
                let slotHeight = bounds.height / CGFloat(rows)
                for row in 0..<rows {
                    let nodes = groups[row]
                    let slotWidth = bounds.width / CGFloat(max(1, nodes.count))
                    for (column, node) in nodes.enumerated() {
                        let width = min(300, slotWidth * 0.84), height = min(108, slotHeight * 0.65)
                        frames[node.id] = CGRect(x: bounds.minX + slotWidth * (CGFloat(column) + 0.5) - width / 2,
                            y: bounds.minY + slotHeight * (CGFloat(row) + 0.5) - height / 2, width: width, height: height)
                    }
                }
            } else {
                // Long chains use a readable snake instead of eight tiny cards.
                let columns = count > 8 ? 3 : 2
                let rows = Int(ceil(Double(count) / Double(columns)))
                let width = min(300, bounds.width / CGFloat(columns) * 0.78), height = min(108, bounds.height / CGFloat(rows) * 0.78)
                for (index, node) in ordered.enumerated() {
                    let row = index / columns, column = row.isMultiple(of: 2) ? index % columns : columns-1-index % columns
                    frames[node.id] = CGRect(x: bounds.minX + bounds.width / CGFloat(columns) * (CGFloat(column)+0.5) - width / 2,
                        y: bounds.minY + bounds.height / CGFloat(rows) * (CGFloat(row) + 0.5) - height / 2, width: width, height: height)
                }
            }
        }
        for node in diagram.nodes {
            if let offset = node.offset, let frame = frames[node.id] {
                let x = min(bounds.maxX-frame.width, max(bounds.minX, frame.minX + offset.x*bounds.width))
                let y = min(bounds.maxY-frame.height, max(bounds.minY, frame.minY + offset.y*bounds.height))
                frames[node.id] = CGRect(x: x, y: y, width: frame.width, height: frame.height)
            }
        }
        let boxes = diagram.nodes.compactMap { node in frames[node.id].map { Box(node: node, frame: $0) } }
        let connections = diagram.links.enumerated().compactMap { index,link -> Connection? in
            guard let a = frames[link.from], let b = frames[link.to] else { return nil }
            let horizontal = abs(a.midX - b.midX) > abs(a.midY - b.midY) * 1.35
            let start: CGPoint, end: CGPoint, c1: CGPoint, c2: CGPoint
            if horizontal {
                let direction: CGFloat = b.midX > a.midX ? 1 : -1
                start = .init(x: direction > 0 ? a.maxX : a.minX, y: a.midY)
                end = .init(x: direction > 0 ? b.minX : b.maxX, y: b.midY)
                let bend = max(20, abs(end.x - start.x) * 0.45)
                c1 = .init(x: start.x + direction * bend, y: start.y)
                c2 = .init(x: end.x - direction * bend, y: end.y)
            } else {
                let direction: CGFloat = b.midY > a.midY ? 1 : -1
                start = .init(x: a.midX, y: direction > 0 ? a.maxY : a.minY)
                end = .init(x: b.midX, y: direction > 0 ? b.minY : b.maxY)
                let bend = max(20, abs(end.y - start.y) * 0.45)
                c1 = .init(x: start.x, y: start.y + direction * bend)
                c2 = .init(x: end.x, y: end.y - direction * bend)
            }
            let midpoint = CGPoint(x: (start.x + 3*c1.x + 3*c2.x + end.x) / 8,
                                   y: (start.y + 3*c1.y + 3*c2.y + end.y) / 8)
            if diagram.arrangement != .cycle {
                let obstacles = frames.filter{$0.key != link.from && $0.key != link.to}.map{$0.value.insetBy(dx:-4,dy:-4)}
                let crossesCard = (1..<24).contains { sample in
                    let t = CGFloat(sample)/24, u = 1-t
                    let p = CGPoint(x:u*u*u*start.x+3*u*u*t*c1.x+3*u*t*t*c2.x+t*t*t*end.x,
                                    y:u*u*u*start.y+3*u*u*t*c1.y+3*u*t*t*c2.y+t*t*t*end.y)
                    return obstacles.contains{$0.contains(p)}
                }
                var points: [CGPoint] = []
                if b.midY < a.midY-20 {
                    let gutter = (a.midX+b.midX)/2 >= bounds.midX ? bounds.maxX+18+CGFloat(index%3)*7 : bounds.minX-18-CGFloat(index%3)*7
                    points = [.init(x:a.midX,y:a.maxY),.init(x:a.midX,y:a.maxY+12),.init(x:gutter,y:a.maxY+12),
                              .init(x:gutter,y:b.minY-12),.init(x:b.midX,y:b.minY-12),.init(x:b.midX,y:b.minY)]
                } else if crossesCard {
                    if abs(a.midY-b.midY) < 12 {
                        let lane = min(a.minY,b.minY)-12
                        points = [.init(x:a.midX,y:a.minY),.init(x:a.midX,y:lane),.init(x:b.midX,y:lane),.init(x:b.midX,y:b.minY)]
                    } else {
                        let gutter = bounds.minX-20-CGFloat(index%3)*6
                        points = [.init(x:a.midX,y:a.maxY),.init(x:a.midX,y:a.maxY+12),.init(x:gutter,y:a.maxY+12),
                                  .init(x:gutter,y:b.minY-12),.init(x:b.midX,y:b.minY-12),.init(x:b.midX,y:b.minY)]
                    }
                }
                if let first = points.first,let last = points.last,points.count > 2 {
                    return Connection(link:link,start:first,end:last,control1:points[1],control2:points[points.count-2],label:points[points.count/2],waypoints:points)
                }
            }
            return Connection(link: link, start: start, end: end, control1: c1, control2: c2, label: midpoint)
        }
        return Self(boxes: boxes, connections: connections)
    }
}
