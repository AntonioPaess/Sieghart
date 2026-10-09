import SwiftUI

// Standalone design study. This file is not a source of the app target.
// The five approved silhouettes are rendered with the same native paths.
enum StudyAvatar: String, CaseIterable, Identifiable {
    case crtBuddy, arcade1984, minimalSpirit, coastBuddy, paperPal, inkBuddy
    var id: String { rawValue }
    var name: String {
        switch self {
        case .crtBuddy: "CRT Buddy"
        case .arcade1984: "Arcade 1984"
        case .minimalSpirit: "Minimal Spirit"
        case .coastBuddy: "Coast Buddy"
        case .paperPal: "Paper Pal"
        case .inkBuddy: "Ink Buddy"
        }
    }
    var tint: Color {
        switch self {
        case .crtBuddy: Color(red: 0.76, green: 0.65, blue: 0.97)
        case .arcade1984: Color(red: 1, green: 0.78, blue: 0.35)
        case .minimalSpirit: Color(red: 0.75, green: 0.72, blue: 0.90)
        case .coastBuddy: Color(red: 0.46, green: 0.72, blue: 0.61)
        case .paperPal: Color(red: 1, green: 0.63, blue: 0.52)
        case .inkBuddy: Color(red: 0.55, green: 0.62, blue: 0.61)
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
            let eyeColor: Color = avatar == .crtBuddy ? Color(red: 0.55, green: 0.95, blue: 0.82) : avatar == .inkBuddy ? .white : avatar == .minimalSpirit && colorScheme == .dark ? .white : Color(red: 0.10, green: 0.12, blue: 0.12)
            let pixel = avatar == .arcade1984
            let eyeWidth: CGFloat = pixel ? 12 : avatar == .minimalSpirit ? 14 : 11
            let eyeHeight: CGFloat = pixel ? 12 : avatar == .minimalSpirit ? 29 : 22
            let centers: [CGFloat] = avatar == .paperPal ? [36, 59] : [34, 62]
            for (index, centerX) in centers.enumerated() {
                let width = eyeWidth + joy * 5
                let height = max(1.8, eyeHeight * openness * (avatar == .coastBuddy ? 0.66 : 1) * (index == 1 ? 1 - wink : 1))
                let frame = CGRect(x: centerX - width / 2 + gaze.width, y: 48 - height / 2 + gaze.height, width: width, height: height)
                var eye = context
                eye.translateBy(x: frame.midX, y: frame.midY)
                eye.rotate(by: .degrees(Double(tilt) * (index == 0 ? 1 : -1)))
                eye.translateBy(x: -frame.midX, y: -frame.midY)
                if avatar == .coastBuddy && joy < 0.3 && wink < 0.4 {
                    eye.clip(to: Path(CGRect(x: frame.minX - 1, y: frame.minY + height * 0.18, width: frame.width + 2, height: height)))
                }
                let lightEyes = avatar == .crtBuddy || avatar == .inkBuddy || (avatar == .minimalSpirit && colorScheme == .dark)
                let bottom: Color = avatar == .crtBuddy ? Color(red: 0.43, green: 0.85, blue: 0.73) : lightEyes ? Color(white: 0.91) : Color(red: 0.06, green: 0.08, blue: 0.08)
                eye.fill(Self.eyePath(in: frame, joy: joy, pixel: pixel), with: .linearGradient(Gradient(colors: [eyeColor, bottom]), startPoint: CGPoint(x: frame.minX, y: frame.minY), endPoint: CGPoint(x: frame.maxX, y: frame.maxY)))
            }
            if avatar == .minimalSpirit {
                var mouth = Path()
                mouth.move(to: CGPoint(x: 43 + gaze.width * 0.4, y: 70 + gaze.height * 0.4))
                mouth.addQuadCurve(to: CGPoint(x: 53 + gaze.width * 0.4, y: 70 + gaze.height * 0.4), control: CGPoint(x: 48, y: 76 + joy * 2))
                context.stroke(mouth, with: .color(eyeColor), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            }
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
        case .crtBuddy:
            let shell = Path(roundedRect: CGRect(x: 12, y: 15, width: 72, height: 66), cornerRadius: 21)
            fillShell(shell, in: context, colors: [Color(red: 0.81, green: 0.71, blue: 1), Color(red: 0.72, green: 0.59, blue: 0.92)])
            let visor = Path(roundedRect: CGRect(x: 20, y: 23, width: 56, height: 50), cornerRadius: 17)
            context.fill(visor, with: .linearGradient(Gradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.10), Color(red: 0.11, green: 0.13, blue: 0.13), Color(red: 0.045, green: 0.06, blue: 0.06)]), startPoint: CGPoint(x: 28, y: 25), endPoint: CGPoint(x: 68, y: 71)))
            context.stroke(visor, with: .linearGradient(Gradient(colors: [.black.opacity(0.32), .white.opacity(0.18)]), startPoint: CGPoint(x: 48, y: 23), endPoint: CGPoint(x: 48, y: 73)), lineWidth: 0.8)
        case .arcade1984:
            let points: [CGPoint] = [(30,14),(66,14),(66,22),(77,22),(77,33),(84,33),(84,66),(77,66),(77,78),(19,78),(19,66),(12,66),(12,33),(19,33),(19,22),(30,22)].map { CGPoint(x: $0.0, y: $0.1) }
            let shell = Self.roundedPolygon(points, radius: 1.5)
            fillShell(shell, in: context, colors: [Color(red: 1, green: 0.82, blue: 0.43), Color(red: 0.99, green: 0.74, blue: 0.29)], shadow: 0.65)
        case .minimalSpirit: break
        case .coastBuddy:
            var pebble = Path()
            pebble.move(to: CGPoint(x: 10, y: 55))
            pebble.addCurve(to: CGPoint(x: 48, y: 22), control1: CGPoint(x: 10, y: 35), control2: CGPoint(x: 28, y: 22))
            pebble.addCurve(to: CGPoint(x: 86, y: 55), control1: CGPoint(x: 68, y: 22), control2: CGPoint(x: 86, y: 35))
            pebble.addCurve(to: CGPoint(x: 48, y: 76), control1: CGPoint(x: 86, y: 73), control2: CGPoint(x: 70, y: 76))
            pebble.addCurve(to: CGPoint(x: 10, y: 55), control1: CGPoint(x: 26, y: 76), control2: CGPoint(x: 10, y: 73))
            fillShell(pebble, in: context, colors: [Color(red: 0.57, green: 0.87, blue: 0.81), Color(red: 0.40, green: 0.75, blue: 0.67)])
            var curl = Path(); curl.move(to: CGPoint(x: 42, y: 19))
            curl.addCurve(to: CGPoint(x: 62, y: 10), control1: CGPoint(x: 53, y: 17), control2: CGPoint(x: 59, y: 18))
            context.stroke(curl, with: .linearGradient(Gradient(colors: [Color(red: 0.28, green: 0.72, blue: 0.63), Color(red: 0.19, green: 0.64, blue: 0.55)]), startPoint: CGPoint(x: 42, y: 19), endPoint: CGPoint(x: 62, y: 10)), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
        case .paperPal:
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
        case .inkBuddy:
            let shell = Path(roundedRect: CGRect(x: 8, y: 25, width: 80, height: 46), cornerRadius: 20)
            fillShell(shell, in: context, colors: [Color(red: 0.16, green: 0.18, blue: 0.18), Color(red: 0.065, green: 0.08, blue: 0.08)])
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

