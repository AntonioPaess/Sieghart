import SwiftUI

struct CodexUsageView: View {
    @EnvironmentObject private var usage: CodexUsageModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            HStack {
                ProviderMark(provider: .codex)
                Text("Codex limits").font(.headline)
                Spacer()
                if usage.enabled {
                    Button { Task { await usage.refresh(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain).focusEffectDisabled().disabled(usage.isRefreshing).accessibilityLabel("Refresh Codex limits")
                    Button { usage.enabled = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("Disconnect Codex usage")
                }
            }
            if usage.enabled {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 10) {
                        if let bucket = usage.bucket {
                            if let primary = bucket.primary { QuotaWindowView(window: primary, now: context.date) }
                            if let secondary = bucket.secondary { QuotaWindowView(window: secondary, now: context.date) }
                        } else {
                            Text(usage.isRefreshing ? "Reading your limits…" : "Limits unavailable")
                                .font(.callout).foregroundStyle(CompanionStyle.muted)
                        }
                    }
                }
                if let error = usage.errorMessage {
                    Text(error).font(.caption).foregroundStyle(CompanionStyle.muted)
                    if usage.bucket != nil { Text("Showing the last successful reading.").font(.caption).foregroundStyle(.orange) }
                }
                if let updated = usage.updatedAt {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(CompanionStyle.muted)
                }
            } else {
                Text("See what’s left in each window and when it resets.").font(.caption).foregroundStyle(CompanionStyle.muted)
                Button("Connect local Codex") { usage.enabled = true }
                    .buttonStyle(CompanionButtonStyle()).focusEffectDisabled()
            }
        }
        .padding(compact ? 14 : 20)
        .background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .task(id: usage.enabled) { await usage.refreshWhileVisible() }
    }

}

struct QuotaWindowView: View {
    let window: CodexQuotaWindow
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.title).font(.callout.weight(.medium))
                Spacer()
                Text(window.remainingPercent(at: now).map { "\($0)% left" } ?? "—")
                    .font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(CompanionStyle.accent)
            }
            GeometryReader { geometry in
                Capsule().fill(CompanionStyle.separator)
                    .overlay(alignment: .leading) {
                        if let remaining = window.remainingPercent(at: now) {
                            Capsule().fill(CompanionStyle.accent).frame(width: geometry.size.width * CGFloat(remaining) / 100)
                        }
                    }
            }.frame(height: 3).accessibilityHidden(true)
            if let reset = window.resetDate {
                Text(reset <= now ? "Reset due — refresh to update" : "Resets \(reset.formatted(date: .abbreviated, time: .shortened)) · \(countdown(to: reset, from: now))")
                    .font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Reset time unavailable").font(.caption).foregroundStyle(CompanionStyle.muted)
            }
        }.padding(.vertical, 3)
    }

    private func countdown(to reset: Date, from now: Date) -> String {
        let minutes = max(1, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h left" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m left" }
        return "\(minutes)m left"
    }
}
