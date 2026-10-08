import Foundation

// Read only the Claude desktop app's versioned, local percentage history.
// This adapter never requests OAuth credentials or guesses renewal dates.
enum ClaudePlanHistory {
    static func location(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }
    static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser, now: Date = .now) throws -> ClaudeLimitsReport? {
        let url = location(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4_194_304 else { throw UsageImportError("Claude history is too large to read safely.") }
        return try decode(Data(contentsOf: url), now: now)
    }
    static func decode(_ data: Data, now: Date = .now) throws -> ClaudeLimitsReport? {
        guard data.count <= 4_194_304,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = integer(json["version"]), [1, 2].contains(version),
              let samples = json["samples"] as? [[String: Any]] else {
            throw UsageImportError("This Claude history format isn't supported yet.")
        }
        let latest = samples.compactMap { row -> (Date, [String: Any])? in
            guard let milliseconds = number(row["t"]), milliseconds > 0 else { return nil }
            let date = Date(timeIntervalSince1970: milliseconds / 1000)
            guard date <= now.addingTimeInterval(300) else { return nil }
            return (date, version == 1 ? row : (row["u"] as? [String: Any] ?? [:]))
        }.max { $0.0 < $1.0 }
        // A stale sample must not look like a live allowance. Each reading is
        // self-contained, so windows from different organizations never merge.
        guard let (date, values) = latest, now.timeIntervalSince(date) < 1800 else { return nil }
        func window(_ key: String, minutes: Int, scope: String? = nil) -> ClaudeLimitsReport.ReportWindow? {
            guard let used = number(values[key]), (0...100).contains(used) else { return nil }
            return .init(usedPercent: used, windowDurationMins: minutes, resetsAt: nil, scope: scope)
        }
        let primary = window("fh", minutes: 300), secondary = window("sd", minutes: 10080)
        let scoped = [window("so", minutes: 10080, scope: "Opus"), window("sn", minutes: 10080, scope: "Sonnet")].compactMap { $0 }
        guard primary != nil || secondary != nil || !scoped.isEmpty else { return nil }
        return ClaudeLimitsReport(capturedAt: date, primary: primary, secondary: secondary, scoped: scoped)
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let value = number(value), value.rounded() == value, abs(value) < 100 else { return nil }
        return Int(value)
    }
}

