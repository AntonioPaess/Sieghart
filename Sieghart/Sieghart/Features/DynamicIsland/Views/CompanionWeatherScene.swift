import AppKit
import SwiftUI

enum CompanionWeatherMood: String, CaseIterable, Sendable {
    case frozen, cold, comfortable, hot, rain, snow, storm, hail, cloudy
    static func resolve(_ weather: VoiceWeatherObservation) -> Self {
        // Preserve the actual precipitation, even below zero. Surface freezing
        // is an independent input to the character, never inferred snowfall.
        switch weather.code ?? -1 {
        case 96, 99: return .hail
        case 95, 97: return .storm
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        default:
            if weather.temperature < 0 { return .frozen }
            if weather.feelsLike < 16 { return .cold }
            if weather.feelsLike >= 28 { return .hot }
            return [2, 3, 45, 48].contains(weather.code ?? -1) ? .cloudy : .comfortable
        }
    }

    var tint: Color {
        switch self {
        case .frozen, .cold, .snow: Color(red: 0.46, green: 0.80, blue: 1)
        case .rain, .storm, .hail: Color(red: 0.48, green: 0.62, blue: 0.92)
        case .hot: Color(red: 1, green: 0.69, blue: 0.28)
        case .cloudy: Color(red: 0.65, green: 0.75, blue: 0.85)
        case .comfortable: Color(red: 0.64, green: 0.85, blue: 0.67)
        }
    }
    func caption(english: Bool) -> String {
        switch self {
        case .frozen: english ? "Even my code is freezing." : "Tá frio até no meu código."
        case .cold: english ? "Scarf ready. Where's the hot chocolate?" : "Cachecol pronto. Cadê o chocolate quente?"
        case .hot: english ? "Who turned the sun all the way up?" : "Quem colocou o sol no máximo?"
        case .rain: english ? "A tiny companion. A very big raincloud." : "Um companheiro pequeno. Uma chuva enorme."
        case .snow: english ? "Pretty snow. Very cold little face." : "Neve bonita. Carinha congelando."
        case .storm: english ? "I'll just stay right here with you." : "Vou ficar bem aqui, pertinho de você."
        case .hail: english ? "That cloud brought ice. I brought a small head." : "A nuvem trouxe gelo. Eu trouxe uma cabecinha."
        case .cloudy: english ? "A little shade. A slower kind of day." : "Uma sombra boa. Um dia mais devagar."
        case .comfortable: english ? "My kind of operating temperature." : "Minha temperatura ideal de funcionamento."
        }
    }
}

