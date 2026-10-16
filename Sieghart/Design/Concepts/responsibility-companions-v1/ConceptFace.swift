import SwiftUI

// Standalone design study. This file is not a source of the app target.
// Independent vector interpretation of the generated concept board, with matte depth.
enum StudyAvatar: String, CaseIterable, Identifiable {
    case sig, rita, ada, gantt, elinor, toni
    var id: String { rawValue }
    var name: String {
        switch self {
        case .sig: "Sig"
        case .rita: "Rita"
        case .ada: "Ada"
        case .gantt: "Gantt"
        case .elinor: "Elinor"
        case .toni: "Toni"
        }
    }
    var role: String {
        switch self {
        case .sig: "Principal"
        case .rita: "Saúde e pausas"
        case .ada: "Código e GitHub"
        case .gantt: "Agenda e rotina"
        case .elinor: "Finanças e recursos"
        case .toni: "Comunicação e e-mail"
        }
    }
    var tint: Color {
        switch self {
        case .sig: Color(red: 0.55, green: 0.81, blue: 0.68)
        case .rita: Color(red: 0.64, green: 0.76, blue: 0.58)
        case .ada: Color(red: 1, green: 0.78, blue: 0.35)
        case .gantt: Color(red: 0.74, green: 0.72, blue: 0.94)
        case .elinor: Color(red: 0.93, green: 0.66, blue: 0.66)
        case .toni: Color(red: 1, green: 0.63, blue: 0.52)
        }
    }
}