struct UsageImportError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum ChargeFile {
    private struct Envelope: Codable { let version: Int; let charges: [Entry] }
    private struct Entry: Codable {
        let reference: String; let provider: String; let date: String
        let amount: String; let currency: String; let kind: String
    }
    static let csvTemplate = "reference,provider,date,amount,currency,kind\ninvoice-001,codex,2026-10-01,20.00,USD,Subscription\n"
    static func decode(_ data: Data, csv: Bool, source: String, now: Date = .now) throws -> [RecordedCharge] {
        guard !data.isEmpty, data.count <= 2_097_152 else { throw UsageImportError("Choose a charge file smaller than 2 MB.") }
        let entries: [Entry]
        if csv {
            guard let text = String(data: data, encoding: .utf8) else { throw UsageImportError("Use a UTF-8 CSV file.") }
            var rows = try csvRows(text.replacingOccurrences(of: "\u{feff}", with: ""))
            guard rows.first == ["reference", "provider", "date", "amount", "currency", "kind"] else { throw UsageImportError("Use the six columns in the charge template, in the same order.") }
            rows.removeFirst()
            entries = try rows.filter { $0 != [""] }.map { row in
                guard row.count == 6 else { throw UsageImportError("Every charge must have six columns.") }
                return Entry(reference: row[0], provider: row[1], date: row[2], amount: row[3], currency: row[4], kind: row[5])
            }
        } else {
            let envelope: Envelope
            do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
            catch { throw UsageImportError("Use the documented charge JSON format or the CSV template.") }
            guard envelope.version == 1 else { throw UsageImportError("Unsupported charge file version.") }
            entries = envelope.charges
        }
        guard !entries.isEmpty, entries.count <= 5000 else { throw UsageImportError("Import between 1 and 5,000 charges at a time.") }
        return try entries.enumerated().map { index, entry in
            guard !entry.reference.isEmpty, entry.reference.count <= 160,
                  entry.reference.rangeOfCharacter(from: .controlCharacters) == nil,
                  let provider = AIProvider(rawValue: entry.provider.lowercased()),
                  let currency = SpendCurrency(rawValue: entry.currency.uppercased()),
                  let kind = SpendKind.allCases.first(where: { $0.rawValue.lowercased() == entry.kind.lowercased() }),
                  entry.amount.range(of: #"^[0-9]+(?:\.[0-9]{1,8})?$"#, options: .regularExpression) != nil,
                  let amount = Decimal(string: entry.amount, locale: Locale(identifier: "en_US_POSIX")), amount > 0, amount < 1_000_000_000,
                  let date = parseDate(entry.date), date.timeIntervalSince1970 > 0, date <= now.addingTimeInterval(86400) else {
                throw UsageImportError("Charge \(index + 1) has an invalid reference, provider, date, amount, currency or type. Nothing was imported.")
            }
            return RecordedCharge(provider: provider, date: date, amount: amount, currency: currency, kind: kind, externalID: entry.reference, source: String(source.prefix(200)))
        }
    }
    static func additions(_ imported: [RecordedCharge], existing: [RecordedCharge]) throws -> [RecordedCharge] {
        var known: [String: RecordedCharge] = [:]
        for charge in existing { if let key = key(charge) { known[key] = charge } }
        var additions: [RecordedCharge] = []
        for charge in imported {
            guard charge.externalID != nil, let key = key(charge) else { throw UsageImportError("Each imported charge needs a stable reference.") }
            if let old = known[key] {
                guard old.amount == charge.amount, old.currency == charge.currency, old.kind == charge.kind, abs(old.date.timeIntervalSince(charge.date)) < 0.001 else {
                    throw UsageImportError("Reference \(charge.externalID ?? "") conflicts with an existing charge. Nothing was imported.")
                }
            } else { known[key] = charge; additions.append(charge) }
        }
        return additions
    }
    static func export(_ charges: [RecordedCharge]) throws -> Data {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let entries = charges.map { charge in
            Entry(reference: charge.externalID ?? "manual-\(charge.id.uuidString)", provider: charge.provider.rawValue, date: formatter.string(from: charge.date), amount: NSDecimalNumber(decimal: charge.amount).stringValue, currency: charge.currency.rawValue, kind: charge.kind.rawValue)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(version: 1, charges: entries))
    }
    private static func key(_ charge: RecordedCharge) -> String? { charge.provider.rawValue + ":" + (charge.externalID ?? "manual-\(charge.id.uuidString)") }
    private static func parseDate(_ text: String) -> Date? {
        if let date = AIActivityParser.parseDate(text) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        // Date-only invoices belong to the user's local billing day. UTC
        // midnight could move October 1 into September's monthly total.
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date)
    }
    // Small RFC 4180 reader: quoted commas/newlines and escaped quotes are
    // accepted; malformed quoting rejects the entire batch before persistence.
    private static func csvRows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, endedQuote = false
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let c = text[cursor], next = text.index(after: cursor)
            if quoted {
                if c == "\"" {
                    if next < text.endIndex, text[next] == "\"" { field.append("\""); cursor = text.index(after: next); continue }
                    quoted = false; endedQuote = true
                } else { field.append(c) }
            } else if c == "," { row.append(field); field = ""; endedQuote = false }
            else if c == "\n" || c == "\r\n" || c == "\r" { row.append(field); rows.append(row); row = []; field = ""; endedQuote = false }
            else if c == "\"", field.isEmpty, !endedQuote { quoted = true }
            else {
                guard !endedQuote, c != "\"" else { throw UsageImportError("Malformed CSV quoting. Nothing was imported.") }
                field.append(c)
            }
            cursor = next
            guard rows.count <= 5001, field.utf8.count <= 8192 else { throw UsageImportError("The CSV exceeds the charge import limits.") }
        }
        guard !quoted else { throw UsageImportError("An unfinished quoted CSV field was found.") }
        if !field.isEmpty || !row.isEmpty || endedQuote { row.append(field); rows.append(row) }
        return rows
    }
}
