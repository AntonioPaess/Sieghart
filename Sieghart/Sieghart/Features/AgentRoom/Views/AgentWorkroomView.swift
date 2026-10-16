import SwiftUI

// Small conversation rooms, with workers supplied by each provider's tree.
// Choosing a room opens that conversation; the plus tile creates another one.
struct AgentWorkroomView: View {
    @ObservedObject var model: AgentRoomViewModel
    var compact = false
    var onCreate: (AIProvider) -> Void
    var observesActivity = true
    @Environment(\.islandPreview) private var preview
    @Environment(\.islandReduceMotion) private var reduced
    @Environment(\.companionMotionEnabled) private var motion
    @State private var roomPage = 0
    private let pageSize = 5
    private var pageCount: Int { max(1, (model.rootSessions.count + pageSize - 1) / pageSize) }
    private var visible: [CodingSession] { Array(model.rootSessions.dropFirst(roomPage * pageSize).prefix(pageSize)) }
    private var observationIDs: [String] { visible.map(\.id) }
    private var hasWorking: Bool { visible.contains { model.workers(in: $0).contains { $0.live && $0.state == .working } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Choose a room, or start a new chat.").font(.caption).foregroundStyle(CompanionStyle.muted)
                Spacer(minLength: 0)
                if pageCount > 1 {
                    Button { roomPage = max(0, roomPage - 1) } label: { Image(systemName: "chevron.left") }.disabled(roomPage == 0)
                    Text("\(roomPage + 1) / \(pageCount)").font(.system(size: 10)).foregroundStyle(CompanionStyle.muted)
                    Button { roomPage = min(pageCount - 1, roomPage + 1) } label: { Image(systemName: "chevron.right") }.disabled(roomPage + 1 >= pageCount)
                }
            }.frame(height: 22)
            if hasWorking, !preview, !reduced, motion, observesActivity {
                // A single sparse clock for visible live workers, never idle rooms.
                TimelineView(.periodic(from: .now, by: 1)) { time in
                    rooms(typing: Int(time.date.timeIntervalSinceReferenceDate).isMultiple(of: 2))
                }
            } else { rooms(typing: false) }
            if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(1).help(notice).textSelection(.enabled) }
            if model.rootSessions.isEmpty {
                Text("Connect Codex or set up Claude to bring your conversations here.").font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.rootSessions.count) { _, _ in roomPage = min(roomPage, pageCount - 1) }
        .task(id: "\(observationIDs.joined(separator: ",")):\(observesActivity)") {
            guard !preview, observesActivity else { return }
            while !Task.isCancelled {
                await model.observeRooms(observationIDs)
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    private func rooms(typing: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(visible) { session in
                Button { Task { await model.openChat(session.id) } } label: {
                    room(session, typing: typing)
                }.buttonStyle(.plain).accessibilityLabel("Open \(session.title), \(session.provider.title)")
                    .help(session.directory)
            }
            if preview { newRoom }
            else {
                Menu {
                    ForEach(AIProvider.allCases) { provider in
                        Button("New \(provider.title) chat…") { onCreate(provider) }
                    }
                } label: { newRoom }.menuStyle(.borderlessButton)
            }
        }
    }
    private var newRoom: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 24, weight: .light)).foregroundStyle(CompanionStyle.accentInk)
            Text("New chat").font(.system(size: 11, weight: .medium)).foregroundStyle(CompanionStyle.muted)
        }.frame(maxWidth: .infinity).frame(height: compact ? 120 : 150)
            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(CompanionStyle.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 15))
            .accessibilityLabel("Create a new conversation")
    }
    private func room(_ session: CodingSession, typing: Bool) -> some View {
        let roster = model.workers(in: session)
        let children = roster.filter { $0.id != session.id }
        let active = children.filter { $0.live && $0.state == .working }.count
        return VStack(alignment: .leading, spacing: 6) {
            miniature(roster, typing: typing).frame(height: compact ? 64 : 78)
            Text(session.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                .foregroundStyle(CompanionStyle.ink)
            HStack(spacing: 4) {
                Circle().fill(active > 0 ? CompanionStyle.accent : CompanionStyle.muted).frame(width: 4, height: 4)
                Text(session.provider.title).font(.system(size: 9))
                Spacer(minLength: 0)
                Text(children.isEmpty ? "Ada" : "\(active) active · \(children.count) agents")
                    .font(.system(size: 9))
            }.foregroundStyle(CompanionStyle.muted)
        }.padding(compact ? 8 : 10).frame(maxWidth: .infinity).frame(height: compact ? 120 : 150)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(model.roomRootID == session.id ? CompanionStyle.accent.opacity(0.4) : Color.white.opacity(0.065), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 15))
    }
    private func miniature(_ roster: [CodingWorker], typing: Bool) -> some View {
        ZStack {
            AgentOfficeFloor().equatable()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 4) {
                ForEach(0..<6, id: \.self) { index in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.35)).frame(width: 38, height: 4).offset(y: -17)
                        if roster.indices.contains(index) {
                            let worker = roster[index]
                            if index == 0 { CompanionCharacter(size: 23, avatar: .ada, animates: false) }
                            else { AgentRoomFigure(identity: worker.id, pattern: (index - 1) % 5, state: worker.state).scaleEffect(0.55).frame(width: 24, height: 24) }
                            Circle().fill(worker.state.roomColor).frame(width: 3, height: 3)
                                .offset(x: 17, y: typing && worker.live && worker.state == .working ? -19 : -17)
                        } else { RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.16)).frame(width: 19, height: 13) }
                    }.frame(height: 25)
                }
            }.padding(.horizontal, 6).padding(.top, 10)
            if roster.count > 6 {
                Text("+\(roster.count - 6)").font(.system(size: 8, weight: .semibold)).padding(3)
                    .background(Color.black.opacity(0.7), in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(4)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// The selected chat keeps its live worker count visible without a full office.
struct AgentRoomActivityStrip: View {
    @ObservedObject var model: AgentRoomViewModel
    @Environment(\.islandPreview) private var preview
    private var roster: [CodingWorker] { model.roomWorkers }
    private var children: [CodingWorker] { roster.filter { $0.id != $0.rootID } }
    private var active: Int { children.filter { $0.live && $0.state == .working }.count }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2").foregroundStyle(CompanionStyle.accentInk)
            Text(children.isEmpty ? "Ada · no subagents yet" : "\(active) subagents active · \(children.count) total").font(.system(size: 10))
            Spacer(minLength: 0)
            ForEach(Array(roster.prefix(6).enumerated()), id: \.element.id) { index, worker in
                if preview { workerBadge(worker, index: index) }
                else {
                    Menu {
                        Text(worker.name + " · " + (worker.live ? worker.state.title : "Last reported: " + worker.state.title))
                        Text(worker.task)
                        if !worker.detail.isEmpty { Text(worker.detail) }
                        if let thread = worker.threadID {
                            Button("Open chat") { Task { await model.openChat(thread) } }
                        }
                    } label: { workerBadge(worker, index: index) }
                        .menuStyle(.borderlessButton).fixedSize().help(worker.name + " · " + worker.task + "\n" + worker.detail)
                }
            }
            if roster.count > 6 {
                Menu("+\(roster.count - 6)") {
                    ForEach(Array(roster.dropFirst(6))) { worker in
                        Text(worker.name + " · " + worker.state.title)
                        Text(worker.task)
                    }
                }.menuStyle(.borderlessButton).font(.system(size: 9)).foregroundStyle(CompanionStyle.muted)
            }
        }.foregroundStyle(CompanionStyle.muted).frame(height: 24)
    }
    private func workerBadge(_ worker: CodingWorker, index: Int) -> some View {
        HStack(spacing: 3) {
            if index == 0 { CompanionCharacter(size: 18, avatar: .ada, animates: false) }
            else { AgentRoomFigure(identity: worker.id, pattern: (index - 1) % 5, state: worker.state).scaleEffect(0.4).frame(width: 18, height: 18) }
            Circle().fill(worker.state.roomColor).frame(width: 4, height: 4)
        }
    }
}
private struct AgentRoomFigure: View {
    let identity: String
    let pattern: Int
    let state: CodingAgentState
    private var color: Color {
        // Stable pseudorandom pastel per runtime ID; never reroll on a redraw.
        var value = identity.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        value ^= value >> 16; value &*= 0x85ebca6b; value ^= value >> 13
        return Color(hue: Double(value % 360) / 360, saturation: 0.34, brightness: 0.87)
    }
    var body: some View {
        ZStack {
            AgentWorkerBody(pattern: pattern).fill(color).frame(width: 35, height: 30)
            HStack(spacing: 9) {
                Rectangle().fill(Color(white: 0.12)).frame(width: 4, height: state == .blocked || state == .failed ? 2 : 5)
                Rectangle().fill(Color(white: 0.12)).frame(width: 4, height: state == .blocked || state == .failed ? 2 : 5)
            }
            ornament
        }.frame(width: 43, height: 39).rotationEffect(.degrees(state == .waiting ? -5 : 0))
    }
    @ViewBuilder private var ornament: some View {
        switch pattern {
        case 0: // A small diamond, like Sig's identifying accent.
            Rectangle().fill(.white.opacity(0.86)).frame(width: 5, height: 5).rotationEffect(.degrees(45)).offset(x: 14, y: -13)
        case 1: // A code tab on the pixel silhouette.
            HStack(spacing: 1) {
                Rectangle().frame(width: 3, height: 2)
                Rectangle().frame(width: 3, height: 2)
            }.foregroundStyle(Color(white: 0.16)).offset(x: 12, y: -15)
        case 2: // A paper corner.
            TriangleCorner().fill(.white.opacity(0.72)).frame(width: 7, height: 7).offset(x: 14, y: -13)
        case 3: // A leaf on the soft drop silhouette.
            Ellipse().fill(.white.opacity(0.75)).frame(width: 5, height: 8).rotationEffect(.degrees(38)).offset(x: 9, y: -16)
        default: // A tiny clock hand on the angular silhouette.
            Circle().stroke(Color(white: 0.17), lineWidth: 1.2).frame(width: 7, height: 7).offset(x: 13, y: -13)
        }
    }
}
private struct AgentWorkerBody: Shape {
    let pattern: Int
    func path(in rect: CGRect) -> Path {
        if pattern == 0 { return Path(roundedRect: rect, cornerRadius: rect.height * 0.43) }
        if pattern == 2 { return Path(roundedRect: rect, cornerRadius: rect.height * 0.23) }
        let points: [CGPoint]
        switch pattern {
        case 1: // Pixel body.
            points = [.init(x: 0.13, y: 0), .init(x: 0.87, y: 0), .init(x: 0.87, y: 0.13), .init(x: 1, y: 0.13),
                .init(x: 1, y: 0.87), .init(x: 0.87, y: 0.87), .init(x: 0.87, y: 1), .init(x: 0.13, y: 1),
                .init(x: 0.13, y: 0.87), .init(x: 0, y: 0.87), .init(x: 0, y: 0.13), .init(x: 0.13, y: 0.13)]
        case 3: // Soft drop with a broad, stable base.
            points = [.init(x: 0.5, y: 0), .init(x: 0.76, y: 0.24), .init(x: 0.94, y: 0.52),
                .init(x: 1, y: 0.76), .init(x: 0.88, y: 0.96), .init(x: 0.12, y: 0.96),
                .init(x: 0, y: 0.76), .init(x: 0.06, y: 0.52), .init(x: 0.24, y: 0.24)]
        default: // Faceted pebble.
            points = [.init(x: 0.26, y: 0.03), .init(x: 0.74, y: 0.03), .init(x: 1, y: 0.3),
                .init(x: 0.96, y: 0.8), .init(x: 0.73, y: 0.98), .init(x: 0.27, y: 0.98),
                .init(x: 0.04, y: 0.8), .init(x: 0, y: 0.3)]
        }
        var path = Path()
        path.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        path.closeSubpath(); return path
    }
}
private struct TriangleCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct AgentOfficeFloor: View, Equatable {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.15, green: 0.17, blue: 0.18)))
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 10)), with: .color(Color(red: 0.23, green: 0.24, blue: 0.27)))
            var boards = Path()
            for row in stride(from: 10.0, through: size.height, by: 14.0) {
                boards.move(to: CGPoint(x: 0, y: row)); boards.addLine(to: CGPoint(x: size.width, y: row))
            }
            context.stroke(boards, with: .color(.white.opacity(0.03)), lineWidth: 1)
            let rug = CGRect(x: 6, y: 13, width: max(0, size.width - 12), height: max(0, size.height - 18))
            context.fill(Path(roundedRect: rug, cornerRadius: 5), with: .color(Color(red: 0.19, green: 0.22, blue: 0.25)))
        }.overlay(alignment: .topLeading) { Image(systemName: "leaf.fill").font(.system(size: 8)).foregroundStyle(Color.green.opacity(0.4)).padding(3) }
            .overlay(alignment: .topTrailing) { Image(systemName: "lamp.desk.fill").font(.system(size: 8)).foregroundStyle(Color.orange.opacity(0.45)).padding(3) }
    }
}
extension CodingAgentState {
    var roomColor: Color {
        switch self {
        case .working: CompanionStyle.accent
        case .waiting, .blocked: .orange
        case .completed: .green
        case .failed: .red
        default: CompanionStyle.muted
        }
    }
}