struct StudyFace: View, Animatable {
    var avatar: StudyAvatar
    var openness: CGFloat
    var joy: CGFloat
    var tilt: CGFloat
    var gaze: CGSize
    var wink: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    nonisolated var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(AnimatablePair(openness, joy), AnimatablePair(tilt, AnimatablePair(gaze.width, gaze.height))) }
        set { openness = newValue.first.first; joy = newValue.first.second; tilt = newValue.second.first; gaze = CGSize(width: newValue.second.second.first, height: newValue.second.second.second) }
    }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 96, y: size.height / 96)
            drawBody(in: context)
            let eyeColor: Color = avatar == .gantt ? Color(red: 0.55, green: 0.95, blue: 0.82) : avatar == .sig ? .white : Color(red: 0.10, green: 0.12, blue: 0.12)
            let pixel = avatar == .ada
            let eyeWidth: CGFloat = pixel ? 12 : 11
            let eyeHeight: CGFloat = pixel ? 12 : 22
            let centers: [CGFloat] = avatar == .toni ? [36, 59] : [34, 62]
            for (index, centerX) in centers.enumerated() {
                let width = eyeWidth + joy * 5
                let height = max(1.8, eyeHeight * openness * (index == 1 ? 1 - wink : 1))
                let frame = CGRect(x: centerX - width / 2 + gaze.width, y: 48 - height / 2 + gaze.height, width: width, height: height)
                var eye = context
                eye.translateBy(x: frame.midX, y: frame.midY)
                eye.rotate(by: .degrees(Double(tilt) * (index == 0 ? 1 : -1)))
                eye.translateBy(x: -frame.midX, y: -frame.midY)
                let lightEyes = avatar == .gantt || avatar == .sig
                let bottom: Color = avatar == .gantt ? Color(red: 0.43, green: 0.85, blue: 0.73) : lightEyes ? Color(white: 0.91) : Color(red: 0.06, green: 0.08, blue: 0.08)
                eye.fill(Self.eyePath(in: frame, joy: joy, pixel: pixel), with: .linearGradient(Gradient(colors: [eyeColor, bottom]), startPoint: CGPoint(x: frame.minX, y: frame.minY), endPoint: CGPoint(x: frame.maxX, y: frame.maxY)))
            }
            drawAccessory(in: context)
        }
    }

    // Draw light on the native paths at the final display size. Clipped edge
    // shading gives a matte rounded surface without enlarging a small canvas.
    private func fillShell(_ path: Path, in context: GraphicsContext, colors: [Color], shadow: CGFloat = 1.2) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.10), radius: shadow, x: 0.4, y: 1.4))
            layer.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 20 + gaze.width, y: 15 + gaze.height), endPoint: CGPoint(x: 76, y: 85)))
        }
        context.fill(path, with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.06), .clear]), center: CGPoint(x: 29 + gaze.width * 0.5, y: 21 + gaze.height * 0.5), startRadius: 0, endRadius: 67))
        var edge = context
        edge.clip(to: path)
        edge.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.25), .clear, .black.opacity(0.18)]), startPoint: CGPoint(x: 22, y: 15), endPoint: CGPoint(x: 70, y: 83)), lineWidth: 1.3)
        edge.fill(path, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.06), location: 1)]), startPoint: CGPoint(x: 48, y: 15), endPoint: CGPoint(x: 48, y: 81)))
    }

    private func drawBody(in context: GraphicsContext) {
        switch avatar {
        case .gantt:
            let shell = Path(roundedRect: CGRect(x: 12, y: 15, width: 72, height: 66), cornerRadius: 21)
            fillShell(shell, in: context, colors: [Color(red: 0.80, green: 0.79, blue: 0.97), Color(red: 0.65, green: 0.63, blue: 0.86)])
            let visor = Path(roundedRect: CGRect(x: 20, y: 23, width: 56, height: 50), cornerRadius: 17)
            context.fill(visor, with: .linearGradient(Gradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.10), Color(red: 0.11, green: 0.13, blue: 0.13), Color(red: 0.045, green: 0.06, blue: 0.06)]), startPoint: CGPoint(x: 28, y: 25), endPoint: CGPoint(x: 68, y: 71)))
            context.stroke(visor, with: .linearGradient(Gradient(colors: [.black.opacity(0.32), .white.opacity(0.18)]), startPoint: CGPoint(x: 48, y: 23), endPoint: CGPoint(x: 48, y: 73)), lineWidth: 0.8)
        case .ada:
            let points: [CGPoint] = [(30,14),(66,14),(66,22),(77,22),(77,33),(84,33),(84,66),(77,66),(77,78),(19,78),(19,66),(12,66),(12,33),(19,33),(19,22),(30,22)].map { CGPoint(x: $0.0, y: $0.1) }
            let shell = Self.roundedPolygon(points, radius: 1.5)
            fillShell(shell, in: context, colors: [Color(red: 1, green: 0.82, blue: 0.43), Color(red: 0.99, green: 0.74, blue: 0.29)], shadow: 0.65)
        case .rita, .elinor:
            var pebble = Path()
            pebble.move(to: CGPoint(x: 10, y: 55))
            pebble.addCurve(to: CGPoint(x: 48, y: 16), control1: CGPoint(x: 10, y: 33), control2: CGPoint(x: 28, y: 16))
            pebble.addCurve(to: CGPoint(x: 86, y: 55), control1: CGPoint(x: 68, y: 16), control2: CGPoint(x: 86, y: 33))
            pebble.addCurve(to: CGPoint(x: 48, y: 76), control1: CGPoint(x: 86, y: 73), control2: CGPoint(x: 70, y: 76))
            pebble.addCurve(to: CGPoint(x: 10, y: 55), control1: CGPoint(x: 26, y: 76), control2: CGPoint(x: 10, y: 73))
            let colors: [Color] = avatar == .rita
                ? [Color(red: 0.73, green: 0.83, blue: 0.67), Color(red: 0.52, green: 0.66, blue: 0.46)]
                : [Color(red: 0.98, green: 0.77, blue: 0.76), Color(red: 0.84, green: 0.55, blue: 0.55)]
            fillShell(pebble, in: context, colors: colors)
        case .toni:
            var folded = Path()
            folded.move(to: CGPoint(x: 44, y: 13))
            folded.addCurve(to: CGPoint(x: 55, y: 16), control1: CGPoint(x: 49, y: 12), control2: CGPoint(x: 52, y: 13))
            folded.addLine(to: CGPoint(x: 83, y: 42))
            folded.addQuadCurve(to: CGPoint(x: 83, y: 54), control: CGPoint(x: 90, y: 48))
            folded.addLine(to: CGPoint(x: 53, y: 81))
            folded.addQuadCurve(to: CGPoint(x: 38, y: 81), control: CGPoint(x: 46, y: 88))
            folded.addLine(to: CGPoint(x: 13, y: 54))
            folded.addQuadCurve(to: CGPoint(x: 13, y: 42), control: CGPoint(x: 7, y: 48))
            folded.addLine(to: CGPoint(x: 38, y: 17)); folded.addQuadCurve(to: CGPoint(x: 44, y: 13), control: CGPoint(x: 41, y: 13))
            folded.closeSubpath()
            fillShell(folded, in: context, colors: [Color(red: 1, green: 0.65, blue: 0.56), Color(red: 1, green: 0.54, blue: 0.46)])
            var front = Path()
            front.move(to: CGPoint(x: 44, y: 13))
            front.addCurve(to: CGPoint(x: 50, y: 18), control1: CGPoint(x: 47, y: 13), control2: CGPoint(x: 49, y: 15))
            front.addCurve(to: CGPoint(x: 70, y: 43), control1: CGPoint(x: 56, y: 29), control2: CGPoint(x: 63, y: 35))
            front.addCurve(to: CGPoint(x: 70, y: 57), control1: CGPoint(x: 75, y: 49), control2: CGPoint(x: 75, y: 52))
            front.addLine(to: CGPoint(x: 51, y: 80))
            front.addQuadCurve(to: CGPoint(x: 38, y: 81), control: CGPoint(x: 44, y: 88))
            front.addLine(to: CGPoint(x: 13, y: 54))
            front.addQuadCurve(to: CGPoint(x: 13, y: 42), control: CGPoint(x: 7, y: 48))
            front.addLine(to: CGPoint(x: 38, y: 17)); front.addQuadCurve(to: CGPoint(x: 44, y: 13), control: CGPoint(x: 41, y: 13))
            front.closeSubpath()
            fillShell(front, in: context, colors: [Color(red: 1, green: 0.97, blue: 0.90), Color(red: 0.97, green: 0.88, blue: 0.76)], shadow: 0.8)
            var foldEdge = Path()
            foldEdge.move(to: CGPoint(x: 50, y: 18))
            foldEdge.addCurve(to: CGPoint(x: 70, y: 43), control1: CGPoint(x: 56, y: 29), control2: CGPoint(x: 63, y: 35))
            foldEdge.addCurve(to: CGPoint(x: 70, y: 57), control1: CGPoint(x: 75, y: 49), control2: CGPoint(x: 75, y: 52))
            context.stroke(foldEdge, with: .linearGradient(Gradient(colors: [.white.opacity(0.28), Color(red: 0.67, green: 0.37, blue: 0.29).opacity(0.13)]), startPoint: CGPoint(x: 50, y: 18), endPoint: CGPoint(x: 70, y: 57)), lineWidth: 0.75)
        case .sig:
            let shell = Path(roundedRect: CGRect(x: 8, y: 25, width: 80, height: 46), cornerRadius: 20)
            fillShell(shell, in: context, colors: [Color(red: 0.16, green: 0.18, blue: 0.18), Color(red: 0.065, green: 0.08, blue: 0.08)])
        }
    }

    private func drawAccessory(in context: GraphicsContext) {
        let cream = Color(red: 1, green: 0.95, blue: 0.83)
        let coral = Color(red: 0.93, green: 0.43, blue: 0.34)
        let teal = Color(red: 0.16, green: 0.65, blue: 0.61)
        switch avatar {
        case .sig:
            let points = [CGPoint(x: 75, y: 21), CGPoint(x: 83, y: 29), CGPoint(x: 75, y: 37), CGPoint(x: 67, y: 29)]
            let pin = Self.roundedPolygon(points, radius: 1.2)
            fillShell(pin, in: context, colors: [Color(red: 0.79, green: 0.96, blue: 0.75), Color(red: 0.44, green: 0.70, blue: 0.46)], shadow: 1)
            var facet = Path(); facet.move(to: points[0]); facet.addLine(to: CGPoint(x:75,y:29)); facet.addLine(to: points[1]); facet.closeSubpath()
            context.fill(facet, with: .color(.white.opacity(0.28)))
        case .rita:
            var tube = Path(); tube.move(to: CGPoint(x: 72, y: 19))
            tube.addCurve(to: CGPoint(x: 83, y: 19), control1: CGPoint(x: 66, y: 33), control2: CGPoint(x: 89, y: 32))
            tube.move(to: CGPoint(x: 77.5, y: 28)); tube.addCurve(to: CGPoint(x: 84, y: 37), control1: CGPoint(x: 74, y: 37), control2: CGPoint(x: 80, y: 41))
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.16), radius: 1.2, y: 1.2))
                layer.stroke(tube, with: .color(cream), style: StrokeStyle(lineWidth: 2.9, lineCap: .round))
            }
            fillShell(Path(ellipseIn: CGRect(x:81,y:31,width:7,height:7)), in: context, colors: [coral.opacity(0.9),coral], shadow:0.4)
        case .ada:
            var brackets = Path(); brackets.move(to: CGPoint(x: 72,y:22)); brackets.addLine(to: CGPoint(x:67,y:27)); brackets.addLine(to: CGPoint(x:72,y:32))
            brackets.move(to: CGPoint(x: 79,y:22)); brackets.addLine(to: CGPoint(x:84,y:27)); brackets.addLine(to: CGPoint(x:79,y:32))
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.15), radius: 0.8, y: 1))
                layer.stroke(brackets, with: .color(teal), style: StrokeStyle(lineWidth: 3.3, lineCap: .square, lineJoin: .miter))
            }
        case .gantt:
            let pin = Path(roundedRect: CGRect(x: 70, y: 16, width: 17, height: 16), cornerRadius: 4)
            fillShell(pin, in: context, colors: [cream,Color(red:0.91,green:0.82,blue:0.67)], shadow:1)
            var binding = Path(); binding.move(to: CGPoint(x:75,y:14));binding.addLine(to:CGPoint(x:75,y:18));binding.move(to:CGPoint(x:82,y:14));binding.addLine(to:CGPoint(x:82,y:18))
            context.stroke(binding, with:.color(cream),style:StrokeStyle(lineWidth:2.1,lineCap:.round))
            context.fill(Path(roundedRect:CGRect(x:74,y:23,width:9,height:2.8),cornerRadius:1.4),with:.color(coral))
        case .elinor:
            let gold = Color(red:0.86,green:0.63,blue:0.27)
            fillShell(Path(ellipseIn:CGRect(x:71,y:20,width:16,height:16)),in:context,colors:[Color(red:1,green:0.83,blue:0.44),gold],shadow:0.8)
            context.stroke(Path(ellipseIn:CGRect(x:73,y:22,width:12,height:12)),with:.color(cream.opacity(0.8)),lineWidth:0.9)
            var line=Path();line.move(to:CGPoint(x:76,y:24));line.addLine(to:CGPoint(x:82,y:31))
            context.stroke(line,with:.color(gold.opacity(0.8)),style:StrokeStyle(lineWidth:1.6,lineCap:.round))
        case .toni:
            let nib=Self.roundedPolygon([CGPoint(x:73,y:22),CGPoint(x:80,y:33),CGPoint(x:76,y:40),CGPoint(x:70,y:40),CGPoint(x:67,y:33)],radius:1.1)
            fillShell(nib,in:context,colors:[Color(red:0.83,green:0.78,blue:1),Color(red:0.58,green:0.48,blue:0.83)],shadow:0.7)
            var slit=Path();slit.move(to:CGPoint(x:73,y:24));slit.addLine(to:CGPoint(x:73,y:33))
            context.stroke(slit,with:.color(Color(red:0.39,green:0.30,blue:0.62)),lineWidth:0.9)
            context.fill(Path(ellipseIn:CGRect(x:71.4,y:31.4,width:3.2,height:3.2)),with:.color(coral))
        }
    }

    private static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        for index in points.indices {
            let point = points[index], previous = points[(index + points.count - 1) % points.count], next = points[(index + 1) % points.count]
            func approach(_ neighbor: CGPoint) -> CGPoint {
                let x = neighbor.x - point.x, y = neighbor.y - point.y, distance = sqrt(x * x + y * y)
                let fraction = min(radius / distance, 0.5)
                return CGPoint(x: point.x + x * fraction, y: point.y + y * fraction)
            }
            let entry = approach(previous), exit = approach(next)
            if index == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
            path.addQuadCurve(to: exit, control: point)
        }
        path.closeSubpath(); return path
    }

    // Four cubic segments keep one topology from a dot to a smiling arch.
    private static func eyePath(in rect: CGRect, joy: CGFloat, pixel: Bool) -> Path {
        let j = min(1, max(0, joy)), w = rect.width, h = rect.height
        if pixel {
            let step = w / 4
            var p = Path()
            if j < 0.45 { return Path(CGRect(x: rect.minX, y: rect.minY, width: w, height: h)) }
            for column in 0..<4 {
                let raised = column == 1 || column == 2
                p.addRect(CGRect(x: rect.minX + CGFloat(column) * step, y: rect.minY + (raised ? 0 : h * 0.3), width: step + 0.05, height: max(2, h * 0.28)))
            }
            return p
        }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        func mix(_ normal: (CGFloat, CGFloat), _ happy: (CGFloat, CGFloat)) -> CGPoint {
            point(normal.0 + (happy.0 - normal.0) * j, normal.1 + (happy.1 - normal.1) * j)
        }
        let k: CGFloat = pixel ? 0 : 0.224
        var p = Path()
        p.move(to: mix((0,0.5),(0,0.8)))
        p.addCurve(to: mix((0.5,0),(0.5,0.15)), control1: mix((0,k),(0,0.48)), control2: mix((k,0),(0.22,0.15)))
        p.addCurve(to: mix((1,0.5),(1,0.8)), control1: mix((1-k,0),(0.78,0.15)), control2: mix((1,k),(1,0.48)))
        p.addCurve(to: mix((0.5,1),(0.5,0.4)), control1: mix((1,1-k),(1,0.98)), control2: mix((1-k,1),(0.80,0.4)))
        p.addCurve(to: mix((0,0.5),(0,0.8)), control1: mix((k,1),(0.20,0.4)), control2: mix((0,1-k),(0,0.98)))
        p.closeSubpath(); return p
    }
}

