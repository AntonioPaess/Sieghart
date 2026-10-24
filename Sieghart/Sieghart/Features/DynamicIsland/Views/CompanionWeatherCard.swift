import SwiftUI

struct CompanionWeatherCard: View {
    static let height: CGFloat = 132
    let observation: VoiceWeatherObservation
    let language: String
    let animates: Bool
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var english: Bool { language.hasPrefix("en") }
    private var tint: Color {
        if observation.symbol.contains("rain") || observation.symbol.contains("drizzle") { return Color(red: 0.39, green: 0.70, blue: 0.96) }
        if observation.temperature < 16 { return Color(red: 0.51, green: 0.81, blue: 0.95) }
        return Color(red: 0.99, green: 0.75, blue: 0.37)
    }
    private var updateTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: observation.timezone)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: observation.date)
    }

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: observation.symbol)
                .symbolRenderingMode(.palette).foregroundStyle(tint, tint.opacity(0.55), .white.opacity(0.8))
                .font(.system(size: 40, weight: .light))
                .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: animates && !reduceMotion)
                .frame(width: 68, height: 76)
                .background(Circle().fill(tint.opacity(0.12)).blur(radius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(observation.location).font(.callout.weight(.semibold)).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(Int(observation.temperature.rounded()))°").font(.system(size: 37, weight: .light, design: .rounded)).monospacedDigit()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(observation.condition(language: language)).font(.callout)
                        Text(english ? "Feels like \(Int(observation.feelsLike.rounded()))°C" : "Sensação de \(Int(observation.feelsLike.rounded()))°C")
                            .font(.caption).foregroundStyle(CompanionStyle.muted)
                    }
                }
                Text(english ? "Open-Meteo · Estimate · \(updateTime) local" : "Open-Meteo · Estimativa · \(updateTime) local")
                    .font(.system(size: 10)).foregroundStyle(CompanionStyle.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).padding(7) }
                    .buttonStyle(.plain).foregroundStyle(CompanionStyle.muted)
                    .accessibilityLabel(english ? "Dismiss weather" : "Fechar clima")
                Spacer(minLength: 0)
                Text("°C").font(.caption.weight(.medium)).foregroundStyle(CompanionStyle.muted)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.20), lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
    }
}
