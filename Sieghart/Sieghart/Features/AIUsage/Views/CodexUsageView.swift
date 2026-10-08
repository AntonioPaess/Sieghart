import SwiftUI

struct CodexUsageView: View {
    @EnvironmentObject private var usage: CodexUsageViewModel
    @EnvironmentObject private var localUsage: AIUsageViewModel
    @Environment(\.islandGlass) private var glass
    @Environment(\.workspaceGlass) private var workspace
    var compact = false
    var dashboard = false
    var cardHeight: CGFloat?
    private var dense: Bool { dashboard && glass && !workspace }
    private var padding: CGFloat { dense ? 10 : dashboard ? (workspace ? 24 : 16) : compact ? 14 : 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 5 : compact ? 10 : 16) {
            HStack {
                ProviderMark(provider: .codex, size: dense ? 18 : 28)
                Text(dashboard ? "Codex" : "Codex limits").font(dense ? .system(size: 10.5, weight: .semibold) : .headline)
                if let plan = usage.bucket?.planType { Text(plan.capitalized).font(.caption2.weight(.semibold)).foregroundStyle(CompanionStyle.accentInk) }
                Spacer()
                if dense, let error = usage.errorMessage { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(error).accessibilityLabel(error) }
                if usage.enabled {
                    Button { Task { await usage.refresh(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain).focusEffectDisabled().disabled(usage.isRefreshing).accessibilityLabel("Refresh Codex limits")
                    if !dashboard { Button { localUsage.disable(.codex, codex: usage) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("Disconnect Codex usage") }
                }
            }
            if usage.enabled {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: dense ? 6 : 10) {
                        if let bucket = usage.bucket {
                            if let primary = bucket.primary { QuotaWindowView(window: primary, now: context.date, compact: dashboard, dense: dense) }
                            if let secondary = bucket.secondary { QuotaWindowView(window: secondary, now: context.date, compact: dashboard, dense: dense) }
                        } else {
                            Text(usage.isRefreshing ? "Reading your limits…" : "Limits unavailable")
                                .font(.callout).foregroundStyle(CompanionStyle.muted)
                        }
                    }
                }
                if !dense, let error = usage.errorMessage {
                    Text(usage.bucket != nil ? "Last successful reading · Refresh unavailable" : error)
                        .font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(dashboard ? 1 : nil).help(error)
                }
                if !dashboard, let updated = usage.updatedAt {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(CompanionStyle.muted)
                }
            } else {
                Text("See what’s left in each window and when it resets.").font(.caption).foregroundStyle(CompanionStyle.muted)
                Button("Connect local Codex") { usage.enabled = true }
                    .buttonStyle(CompanionButtonStyle()).focusEffectDisabled()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: cardHeight.map { max(0, $0 - padding * 2) }, alignment: .topLeading)
        .padding(padding)
        .modifier(CodexCardChrome(glass: glass, workspace: workspace))
        .task(id: usage.enabled) { await usage.refreshWhileVisible() }
    }

}

private struct CodexCardChrome: ViewModifier {
    var glass: Bool
    var workspace: Bool
    func body(content: Content) -> some View {
        if workspace { content.modifier(WorkspaceSurface()) }
        else if glass { content.modifier(IslandControlSurface()) }
        else { content.background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 16)) }
    }
}

struct QuotaWindowView: View {
    let window: CodexQuotaWindow
    let now: Date
    var compact = false
    var dense = false
    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 3 : 5) {
            HStack {
                Text(compact ? (window.windowDurationMins == 300 ? "Session" : window.windowDurationMins == 10080 ? "Week" : window.title) : window.title).font(dense ? .system(size: 10, weight: .medium) : .callout.weight(.medium))
                if compact, let reset = window.resetDate { Text(reset <= now ? "Reset due" : countdown(to: reset, from: now)).font(dense ? .system(size: 9) : .caption2).foregroundStyle(CompanionStyle.muted) }
                Spacer()
                Text(window.remainingPercent(at: now).map { "\($0)% left" } ?? "—")
                    .font(dense ? .system(size: 10, weight: .semibold) : .callout.weight(.semibold)).monospacedDigit().foregroundStyle(CompanionStyle.accentInk)
            }
            GeometryReader { geometry in
                Capsule().fill(CompanionStyle.separator)
                    .overlay(alignment: .leading) {
                        if let remaining = window.remainingPercent(at: now) {
                            Capsule().fill(CompanionStyle.accent).frame(width: geometry.size.width * CGFloat(remaining) / 100)
                        }
                    }
            }.frame(height: dense ? 5 : compact ? 8 : 3).accessibilityHidden(true)
            if !compact, let reset = window.resetDate {
                Text(reset <= now ? "Reset due — refresh to update" : "Resets \(reset.formatted(date: .abbreviated, time: .shortened)) · \(countdown(to: reset, from: now))")
                    .font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
            } else if !compact {
                Text("Reset time unavailable").font(.caption).foregroundStyle(CompanionStyle.muted)
            }
        }.padding(.vertical, dense ? 1 : 3)
            .help(window.resetDate.map { "Resets \($0.formatted(date: .complete, time: .shortened))" } ?? "Reset time unavailable")
    }

    private func countdown(to reset: Date, from now: Date) -> String {
        let minutes = max(1, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h left" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m left" }
        return "\(minutes)m left"
    }
}