/// The result takes over the Companion surface. All values and the scene come
/// from the same observation, independent of the city or the request's wording.
struct CompanionWeatherScene: View {
    static let height: CGFloat = 292
    let observation: VoiceWeatherObservation
    let language: String
    let animates: Bool
    var stop: (() -> Void)? = nil
    var previewTime: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandPreview) private var preview
    @Environment(\.islandReduceMotion) private var islandReduceMotion
    @Environment(\.companionMotionEnabled) private var motionEnabled
    @State private var visible = false
    @State private var presented = false
    @State private var clock = WeatherPanelClock()
    private var en: Bool { language.hasPrefix("en") }
    private var mood: CompanionWeatherMood { .resolve(observation) }
    private var updateTime: String {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: observation.timezone)
        formatter.dateFormat = "HH:mm"; return formatter.string(from: observation.date)
    }
    private var moves: Bool {
        animates && motionEnabled && !reduceMotion && !islandReduceMotion && !preview && previewTime == nil && visible && presented
    }
    private var freezing: Bool { observation.temperature < 0 }
    private var chilly: Bool { freezing || observation.feelsLike < 16 }
    private var heat: Double { min(1, max(0, (observation.feelsLike - 16) / 22)) }
    private var cloudAmount: Double {
        switch observation.code ?? -1 {
        case 3, 45, 48: 1
        case 2: 0.65
        case 1: 0.25
        case 51...99: 0.85
        default: 0
        }
    }
    private var condition: String {
        mood == .hail ? (en ? "Thunderstorm with hail" : "Trovoada com granizo") : observation.condition(language: language)
    }
    var body: some View {
        // Forecast metadata is stable during display ticks. In particular, do
        // not allocate a DateFormatter at the atmosphere's 24 Hz cadence.
        let timestamp = updateTime
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moves)) { timeline in
            let time = previewTime.map { $0.isFinite ? max(0, $0) : 0 } ?? clock.time(at: timeline.date)
            ZStack {
                RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [mood.tint.opacity(0.23), Color.black.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                atmosphere(time: time, foreground: false).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(en ? "Weather with Sieg" : "O tempo com o Sieg", systemImage: mood == .hail ? "cloud.hail.fill" : observation.symbol)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(mood.tint)
                        Spacer()
                        if let stop { Button(action: stop) { Image(systemName: "stop.circle") }.help(en ? "Stop speaking" : "Parar fala").padding(.trailing, 76) }
                        else { Color.clear.frame(width: 88, height: 24) }
                    }
                    HStack(spacing: 20) {
                        character.frame(width: 154, height: 156)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(observation.location).font(.system(size: 13, weight: .medium)).lineLimit(2).padding(.trailing, 60)
                            Text("\(Int(observation.temperature.rounded()))°").font(.system(size: 60, weight: .light, design: .rounded)).monospacedDigit()
                            Text(condition).font(.callout)
                            Text(en ? "Feels like \(Int(observation.feelsLike.rounded()))°C" : "Sensação de \(Int(observation.feelsLike.rounded()))°C")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(observation.regionEstimate ? (en ? "Regional reference · conditions vary locally" : "Referência regional · varia conforme a cidade") : mood.caption(english: en)).font(.callout.weight(.medium)).lineLimit(2)
                    HStack {
                        Text("Open-Meteo · \(en ? "Estimate" : "Estimativa")").font(.system(size: 10))
                        Spacer()
                        Text(timestamp)
                            .font(.system(size: 10)).monospacedDigit()
                        Text(en ? "local · °C" : "local · °C").font(.system(size: 10))
                    }.foregroundStyle(.secondary)
                }.padding(20)
                atmosphere(time: time, foreground: true).allowsHitTesting(false)
            }.clipShape(RoundedRectangle(cornerRadius: 26)).foregroundStyle(.white).buttonStyle(.plain)
        }.frame(height: Self.height)
            // Native visibility is absent from ImageRenderer exports; an unsupported
            // NSView in their background would draw a placeholder over the panel.
            .background {
                if !preview && previewTime == nil { WeatherPanelVisibility { visible = $0 } }
            }
            .onAppear { presented = true }
            .onDisappear { presented = false; clock.setPlaying(false) }
            .onChange(of: moves, initial: true) { _, playing in clock.setPlaying(playing) }
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(mood.tint.opacity(0.25)))
    }
    private var character: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(mood.tint.opacity(wet ? 0.12 : 0.08))
                .frame(width: 112, height: 7).blur(radius: 5).offset(y: -12)
            CompanionWeatherCharacter(mood: mood, animates: moves, previewTime: previewTime, freezing: freezing)
        }.accessibilityLabel(mood.caption(english: en))
    }
    private var wet: Bool { mood == .rain || mood == .storm || mood == .hail }
    private var snowy: Bool { mood == .snow }

    /// The complete panel owns the only clip. Low-contrast foreground layers
    /// cross the data too; stronger clouds and cold light stay behind the text.
    private func atmosphere(time: Double, foreground: Bool) -> some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let bounds = CGRect(origin: .zero, size: size)
            if !foreground {
                let light = CGPoint(x: size.width * 0.25, y: size.height * 0.30)
                context.fill(Path(bounds), with: .radialGradient(Gradient(colors: [mood.tint.opacity(0.20), .clear]), center: light, startRadius: 0, endRadius: max(size.width, size.height) * 0.85))
                celestial(context: context, size: size, time: time)
            }
            if cloudAmount > 0 {
                clouds(context: context, size: size, time: time, foreground: foreground)
            }
            if chilly {
                coldAir(context: context, size: size, time: time, foreground: foreground)
            }
            if mood == .hot && !foreground {
                heatWaves(context: context, size: size, time: time)
            }
            if mood == .hail {
                hail(context: context, size: size, time: time, foreground: foreground)
            }
            if wet || snowy {
                let count = wet ? (foreground ? 26 : 86) : (foreground ? 24 : 70)
                for index in 0..<count {
                    let seed = Double(index + (foreground ? 137 : 0))
                    let depth = 0.35 + (seed * 0.37).truncatingRemainder(dividingBy: 0.65)
                    let speed = wet ? 100 + 145 * depth : 13 + 24 * depth
                    let y = (seed * 73 + time * speed).truncatingRemainder(dividingBy: size.height + 30) - 15
                    let base = (seed * 0.61803398875).truncatingRemainder(dividingBy: 1) * (size.width + 40)
                    let drift = snowy ? sin(time * 0.55 + seed) * 14 : -y * 0.14
                    let x = (base + drift + size.width + 40).truncatingRemainder(dividingBy: size.width + 40) - 20
                    let legibility = x > size.width * 0.40 ? 0.43 : 1.0
                    if wet {
                        var drop = Path(); drop.move(to: CGPoint(x: x, y: y)); drop.addLine(to: CGPoint(x: x - 3, y: y + 7 + 10 * depth))
                        context.stroke(drop, with: .color(Color(red: 0.65, green: 0.83, blue: 1).opacity((foreground ? 0.34 : 0.16) * depth * legibility * (mood == .hail ? 0.55 : 1))), style: StrokeStyle(lineWidth: foreground ? 1.1 : 0.7, lineCap: .round))
                    } else {
                        let radius = (foreground ? 2.4 : 1.7) * depth
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity((foreground ? 0.72 : 0.36) * legibility)))
                    }
                }
                if wet && foreground {
                    for index in 0..<12 {
                        let cycle = (time * 1.3 + Double(index) * 0.29).truncatingRemainder(dividingBy: 1)
                        let x = (Double(index) + 0.5) / 12 * size.width
                        context.stroke(Path(ellipseIn: CGRect(x: x - cycle * 8, y: size.height - 11 + sin(Double(index)) * 4, width: cycle * 16, height: cycle * 3)), with: .color(.cyan.opacity((1 - cycle) * 0.15)), lineWidth: 0.6)
                    }
                }
            }
        }.accessibilityHidden(true)
    }

    private func celestial(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width - 44, y: 42)
        let warm = Color(red: 1, green: 0.85 - heat * 0.29, blue: 0.56 - heat * 0.41)
        let color = observation.isDay ? warm : Color(red: 0.73, green: 0.84, blue: 1)
        let energy = (0.14 + heat * 0.25) * (1 - cloudAmount * 0.4)
        let pulse = 1 + sin(time * (1.1 + heat)) * (0.015 + heat * 0.035)
        let radius = observation.isDay ? (20 + heat * 5) * pulse : 20
        let rect = CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [color.opacity(energy * pulse), .clear]), center: center, startRadius: 0, endRadius: size.width * 0.70))
        let disc = GraphicsContext.Shading.radialGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.79), color, color.opacity(0.8)]), center: CGPoint(x: center.x-radius*0.3, y: center.y-radius*0.35), startRadius: 0, endRadius: radius*1.9)
        if observation.isDay {
            context.fill(Path(ellipseIn: rect), with: disc)
            for index in 0..<12 {
                let angle = Double(index) * .pi/6 + time*(0.055 + heat*0.10)
                let length = 5 + heat*3 + sin(time*1.5 + Double(index))*heat
                var ray = Path()
                ray.move(to: CGPoint(x: center.x+cos(angle)*(radius+4), y: center.y+sin(angle)*(radius+4)))
                ray.addLine(to: CGPoint(x: center.x+cos(angle)*(radius+4+length), y: center.y+sin(angle)*(radius+4+length)))
                context.stroke(ray, with: .color(color.opacity(0.45+heat*0.25)), style: StrokeStyle(lineWidth: 1.5+heat*0.5, lineCap: .round))
            }
        } else {
            var crescent = Path(ellipseIn: rect)
            crescent.addEllipse(in: rect.offsetBy(dx: 11, dy: -4))
            var moon = context; moon.clip(to: Path(ellipseIn: rect))
            moon.fill(crescent, with: .radialGradient(Gradient(colors: [.white, color.opacity(0.7)]), center: center, startRadius: 0, endRadius: 34), style: FillStyle(eoFill: true))
            for index in 0..<3 {
                let x = center.x - 29 + Double(index)*24, y = center.y - 24 + Double(index % 2)*48
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.45+sin(time*0.6+Double(index))*0.1)))
            }
        }
    }

    private func clouds(context: GraphicsContext, size: CGSize, time: Double, foreground: Bool) {
        let count = foreground ? 3 : 8
        for index in 0..<count {
            let seed = Double(index), width = size.width*(0.38 + Double(index % 3)*0.10)
            let distance = size.width+width*1.5
            let travel = (time*(foreground ? 5 : 8+seed*0.7)+seed*137).truncatingRemainder(dividingBy: distance)
            let x = travel-width, y = size.height*(Double(index % 4)*0.27)-27 + sin(time*0.12+seed)*9
            let height = 72+Double(index % 3)*17
            let shape = WeatherPanelDrawing.cloud.applying(CGAffineTransform(a: width, b: 0, c: 0, d: height, tx: x, ty: y))
            var cloud = context; cloud.addFilter(.blur(radius: foreground ? 12 : 7))
            let opacity = cloudAmount * (foreground ? 0.022 : 0.16)
            let top = wet ? Color(red: 0.48, green: 0.56, blue: 0.67) : Color(red: 0.86, green: 0.91, blue: 0.96)
            cloud.fill(shape, with: .linearGradient(Gradient(colors: [top.opacity(opacity), Color(red: 0.24, green: 0.31, blue: 0.40).opacity(opacity*1.1)]), startPoint: CGPoint(x: x,y: y), endPoint: CGPoint(x: x,y: y+height)))
        }
    }

    private func coldAir(context: GraphicsContext, size: CGSize, time: Double, foreground: Bool) {
        if !foreground {
            let tint = Color(red: 0.53, green: 0.78, blue: 0.91)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [tint.opacity(freezing ? 0.17 : 0.11), .clear, tint.opacity(0.11)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        }
        for index in 0..<(foreground ? 3 : 7) {
            let seed = Double(index), width = size.width*0.74
            let x = (time*(17+seed*1.4)+seed*103).truncatingRemainder(dividingBy: size.width+width)-width
            let y = size.height*(seed+0.5)/Double(foreground ? 3 : 7)
            var mist = context; mist.addFilter(.blur(radius: 17))
            mist.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: 27+seed*2)), with: .color(Color(red: 0.74, green: 0.87, blue: 0.94).opacity(foreground ? 0.025 : 0.075)))
            if !foreground {
                var wind = Path()
                wind.move(to: CGPoint(x: x+width*0.12, y: y+8))
                wind.addCurve(to: CGPoint(x: x+width*0.82, y: y), control1: CGPoint(x: x+width*0.35, y: y+20), control2: CGPoint(x: x+width*0.60, y: y-13))
                context.stroke(wind, with: .color(.white.opacity(0.075)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
    }

    private func heatWaves(context: GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<11 {
            let seed = Double(index)
            let travel = (time*(24+seed*0.7)+seed*43).truncatingRemainder(dividingBy: size.height+150)
            let y = size.height+65-travel, x = (seed+0.5)/11*size.width
            var wave = Path()
            for step in 0...12 {
                let v = Double(step)/12
                let p = CGPoint(x: x+sin(v * .pi*2.6-time*1.9+seed)*(5+seed.truncatingRemainder(dividingBy: 3)), y: y-v*76)
                if step == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
            }
            var haze = context; haze.addFilter(.blur(radius: 0.65))
            haze.stroke(wave, with: .linearGradient(Gradient(colors: [.clear, Color(red: 1, green: 0.77, blue: 0.39).opacity(x>size.width*0.40 ? 0.065 : 0.15), .clear]), startPoint: CGPoint(x: x,y: y), endPoint: CGPoint(x: x,y: y-76)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func hail(context: GraphicsContext, size: CGSize, time: Double, foreground: Bool) {
        for index in 0..<(foreground ? 18 : 38) {
            let seed = Double(index+(foreground ? 79 : 0))
            let depth = 0.5+(seed*0.37).truncatingRemainder(dividingBy: 0.5)
            let period = 1.8+depth*0.6
            let phase = (time+seed*0.113).truncatingRemainder(dividingBy: period)/period
            let baseX = (seed*0.61803398875).truncatingRemainder(dividingBy: 1)*size.width
            let falling = phase < 0.72
            let flight = phase/0.72
            let bounce = (phase-0.72)/0.28
            let x = baseX + (falling ? flight*17 : 17+bounce*9)
            let y = falling ? -12+flight*(size.height+1) : size.height-11-sin(bounce * .pi)*(12+depth*14)
            let radius = (foreground ? 2.8 : 2.0)*depth
            let rect = CGRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2)
            let contrast = (x>size.width*0.40 ? 0.43 : 1)*(falling ? 1 : 1-bounce)
            context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [.white.opacity(contrast), Color(red: 0.48, green: 0.70, blue: 0.86).opacity(contrast*0.85)]), center: CGPoint(x: x-radius*0.3,y: y-radius*0.3), startRadius: 0, endRadius: radius*2))
        }
    }
}

private enum WeatherPanelDrawing {
    static let cloud: Path = {
        var p = Path(); p.move(to: CGPoint(x: 0.04,y: 0.80))
        p.addCurve(to: CGPoint(x: 0.20,y: 0.39), control1: CGPoint(x: -0.04,y: 0.40), control2: CGPoint(x: 0.09,y: 0.34))
        p.addCurve(to: CGPoint(x: 0.53,y: 0.22), control1: CGPoint(x: 0.18,y: -0.05), control2: CGPoint(x: 0.49,y: -0.02))
        p.addCurve(to: CGPoint(x: 0.80,y: 0.37), control1: CGPoint(x: 0.67,y: 0.03), control2: CGPoint(x: 0.82,y: 0.13))
        p.addCurve(to: CGPoint(x: 0.96,y: 0.80), control1: CGPoint(x: 0.99,y: 0.30), control2: CGPoint(x: 1.05,y: 0.68))
        p.addCurve(to: CGPoint(x: 0.04,y: 0.80), control1: CGPoint(x: 0.78,y: 1.02), control2: CGPoint(x: 0.20,y: 0.98)); p.closeSubpath()
        return p
    }()
}

private struct WeatherPanelClock {
    private var started: Date?
    private var elapsed = 0.0
    func time(at date: Date) -> Double { elapsed + (started.map { max(0,date.timeIntervalSince($0)) } ?? 0) }
    mutating func setPlaying(_ playing: Bool) {
        if playing, started == nil { started = Date() }
        else if !playing, let start = started { elapsed += max(0,Date().timeIntervalSince(start)); started = nil }
    }
}

/// Window events gate the Canvas schedule too. No new polling timer; the native
/// character retains its existing renderer visibility safeguards independently.
private struct WeatherPanelVisibility: NSViewRepresentable {
    var changed: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { let view = VisibilityView(); view.changed = changed; return view }
    func updateNSView(_ view: VisibilityView, context: Context) { view.changed = changed }
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.stop() }
    final class VisibilityView: NSView {
        var changed: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var last: Bool?
        private var generation = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var isHidden: Bool { didSet { publish() } }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); removeObservers()
            let generation = self.generation
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                             NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                        let closing = note.name == NSWindow.willCloseNotification
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == generation else { return }
                            self.publish(closing: closing)
                        }
                    })
                }
            }
            publish()
        }
        private func publish(closing: Bool = false) {
            let visible = !closing && !isHiddenOrHasHiddenAncestor && (window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false)
            guard visible != last else { return }; last = visible
            Task { @MainActor [weak self] in
                guard let self, self.last == visible else { return }
                self.changed?(visible)
            }
        }
        func stop() { changed = nil; removeObservers() }
        private func removeObservers() { generation += 1; observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll() }
        isolated deinit { removeObservers() }
    }
}
