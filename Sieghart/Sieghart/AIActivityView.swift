import SwiftUI

private enum UsagePeriod: String, CaseIterable { case today = "Today", week = "This week", month = "This month"
    var start: Date {
        Calendar.current.dateInterval(of: self == .today ? .day : self == .week ? .weekOfYear : .month, for: .now)?.start ?? .now
    }
}

struct AIUsageView: View {
    @EnvironmentObject private var codex: CodexUsageModel
    @EnvironmentObject private var usage: AIUsageModel
    @EnvironmentObject private var preferences: CompanionPreferences
    @State private var provider: AIProvider = .codex
    @State private var period: UsagePeriod = .today
    @State private var details = false
    private var points: [AIUsagePoint] { usage.analytics.filtered(provider: provider, since: period.start) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI agents").font(.title2.weight(.semibold))
                Spacer()
                if usage.claudeEnabled {
                    ForEach(AIProvider.allCases) { choice in
                        Button(choice.title) { provider = choice }.buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(provider == choice ? CompanionStyle.accent : CompanionStyle.muted)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(UsagePeriod.allCases, id: \.self) { choice in
                        Button(choice == .today ? "Today" : choice == .week ? "Week" : "Month") { period = choice }
                            .buttonStyle(.plain).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 7)
                            .foregroundStyle(period == choice ? .white : CompanionStyle.muted)
                            .background(period == choice ? CompanionStyle.separator : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityValue(period == choice ? "Selected" : "")
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { limits.frame(minWidth: 270); spending.frame(minWidth: 250) }
                VStack(spacing: 16) { limits; spending }
            }
            currentWork
            trend
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { ranking("Models", symbol: "cpu", key: \.model).frame(minWidth: 240); ranking("Projects", symbol: "folder", key: \.project).frame(minWidth: 240) }
                VStack(spacing: 16) { ranking("Models", symbol: "cpu", key: \.model); ranking("Projects", symbol: "folder", key: \.project) }
            }
            activity
            HStack {
                Text("Hourly, model and project charts · Partial local history").font(.caption2)
                Spacer()
                if let updated = usage.activityUpdatedAt { Text("Updated \(updated.formatted(date: .omitted, time: .shortened))").font(.caption2) }
            }.foregroundStyle(CompanionStyle.muted)
            DisclosureGroup("Tokens, charges & connections", isExpanded: $details) { AIUsageDetailsView().padding(.top, 14) }
                .font(.callout).tint(CompanionStyle.accent)
        }
        .foregroundStyle(.white)
        .onChange(of: usage.claudeEnabled) { _, enabled in if !enabled { provider = .codex } }
    }

