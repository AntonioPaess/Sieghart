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
    @Environment(\.islandGlass) private var glass
    @Environment(\.workspaceGlass) private var workspace
    @Environment(\.islandPreview) private var preview
    @State private var provider: AIProvider = .codex
    @State private var period: UsagePeriod = .today
    @State private var details = false
    @State private var selectedHour: Int?
    @State private var selectedDay: Date?
    private var providers: [AIProvider] { usage.usedProviders(codex: codex) }
    var showsHeader = true
    init(initialHour: Int? = nil, showsHeader: Bool = true) { self.showsHeader = showsHeader; _selectedHour = State(initialValue: initialHour) }
    private var points: [AIUsagePoint] { usage.analytics.filtered(provider: provider, since: period.start) }
    private var dense: Bool { glass && !workspace }
    private var summaryHeight: CGFloat { dense ? 96 : 192 }
    private var rankingHeight: CGFloat { dense ? 96 : 162 }
    private var heading: Font { dense ? .system(size: 10.5, weight: .semibold) : .headline }
    private var detail: Font { dense ? .system(size: 9) : .caption }
    private var cardPadding: CGFloat? { dense ? 10 : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 10 : 16) {
            if showsHeader || providers.count > 1 { HStack {
                if showsHeader { Text("AI agents").font(.title2.weight(.semibold)) }
                Spacer()
                if providers.count > 1 {
                    ForEach(providers) { choice in
                        Button(choice.title) { provider = choice }.buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(provider == choice ? CompanionStyle.accentInk : CompanionStyle.muted)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(UsagePeriod.allCases, id: \.self) { choice in
                        Button(choice == .today ? "Today" : choice == .week ? "Week" : "Month") { period = choice }
                            .buttonStyle(.plain).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 7)
                            .foregroundStyle(period == choice ? CompanionStyle.ink : CompanionStyle.muted)
                            .background(period == choice ? CompanionStyle.separator : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityValue(period == choice ? "Selected" : "")
                    }
                }
            } }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: dense ? 10 : 16) { limits.frame(minWidth: 280, maxWidth: .infinity); spending.frame(minWidth: 280, maxWidth: .infinity) }
                VStack(spacing: 16) { limits; spending }
            }
            currentWork
            trend
            ViewThatFits(in: .horizontal) {
                HStack(spacing: dense ? 10 : 16) { ranking("Models", symbol: "cpu", key: \.model).frame(minWidth: 240, maxWidth: .infinity); ranking("Projects", symbol: "folder", key: \.project).frame(minWidth: 240, maxWidth: .infinity) }
                VStack(spacing: 16) { ranking("Models", symbol: "cpu", key: \.model); ranking("Projects", symbol: "folder", key: \.project) }
            }
            activity
            HStack {
                Text("Hourly, model and project charts · Partial local history").font(.caption2)
                Spacer()
                if let updated = usage.activityUpdatedAt { Text("Updated \(updated.formatted(date: .omitted, time: .shortened))").font(.caption2) }
            }.foregroundStyle(CompanionStyle.muted)
            Button("Tokens, charges & connections") { details = true }.buttonStyle(.plain).font(.caption).foregroundStyle(CompanionStyle.accentInk)
        }
        .foregroundStyle(CompanionStyle.ink)
        .sheet(isPresented: $details) {
            VStack(spacing: 16) {
                HStack { Text("AI data & connections").font(.title3.weight(.semibold)); Spacer(); Button("Done") { details = false }.buttonStyle(CompanionButtonStyle()) }
                ScrollView { AIUsageDetailsView() }.scrollIndicators(.hidden)
            }.padding(28).frame(width: 720, height: 580).background { WorkspaceBackdrop() }.preferredColorScheme(preferences.appearance.colorScheme).environment(\.surfaceGlassEnabled, preferences.windowGlass).environment(\.workspaceGlass, true)
        }
        .onAppear { if let first = providers.first { provider = first } }
        .onChange(of: providers) { _, choices in
            if !choices.contains(provider), let first = choices.first { provider = first }
            selectedHour = nil; selectedDay = nil
        }
        .onChange(of: provider) { _, _ in selectedHour = nil; selectedDay = nil }
    }

    @ViewBuilder private var limits: some View {
        if provider == .codex { CodexUsageView(compact: true, dashboard: true, cardHeight: summaryHeight) }
        else {
            VStack(alignment: .leading, spacing: dense ? 5 : 10) {
                Label { Text("Claude").font(heading) } icon: { ProviderMark(provider: .claude, size: dense ? 18 : 28) }
                if let report = usage.effectiveClaudeReport {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        VStack(spacing: 8) {
                            if let window = report.primary { QuotaWindowView(window: window.window, now: context.date, compact: true, dense: dense) }
                            if let window = report.secondary { QuotaWindowView(window: window.window, now: context.date, compact: true, dense: dense) }
                        }
                    }
                    if !dense { Text(usage.claudeSource).font(.caption2).foregroundStyle(CompanionStyle.muted) }
                } else { Text("Subscription limits unavailable").font(.callout).foregroundStyle(CompanionStyle.muted) }
            }.companionCard(height: summaryHeight, padding: cardPadding)
        }
    }

    private var spending: some View {
        let input = points.reduce(Int64(0)) { $0 + $1.input }, output = points.reduce(Int64(0)) { $0 + $1.output }, cache = points.reduce(Int64(0)) { $0 + $1.cached }
        let estimate = usage.estimate(points, provider: provider)
        return VStack(alignment: .leading, spacing: dense ? 3 : 8) {
            HStack {
                Label("Spending", systemImage: "dollarsign.circle").font(heading); Spacer()
                if dense && !showsHeader && !preview {
                    Menu { ForEach(UsagePeriod.allCases, id: \.self) { choice in Button(choice.rawValue) { period = choice } } }
                    label: { Text(period.rawValue).font(detail) }.menuStyle(.borderlessButton).fixedSize()
                } else { Text(period.rawValue).font(detail).foregroundStyle(CompanionStyle.muted) }
            }
            if estimate.hasValue {
                Text(estimate.label).font(.system(size: dense ? 27 : 32, weight: .medium)).monospacedDigit()
            } else {
                Text("Estimate unavailable").font(dense ? .system(size: 12, weight: .medium) : .title3.weight(.medium))
                Button("Prices & sources") { details = true }.buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk).font(detail)
            }
            Capsule().fill(CompanionStyle.accent).frame(height: dense ? 3 : 4)
            Text(points.isEmpty ? "No token records for this period" : "\(short(input + output)) tokens · \(input > 0 ? Int(Double(cache) / Double(input) * 100) : 0)% input cache")
                .font(detail).foregroundStyle(CompanionStyle.muted)
            HStack(spacing: 6) {
                Text("API equivalent").font(dense ? .system(size: 8) : .caption2).foregroundStyle(CompanionStyle.muted)
                if estimate.unpricedTokens > 0 { Text("\(short(estimate.unpricedTokens)) unpriced").font(dense ? .system(size: 8) : .caption2).foregroundStyle(CompanionStyle.muted) }
            }.help("API token value, not your subscription bill. " + usage.pricingDescription(provider) + " · Input \(input.formatted()) · Output \(output.formatted()) · Cache \(cache.formatted()) · Unpriced \(estimate.unpricedTokens.formatted()) tokens")
        }.companionCard(height: summaryHeight, padding: cardPadding)
    }
    private func metric(_ label: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption2).foregroundStyle(CompanionStyle.muted); Text(points.isEmpty ? "—" : value.formatted()).font(.callout.weight(.medium)) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var currentWork: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let work = usage.analytics.work.filter { $0.provider == provider && $0.isCurrent(at: context.date) }
            VStack(alignment: .leading, spacing: dense ? 6 : 16) {
                HStack { Label("Now", systemImage: "waveform.path.ecg").font(heading); Spacer(); Circle().fill(work.isEmpty ? CompanionStyle.muted : CompanionStyle.accent).frame(width: 7, height: 7) }
                if work.isEmpty {
                    HStack(spacing: 14) {
                        CompanionCharacter(size: dense ? 24 : 36, avatar: preferences.avatar, animates: false)
                        VStack(alignment: .leading, spacing: 4) { Text("Ready when you are.").font(heading); Text("Active AI work appears here automatically after monitoring is enabled.").font(detail).foregroundStyle(CompanionStyle.muted) }
                    }
                } else {
                    ForEach(work.prefix(2)) { task in
                        HStack(spacing: 14) {
                            CompanionCharacter(size: dense ? 22 : 36, avatar: preferences.avatar, animates: preferences.characterMotion && !preferences.usesReducedMotion, focusing: true)
                            VStack(alignment: .leading, spacing: dense ? 2 : 5) {
                                HStack { ProviderMark(provider: task.provider, size: dense ? 14 : 22); Text(task.project).font(heading).lineLimit(1) }
                                Text("\(modelName(task.model)) · \(task.output.formatted()) recent output").font(detail).foregroundStyle(CompanionStyle.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(task.elapsed(at: context.date)).font(dense ? .system(size: 13, weight: .semibold) : .title3.weight(.semibold)).monospacedDigit().foregroundStyle(CompanionStyle.accentInk)
                        }
                    }
                }
            }.companionCard(height: dense ? 96 : nil, padding: cardPadding)
        }
    }
    private var trend: some View {
        let today = usage.analytics.filtered(provider: provider, since: Calendar.current.startOfDay(for: .now))
        let hours = (0..<24).map { hour in today.filter { Calendar.current.component(.hour, from: $0.date) == hour }.reduce(Int64(0)) { $0 + $1.total } }
        return VStack(alignment: .leading, spacing: dense ? 5 : 16) {
            HStack { Label("Trend", systemImage: "chart.bar.xaxis").font(heading); Spacer(); Text(today.isEmpty ? "Today · No records" : "Today · \(short(hours.reduce(0, +))) tokens").font(detail).foregroundStyle(CompanionStyle.muted) }
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<24, id: \.self) { hour in
                        let value = hours[hour], peak = max(1, hours.max() ?? 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(value > 0 ? CompanionStyle.accent : CompanionStyle.separator)
                            .frame(maxWidth: .infinity)
                            .frame(height: value > 0 ? max(3, geometry.size.height * Double(value) / Double(peak)) : 3)
                            .frame(height: geometry.size.height, alignment: .bottom)
                            .contentShape(Rectangle())
                            .onHover { inside in selectedHour = inside ? hour : (selectedHour == hour ? nil : selectedHour) }
                            .onTapGesture { selectedHour = hour }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { selectedHour = hour }
                            .accessibilityLabel(String(format: "%02d:00, %@ tokens", hour, value.formatted()))
                    }
                }.frame(height: geometry.size.height, alignment: .bottom)
            }.frame(height: dense ? 58 : 108)
                .accessibilityLabel("Today's hourly token usage")
            HStack { Text("00"); Spacer(); Text("12"); Spacer(); Text("23") }.font(.caption2).foregroundStyle(CompanionStyle.muted)
            let selection = selectedHour.map { hour in today.filter { Calendar.current.component(.hour, from: $0.date) == hour } } ?? []
            VStack(alignment: .leading, spacing: dense ? 2 : 5) {
                Text(selectedHour.map { String(format: "%02d:00–%02d:00 · %@ tokens", $0, $0 + 1, hours[$0].formatted()) } ?? "Hover or select an hour to see its tokens and value.").font(dense ? .system(size: 9, weight: .semibold) : .caption.weight(.semibold))
                Text(selectedHour == nil ? "Input · Output · Cache read · API equivalent" : "Input \(selection.reduce(0) { $0 + $1.input }.formatted()) · Output \(selection.reduce(0) { $0 + $1.output }.formatted()) · Cache \(selection.reduce(0) { $0 + $1.cached }.formatted()) · \(selection.isEmpty ? "$0.00" : usage.estimate(selection, provider: provider).label)")
                    .font(dense ? .system(size: 8) : .caption2).foregroundStyle(CompanionStyle.muted)
            }.frame(height: dense ? 25 : 42, alignment: .topLeading).accessibilityElement(children: .combine)
        }.companionCard(height: dense ? 144 : nil, padding: cardPadding)
    }
    private func ranking(_ title: String, symbol: String, key: KeyPath<AIUsagePoint, String>) -> some View {
        let groups = Dictionary(grouping: points, by: { $0[keyPath: key] }).map { name, values in (name, values.reduce(Int64(0)) { $0 + $1.total }) }.sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: dense ? 6 : 12) {
            Label(title, systemImage: symbol).font(heading)
            if groups.isEmpty { Text("No records for this period").font(detail).foregroundStyle(CompanionStyle.muted) }
            ForEach(Array(groups.prefix(3).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Text(title == "Models" ? modelName(item.0) : item.0).font(dense ? .system(size: 10.5, weight: .medium) : .callout.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { geometry in Capsule().fill(title == "Models" ? CompanionStyle.accent : CompanionStyle.ink).frame(width: max(3, geometry.size.width * Double(item.1) / Double(max(1, groups.first?.1 ?? 1)))) }.frame(width: 64, height: 4)
                    Text(short(item.1)).font(detail).monospacedDigit().foregroundStyle(CompanionStyle.muted).fixedSize()
                }.accessibilityElement(children: .combine)
                .help("\(item.0): \(item.1.formatted()) tokens · \(period.rawValue)")
            }
        }.companionCard(height: rankingHeight, padding: cardPadding)
            .help(title == "Models" && groups.contains(where: { $0.0 == "Unknown model" }) ? "Model not recorded: the source has no model metadata. These tokens remain in totals." : "\(title) · \(period.rawValue)")
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
        return VStack(alignment: .leading, spacing: dense ? 5 : 16) {
            HStack { Label("Activity", systemImage: "square.grid.3x3.fill").font(heading); Spacer(); if provider == .codex, let streak = usage.accountActivity?.summary?.currentStreakDays { Label("\(streak)", systemImage: "flame.fill").font(detail.weight(.medium)).foregroundStyle(.orange) } }
            HStack(alignment: .top, spacing: 22) {
                HStack(spacing: dense ? 3 : 4) {
                    ForEach(0..<13) { week in
                        VStack(spacing: dense ? 3 : 4) {
                            ForEach(0..<7) { day in
                                let date = dates[week * 7 + day], count = values[date] ?? 0
                                RoundedRectangle(cornerRadius: 3).fill(count == 0 ? CompanionStyle.separator.opacity(0.5) : CompanionStyle.edge.opacity(0.25 + 0.75 * Double(count) / Double(max(1, peak))))
                                    .frame(width: dense ? 7 : 12, height: dense ? 7 : 12)
                                    .contentShape(Rectangle())
                                    .onHover { inside in selectedDay = inside ? date : (selectedDay == date ? nil : selectedDay) }
                                    .onTapGesture { selectedDay = date }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { selectedDay = date }
                                    .help("\(date.formatted(date: .abbreviated, time: .omitted)): \(values[date].map { "\($0.formatted()) tokens" } ?? "No record")")
                                    .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), \(values[date].map { "\($0.formatted()) tokens" } ?? "No record")")
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: dense ? 2 : 6) { Text(values.isEmpty ? "—" : short(total)).font(dense ? .system(size: 22, weight: .semibold) : .title.weight(.semibold)); Text("13 weeks").font(detail).foregroundStyle(CompanionStyle.muted); Spacer(minLength: dense ? 4 : 8); Text(values.isEmpty ? "Activity unavailable" : "\(active) active days").font(detail); Text(source).font(dense ? .system(size: 8) : .caption2).foregroundStyle(CompanionStyle.muted) }
                Spacer(minLength: 0)
            }
            Text(selectedDay.map { date in "\(date.formatted(date: .abbreviated, time: .omitted)) · \(values[date].map { "\($0.formatted()) tokens" } ?? "No record")" } ?? "Hover or select a day for its exact usage.")
                .font(detail).foregroundStyle(CompanionStyle.muted).frame(height: dense ? 12 : 18, alignment: .leading)
            if !dense, provider == .codex, let updated = usage.accountUpdatedAt {
                Text("\(usage.accountRefreshFailed ? "Last account reading" : "Account updated") \(updated.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(usage.accountRefreshFailed ? .orange : CompanionStyle.muted)
            }
            if let date = dates.max(by: { (values[$0] ?? 0) < (values[$1] ?? 0) }), peak > 0 {
                HStack { Text("Most intense day"); Spacer(); Text("\(date.formatted(date: .abbreviated, time: .omitted)) · \(short(peak))") }.font(detail).foregroundStyle(CompanionStyle.muted)
            }
        }.companionCard(height: dense ? 144 : nil, padding: cardPadding)
    }
    private func modelName(_ model: String) -> String {
        if model == "Unknown model" { return "Model not recorded" }
        if model.hasPrefix("gpt-") { return "GPT-" + model.dropFirst(4).split(separator: "-").enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }.joined(separator: " ") }
        return model
    }
    private func short(_ value: Int64) -> String { value.formatted(.number.notation(.compactName)) }
}
