import SwiftUI
import UniformTypeIdentifiers

@MainActor enum AIProviderResources { static var bundle = Bundle.main }

struct ProviderMark: View {
    let provider: AIProvider
    var size: CGFloat = 30
    var body: some View {
        Image(provider.assetName, bundle: AIProviderResources.bundle).resizable().renderingMode(.template).scaledToFit()
            .foregroundStyle(provider == .codex ? CompanionStyle.accentInk : Color(red: 0.85, green: 0.53, blue: 0.39))
            .padding(size * 0.18).frame(width: size, height: size)
            .background(CompanionStyle.background, in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}

struct AIUsageSummary: View {
    @Environment(\.workspaceGlass) private var workspace
    @EnvironmentObject private var usage: AIUsageModel
    @EnvironmentObject private var codex: CodexUsageModel
    @EnvironmentObject private var notch: NotchWidgetController
    var compact = false
    var onOpen: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let provider = usage.usedProviders(codex: codex).first { ProviderMark(provider: provider) }
                else { Image(systemName: "chart.bar.xaxis").font(.title3).foregroundStyle(CompanionStyle.accentInk) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI limits").font(.headline)
                    Text("Usage, resets & spending").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                ForEach(usage.usedProviders(codex: codex).dropFirst()) { ProviderMark(provider: $0, size: 24) }
            }
            if codex.enabled, let bucket = codex.bucket {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array([bucket.primary, bucket.secondary].compactMap { $0 }.enumerated()), id: \.offset) { _, window in
                            HStack {
                                Text(window.title).font(.caption)
                                Spacer()
                                Text(window.remainingPercent(at: context.date).map { "\($0)% left" } ?? "Refresh due")
                                    .font(.caption.weight(.semibold)).foregroundStyle(CompanionStyle.accentInk)
                            }
                            if let reset = window.resetDate {
                                Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(CompanionStyle.muted)
                            }
                        }
                    }
                }
            }
            Button("View AI limits") { if let onOpen { onOpen() } else { notch.showAILimits() } }
                .buttonStyle(CompanionButtonStyle()).focusEffectDisabled()
        }.modifier(AISummarySurface(workspace: workspace, compact: compact))
            .task(id: codex.enabled) { await codex.refreshWhileVisible() }
    }
}

private struct AISummarySurface: ViewModifier {
    let workspace: Bool
    let compact: Bool
    func body(content: Content) -> some View {
        if workspace { content.companionCard() }
        else { content.padding(compact ? 14 : 20).background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 16)) }
    }
}