    @ViewBuilder private var limits: some View {
        if provider == .codex { CodexUsageView(compact: true) }
        else {
            VStack(alignment: .leading, spacing: 12) {
                Label { Text("Claude Code").font(.headline) } icon: { ProviderMark(provider: .claude) }
                if let report = usage.claudeReport {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        VStack(spacing: 8) {
                            if let window = report.primary { QuotaWindowView(window: window.window, now: context.date) }
                            if let window = report.secondary { QuotaWindowView(window: window.window, now: context.date) }
                        }
                    }
                    Text("Dated report").font(.caption2).foregroundStyle(CompanionStyle.muted)
                } else { Text("Subscription limits unavailable").font(.callout).foregroundStyle(CompanionStyle.muted) }
            }.companionCard()
        }
    }

    private var spending: some View {
        let input = points.reduce(Int64(0)) { $0 + $1.input }, output = points.reduce(Int64(0)) { $0 + $1.output }, cache = points.reduce(Int64(0)) { $0 + $1.cached }
        let tokens = LocalTokenUsage(input: input, cachedInput: cache, cacheCreation: points.reduce(0) { $0 + $1.cacheCreation }, output: output, sessions: 0)
        let estimate = usage.ledger.prices[provider]?.estimate(points.isEmpty ? nil : tokens)
        return VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Spending", systemImage: "dollarsign.circle").font(.headline); Spacer(); Text(period.rawValue).font(.caption).foregroundStyle(CompanionStyle.muted) }
            if let estimate {
                Text(estimate.formatted(.currency(code: "USD"))).font(.system(size: 32, weight: .semibold)).monospacedDigit()
                if let rate = usage.ledger.usdToBRL { Text((estimate * rate).formatted(.currency(code: "BRL"))).font(.callout).foregroundStyle(CompanionStyle.muted) }
            } else {
                Text("Estimate unavailable").font(.title3.weight(.medium))
                Button("Set token prices") { details = true }.buttonStyle(.plain).foregroundStyle(CompanionStyle.accent).font(.caption)
            }
            Capsule().fill(CompanionStyle.accent).frame(height: 4)
            Text(points.isEmpty ? "No token records for this period" : "\(short(input + output)) tokens · \(input > 0 ? Int(Double(cache) / Double(input) * 100) : 0)% input cache")
                .font(.caption).foregroundStyle(CompanionStyle.muted)
            Text("API-equivalent estimate · Custom prices").font(.caption2).foregroundStyle(CompanionStyle.muted)
            ForEach(SpendCurrency.allCases, id: \.self) { currency in
                let charges = usage.ledger.charges.filter { $0.provider == provider && $0.currency == currency && $0.date >= period.start && $0.date <= Date() }
                if !charges.isEmpty {
                    Text("Recorded charges: \(charges.reduce(Decimal.zero) { $0 + $1.amount }.formatted(.currency(code: currency.rawValue)))").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
            }
            HStack {
                metric("Input", input); metric("Output", output); metric("Cache", cache)
            }
        }.companionCard()
    }
    private func metric(_ label: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption2).foregroundStyle(CompanionStyle.muted); Text(points.isEmpty ? "—" : short(value)).font(.callout.weight(.medium)) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var currentWork: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let work = usage.analytics.work.filter { $0.provider == provider && $0.isCurrent(at: context.date) }
            VStack(alignment: .leading, spacing: 16) {
                HStack { Label("Now", systemImage: "waveform.path.ecg").font(.headline); Spacer(); Circle().fill(work.isEmpty ? CompanionStyle.muted : CompanionStyle.accent).frame(width: 7, height: 7) }
                if work.isEmpty {
                    HStack(spacing: 14) {
                        CompanionCharacter(size: 48, avatar: preferences.avatar, animates: false)
                        VStack(alignment: .leading, spacing: 4) { Text("Ready when you are.").font(.headline); Text("Active AI work appears here automatically after monitoring is enabled.").font(.caption).foregroundStyle(CompanionStyle.muted) }
                    }
                } else {
                    ForEach(work.prefix(4)) { task in
                        HStack(spacing: 14) {
                            CompanionCharacter(size: 48, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion, focusing: true)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { ProviderMark(provider: task.provider, size: 22); Text(task.project).font(.headline).lineLimit(1) }
                                Text("\(task.model) · \(short(task.output)) recent output").font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(task.elapsed(at: context.date)).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(CompanionStyle.accent)
                        }
                    }
                }
            }.companionCard()
        }
    }
    private var trend: some View {
        let today = usage.analytics.filtered(provider: provider, since: Calendar.current.startOfDay(for: .now))
        let hours = (0..<24).map { hour in today.filter { Calendar.current.component(.hour, from: $0.date) == hour }.reduce(Int64(0)) { $0 + $1.total } }
        return VStack(alignment: .leading, spacing: 16) {
            HStack { Label("Trend", systemImage: "chart.bar.xaxis").font(.headline); Spacer(); Text(today.isEmpty ? "Today · No records" : "Today · \(short(hours.reduce(0, +))) tokens").font(.caption).foregroundStyle(CompanionStyle.muted) }
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<24, id: \.self) { hour in
                        let value = hours[hour], peak = max(1, hours.max() ?? 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(value > 0 ? CompanionStyle.accent : CompanionStyle.separator)
                            .frame(maxWidth: .infinity)
                            .frame(height: value > 0 ? max(3, geometry.size.height * Double(value) / Double(peak)) : 3)
                            .help(String(format: "%02d:00 · %@ tokens", hour, value.formatted()))
                            .accessibilityLabel(String(format: "%02d:00, %@ tokens", hour, value.formatted()))
                    }
                }.frame(height: geometry.size.height, alignment: .bottom)
            }.frame(height: 135)
                .accessibilityLabel("Today's hourly token usage")
            HStack { Text("00"); Spacer(); Text("12"); Spacer(); Text("23") }.font(.caption2).foregroundStyle(CompanionStyle.muted)
            if today.isEmpty { Text("No usage found in today's local records.").font(.caption).foregroundStyle(CompanionStyle.muted) }
        }.companionCard()
    }
    private func ranking(_ title: String, symbol: String, key: KeyPath<AIUsagePoint, String>) -> some View {
        let groups = Dictionary(grouping: points, by: { $0[keyPath: key] }).map { name, values in (name, values.reduce(Int64(0)) { $0 + $1.total }) }.sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
            if groups.isEmpty { Text("No records for this period").font(.caption).foregroundStyle(CompanionStyle.muted) }
            ForEach(Array(groups.prefix(5).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Text(item.0).font(.callout.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { geometry in Capsule().fill(title == "Models" ? CompanionStyle.accent : .white).frame(width: max(3, geometry.size.width * Double(item.1) / Double(max(1, groups.first?.1 ?? 1)))) }.frame(width: 62, height: 4)
                    Text(short(item.1)).font(.caption).foregroundStyle(CompanionStyle.muted).frame(width: 45, alignment: .trailing)
                }.accessibilityElement(children: .combine)
            }
        }.companionCard()
    }
    private var daily: [Date: Int64] {
        let calendar = Calendar.current
        if provider == .codex, let buckets = codex.enabled ? usage.accountActivity?.dailyUsageBuckets : nil {
            return buckets.reduce(into: [:]) { result, day in
                let parts = day.startDate.split(separator: "-").compactMap { Int($0) }
                if parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), day.tokens >= 0 { result[date] = day.tokens }
            }
        }
        return Dictionary(grouping: usage.analytics.points.filter { $0.provider == provider }, by: { calendar.startOfDay(for: $0.date) }).mapValues { $0.reduce(0) { $0 + $1.total } }
    }
    private var activity: some View {
        let calendar = Calendar.current, today = calendar.startOfDay(for: .now)
        let dates = (0..<91).map { calendar.date(byAdding: .day, value: $0 - 90, to: today)! }
        let values = daily, peak = dates.map { values[$0] ?? 0 }.max() ?? 0
        let total = dates.reduce(Int64(0)) { $0 + (values[$1] ?? 0) }
        let active = dates.filter { (values[$0] ?? 0) > 0 }.count
        let source = provider == .codex && usage.accountActivity?.dailyUsageBuckets != nil ? "Codex account activity" : "Partial local history"
        return VStack(alignment: .leading, spacing: 16) {
            HStack { Label("Activity", systemImage: "square.grid.3x3.fill").font(.headline); Spacer(); if provider == .codex, let streak = usage.accountActivity?.summary?.currentStreakDays { Label("\(streak)", systemImage: "flame.fill").font(.callout.weight(.medium)).foregroundStyle(.orange) } }
            HStack(alignment: .top, spacing: 22) {
                HStack(spacing: 4) {
                    ForEach(0..<13) { week in
                        VStack(spacing: 4) {
                            ForEach(0..<7) { day in
                                let date = dates[week * 7 + day], count = values[date] ?? 0
                                RoundedRectangle(cornerRadius: 3).fill(count == 0 ? CompanionStyle.separator.opacity(0.5) : Color.white.opacity(0.25 + 0.75 * Double(count) / Double(max(1, peak))))
                                    .frame(width: 12, height: 12)
                                    .help("\(date.formatted(date: .abbreviated, time: .omitted)): \(values[date].map { "\($0.formatted()) tokens" } ?? "No record")")
                                    .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), \(values[date].map { "\($0.formatted()) tokens" } ?? "No record")")
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) { Text(values.isEmpty ? "—" : short(total)).font(.title.weight(.semibold)); Text("13 weeks").font(.caption).foregroundStyle(CompanionStyle.muted); Spacer(minLength: 8); Text(values.isEmpty ? "Activity unavailable" : "\(active) active days").font(.caption); Text(source).font(.caption2).foregroundStyle(CompanionStyle.muted) }
                Spacer(minLength: 0)
            }
            if provider == .codex, let updated = usage.accountUpdatedAt {
                Text("\(usage.accountRefreshFailed ? "Last account reading" : "Account updated") \(updated.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(usage.accountRefreshFailed ? .orange : CompanionStyle.muted)
            }
            if let date = dates.max(by: { (values[$0] ?? 0) < (values[$1] ?? 0) }), peak > 0 {
                HStack { Text("Most intense day"); Spacer(); Text("\(date.formatted(date: .abbreviated, time: .omitted)) · \(short(peak))") }.font(.caption).foregroundStyle(CompanionStyle.muted)
            }
        }.companionCard()
    }
    private func short(_ value: Int64) -> String { value.formatted(.number.notation(.compactName)) }
}
