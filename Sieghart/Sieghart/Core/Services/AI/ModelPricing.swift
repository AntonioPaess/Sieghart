import Foundation

// Public numeric price facts, independently parsed from provider documentation.
// No account identifiers, local usage or credentials leave the device.
struct ModelPrice: Codable, Sendable {
    var id: String
    var provider: AIProvider
    var input: String
    var cached: String?
    var creation: String?
    var output: String
    var longInput: String?
    var longCached: String?
    var longCreation: String?
    var longOutput: String?
    var creationLong: String?
    var tier: String?
    var source: String
    var checked: String
    var rates: TokenPrices { rates(long: false) }
    func rates(long: Bool) -> TokenPrices {
        func decimal(_ value: String?) -> Decimal? { value.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
        return TokenPrices(inputUSD: decimal(long ? longInput ?? input : input), outputUSD: decimal(long ? longOutput ?? output : output), cachedInputUSD: decimal(long ? longCached ?? cached : cached), cacheCreationUSD: decimal(long ? longCreation ?? creation : creation))
    }
    var valid: Bool {
        guard let input = rates.inputUSD, let output = rates.outputUSD else { return false }
        let extras = [cached, creation, longInput, longCached, longCreation, longOutput, creationLong].compactMap { $0 }
        return input >= 0 && output >= 0 && input < 10000 && output < 10000 && extras.allSatisfy { Decimal(string: $0).map { $0 >= 0 && $0 < 10000 } ?? false }
    }
}

struct PriceCatalog: Codable, Sendable {
    var entries: [ModelPrice] = []
    var fetched: [AIProvider: Date] = [:]
    static func bundled(bundle: Bundle = .main, file: URL? = nil) -> PriceCatalog {
        guard let url = file ?? bundle.url(forResource: "ModelTokenPrices", withExtension: "json"), let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([ModelPrice].self, from: data) else { return PriceCatalog() }
        return PriceCatalog(entries: entries.filter(\.valid))
    }
    func price(model: String, provider: AIProvider, tier: String? = nil) -> ModelPrice? {
        // Only documented snapshot suffixes may inherit a base price. Internal
        // models (including auto-review) remain unpriced unless documented.
        let base = model.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").last.map(String.init)?.lowercased() ?? model.lowercased()
        let normalized = provider == .claude ? base.replacingOccurrences(of: ".", with: "-") : base
        let speed = tier?.lowercased()
        let requestedTier = speed == "priority" || speed == "fast" ? "fast" : ["flex", "batch", "ultrafast"].contains(speed ?? "") ? speed : nil
        let candidates = entries.filter { $0.provider == provider && $0.tier == requestedTier }
        if let exact = candidates.first(where: { $0.id == normalized }) { return exact }
        return candidates.sorted { $0.id.count > $1.id.count }.first { entry in
            guard normalized.hasPrefix(entry.id + "-") else { return false }
            let suffix = String(normalized.dropFirst(entry.id.count + 1))
            return suffix.range(of: "^(?:[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{8})$", options: .regularExpression) != nil
        }
    }
    static func parse(_ markdown: String, provider: AIProvider, checked: Date = .now) -> [ModelPrice] {
        let day = checked.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        var section: String?, headers: [String] = [], result: [ModelPrice] = []
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("#") {
                if provider == .codex {
                    section = ["Standard", "Fast", "Flex", "Batch", "Ultrafast"].first { line == "### \($0) pricing data" }?.lowercased()
                } else { section = nil }
                headers = []
            }
            guard line.hasPrefix("|"), line.hasSuffix("|") else { continue }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.first == "Model" {
                headers = cells
                if provider == .claude && headers.contains("Base input tokens") { section = "standard" }
                continue
            }
            guard let section, cells.count == headers.count else { continue }
            func value(_ title: String) -> String? {
                guard let index = headers.firstIndex(of: title) else { return nil }
                let text = cells[index]
                guard let range = text.range(of: "\\$[0-9]+(?:\\.[0-9]+)?", options: .regularExpression) else { return nil }
                return String(text[range].dropFirst())
            }
            let name = cells[0].components(separatedBy: " (")[0]
            let id = provider == .codex ? name : name.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ".", with: "-")
            guard id.hasPrefix(provider == .codex ? "gpt-" : "claude-") || (provider == .codex && (id.hasPrefix("o") || id == "davinci-002" || id == "babbage-002")),
                  let input = value(provider == .codex ? "Short context input" : "Base input tokens"),
                  let output = value(provider == .codex ? "Short context output" : "Output tokens") else { continue }
            let price = ModelPrice(id: id, provider: provider, input: input, cached: value(provider == .codex ? "Short context cached input" : "Cache hits and refreshes"), creation: value(provider == .codex ? "Short context cache writes" : "5m cache writes"), output: output, longInput: value("Long context input"), longCached: value("Long context cached input"), longCreation: value("Long context cache writes"), longOutput: value("Long context output"), creationLong: value("1h cache writes"), tier: section == "standard" ? nil : section, source: PricingSource.page(provider).absoluteString, checked: day)
            if price.valid { result.append(price) }
        }
        return result
    }
}

struct TokenEstimate: Sendable {
    var usd: Decimal = 0
    var pricedTokens: Int64 = 0
    var unpricedTokens: Int64 = 0
    var hasValue: Bool { pricedTokens > 0 }
    var isLowerBound: Bool { unpricedTokens > 0 }
    var label: String { hasValue ? (isLowerBound ? "≥ " : "") + usd.formatted(.currency(code: "USD")) : "Estimate unavailable" }
}

struct ExchangeQuote: Codable, Sendable {
    let date: String
    let base: String
    let quote: String
    let rate: Decimal
    var valid: Bool { base.uppercased() == "USD" && quote.uppercased() == "BRL" && rate > 0 && rate < 100 && AIActivityParser.parseDate(date + "T00:00:00Z") != nil }
}

enum PricingSource {
    static func page(_ provider: AIProvider) -> URL { URL(string: provider == .codex ? "https://developers.openai.com/api/docs/pricing" : "https://platform.claude.com/docs/en/about-claude/pricing")! }
    static func fetch(_ provider: AIProvider) async throws -> [ModelPrice] {
        let data = try await download(URL(string: page(provider).absoluteString + ".md")!, limit: 1_000_000)
        guard let text = String(data: data, encoding: .utf8) else { throw CodexUsageError.invalidResponse }
        let prices = PriceCatalog.parse(text, provider: provider)
        // A changed or empty table must never replace a good cached reading.
        guard prices.count >= 5 else { throw CodexUsageError.invalidResponse }
        return prices
    }
    static func exchange() async throws -> ExchangeQuote {
        let data = try await download(URL(string: "https://api.frankfurter.dev/v2/rate/usd/brl")!, limit: 16384)
        let quote = try JSONDecoder().decode(ExchangeQuote.self, from: data)
        guard quote.valid else { throw CodexUsageError.invalidResponse }
        return quote
    }
    private static func download(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("text/markdown, application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= limit else { throw CodexUsageError.invalidResponse }
        return data
    }
}