struct AIUsageDetailsView: View {
    @EnvironmentObject private var codex: CodexUsageModel
    @EnvironmentObject private var usage: AIUsageModel
    @State private var editingProvider: AIProvider?
    @State private var importing = false
    @State private var importError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CodexUsageView()
            if codex.enabled { tokenCard(.codex) }
            claudeCard
            if usage.claudeEnabled { tokenCard(.claude) }
            Text("Quota percentages describe your subscription limits. Token estimates and recorded charges are separate amounts.")
                .font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
        .task(id: "\(codex.enabled)-\(usage.claudeEnabled)") {
            await usage.refresh(codexEnabled: codex.enabled)
            await usage.refreshPricing(providers: AIProvider.allCases.filter { $0 == .codex ? codex.enabled : usage.claudeEnabled })
        }
        .sheet(item: $editingProvider) { provider in UsageSettingsView(provider: provider).environmentObject(usage) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size < 65_536 else { throw CodexUsageError.invalidResponse }
                try usage.importClaudeReport(Data(contentsOf: url)); importError = nil
            } catch { importError = "Choose a valid, dated Claude limits report. See the README for its format." }
        }
    }

    private var claudeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProviderMark(provider: .claude)
                Text("Claude Code limits").font(.headline)
                Spacer()
                if usage.claudeEnabled {
                    Button { usage.disable(.claude, codex: codex) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("Disconnect Claude usage")
                }
            }
            if usage.claudeEnabled {
                if let report = usage.claudeReport {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        VStack(alignment: .leading, spacing: 10) {
                            if let window = report.primary { QuotaWindowView(window: window.window, now: context.date) }
                            if let window = report.secondary { QuotaWindowView(window: window.window, now: context.date) }
                        }
                    }
                    Text("Imported report · \(report.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(CompanionStyle.muted)
                } else {
                    Text("Limits unavailable").font(.callout.weight(.medium))
                    Text("Claude’s local session logs contain tokens, not subscription quotas. Import a dated report to show those limits.")
                        .font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Import limits report") { importing = true }
                        .buttonStyle(CompanionButtonStyle()).focusEffectDisabled()
                    if usage.claudeReport != nil {
                        Button("Remove report") { usage.clearClaudeReport() }.buttonStyle(.plain).font(.caption).focusEffectDisabled()
                    }
                }
            } else {
                Text("Connect to read token counters from your local Claude Code sessions.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                Button("Connect local Claude Code") { usage.claudeEnabled = true }
                    .buttonStyle(CompanionButtonStyle()).focusEffectDisabled()
            }
            if let importError { Text(importError).font(.caption).foregroundStyle(.orange) }
        }.padding(20).background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tokenCard(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(provider.title) · Tokens & spending").font(.callout.weight(.semibold))
                Spacer()
                Button { Task { await usage.refresh(codexEnabled: codex.enabled) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).focusEffectDisabled().disabled(usage.isRefreshing).accessibilityLabel("Refresh local token counters")
            }
            if let tokens = usage.tokens[provider] {
                HStack(spacing: 20) {
                    tokenValue("Input", tokens.input)
                    tokenValue("Output", tokens.output)
                    tokenValue("Cache read", tokens.cachedInput)
                }
                if tokens.cacheCreation > 0 { Text("Cache write: \(tokens.cacheCreation.formatted())").font(.caption).foregroundStyle(CompanionStyle.muted) }
                Text("Recent local sessions · \(tokens.sessions) found · Partial local history")
                    .font(.caption2).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(usage.isRefreshing ? "Reading local counters…" : "No local token counters found")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            Divider().overlay(CompanionStyle.separator)
            HStack(alignment: .firstTextBaseline) {
                Text("Recorded this month").font(.caption)
                Spacer()
                Text(recordedMoney(provider)).font(.callout.weight(.semibold)).monospacedDigit()
            }
            Text("Charges you entered · Subscription + API").font(.caption2).foregroundStyle(CompanionStyle.muted)
            HStack(alignment: .firstTextBaseline) {
                Text("Token estimate").font(.caption)
                Spacer()
                Text(estimateMoney(provider)).font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(.mint)
            }
            Text(usage.pricingDescription(provider) + " · Partial local history · Not a bill")
                .font(.caption2).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
            if let date = usage.conversionDate {
                Text("BRL reference rate: \(date.formatted(date: .abbreviated, time: .omitted)) · \(usage.ledger.customExchangeRate == true ? "Custom rate" : "Frankfurter")")
                    .font(.caption2).foregroundStyle(CompanionStyle.muted)
            }
            Button("Prices & recorded charges") { editingProvider = provider }
                .buttonStyle(CompanionButtonStyle()).focusEffectDisabled()
        }.padding(20).background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func tokenValue(_ label: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(CompanionStyle.muted)
            Text(value.formatted()).font(.title3.weight(.medium)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func recordedMoney(_ provider: AIProvider) -> String {
        let values = SpendCurrency.allCases.compactMap { currency in
            usage.ledger.recorded(provider, currency: currency, month: .now).map { money($0, currency) }
        }
        return values.isEmpty ? "Not recorded" : values.joined(separator: " · ")
    }
    private func estimateMoney(_ provider: AIProvider) -> String {
        let estimate = usage.estimate(usage.analytics.points, provider: provider)
        guard estimate.hasValue else { return "—" }
        if let rate = usage.conversionRate { return estimate.label + " · " + (estimate.isLowerBound ? "≥ " : "") + money(estimate.usd * rate, .BRL) }
        return estimate.label
    }
}

private func money(_ amount: Decimal, _ currency: SpendCurrency) -> String {
    let formatter = NumberFormatter(); formatter.numberStyle = .currency
    formatter.locale = Locale(identifier: currency == .USD ? "en_US" : "pt_BR"); formatter.currencyCode = currency.rawValue
    return formatter.string(from: amount as NSDecimalNumber) ?? "—"
}

private struct UsageSettingsView: View {
    let provider: AIProvider
    @EnvironmentObject private var usage: AIUsageModel
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
@State private var output = ""
@State private var cacheRead = ""
@State private var cacheWrite = ""
@State private var exchange = ""
    @State private var amount = ""
    @State private var currency = SpendCurrency.USD
    @State private var kind = SpendKind.subscription
    @State private var date = Date.now
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { ProviderMark(provider: provider); Text("\(provider.title) spending").font(.title3.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.buttonStyle(CompanionButtonStyle()) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Automatic model prices").font(.headline)
                    Text(usage.pricingDescription(provider)).font(.caption).foregroundStyle(CompanionStyle.muted)
                    Link("Official price source", destination: PricingSource.page(provider)).font(.caption)
                    Button("Use automatic prices & exchange rate") { usage.useAutomaticPrices(provider) }.buttonStyle(CompanionButtonStyle())
                    Text("Optional custom average USD prices per 1M tokens").font(.headline)
                    rateField("Input", text: $input); rateField("Output", text: $output)
                    rateField("Cache read", text: $cacheRead); rateField("Cache write", text: $cacheWrite)
                    Text("Optional cache prices fall back to the input price. Use an average for your models; this remains an estimate.")
                        .font(.caption).foregroundStyle(CompanionStyle.muted)
                    rateField("1 USD in BRL", text: $exchange)
                    Text("Leave empty to use the automatic dated USD/BRL reference rate.").font(.caption).foregroundStyle(CompanionStyle.muted)
                    Button("Save custom prices") { savePrices() }.buttonStyle(CompanionButtonStyle(primary: true))
                    Divider()
                    Text("Record an actual charge").font(.headline)
                    HStack { TextField("Amount", text: $amount); Picker("Currency", selection: $currency) { ForEach(SpendCurrency.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 130) }
                    HStack { Picker("Type", selection: $kind) { ForEach(SpendKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; DatePicker("Date", selection: $date, displayedComponents: .date) }
                    Button("Add charge") {
                        guard let value = decimal(amount), value > 0, value < 1_000_000_000 else { invalid = true; return }
                        usage.record(RecordedCharge(provider: provider, date: date, amount: value, currency: currency, kind: kind)); amount = ""; invalid = false
                    }.buttonStyle(CompanionButtonStyle())
                    Text("Enter a charge from your invoice or subscription. Sieghart does not connect to billing accounts.").font(.caption).foregroundStyle(CompanionStyle.muted)
                    ForEach(usage.ledger.charges.filter { $0.provider == provider }.reversed()) { charge in
                        HStack {
                            VStack(alignment: .leading) { Text("\(charge.kind.rawValue) · \(money(charge.amount, charge.currency))"); Text(charge.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(CompanionStyle.muted) }
                            Spacer(); Button { usage.removeCharge(id: charge.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).accessibilityLabel("Remove recorded charge")
                        }.font(.callout)
                    }
                    if invalid { Text("Use nonnegative prices and a positive amount or exchange rate.").font(.caption).foregroundStyle(.orange) }
                }.textFieldStyle(.roundedBorder)
            }
        }.padding(24).frame(width: 520, height: 650).background(CompanionStyle.background).foregroundStyle(CompanionStyle.ink)
            .onAppear {
                let prices = usage.ledger.prices[provider]
                input = prices?.inputUSD.map { "\($0)" } ?? ""; output = prices?.outputUSD.map { "\($0)" } ?? ""
                cacheRead = prices?.cachedInputUSD.map { "\($0)" } ?? ""; cacheWrite = prices?.cacheCreationUSD.map { "\($0)" } ?? ""
                exchange = usage.ledger.customExchangeRate == true ? usage.ledger.usdToBRL.map { "\($0)" } ?? "" : ""
            }
    }
    private func rateField(_ name: String, text: Binding<String>) -> some View { HStack { Text(name).font(.callout); Spacer(); TextField("Optional", text: text).frame(width: 160) } }
    private func decimal(_ text: String) -> Decimal? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, cleaned.range(of: "^[0-9]+(?:\\.[0-9]{1,8})?$", options: .regularExpression) != nil else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
    private func savePrices() {
        let entries = [input, output, cacheRead, cacheWrite, exchange]
        guard entries.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty || decimal($0) != nil }),
              exchange.isEmpty || (decimal(exchange) ?? 0) > 0 else { invalid = true; return }
        usage.savePrices(TokenPrices(inputUSD: decimal(input), outputUSD: decimal(output), cachedInputUSD: decimal(cacheRead), cacheCreationUSD: decimal(cacheWrite)), provider: provider, exchangeRate: decimal(exchange)); invalid = false
    }
}
