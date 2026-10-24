import Foundation
import MapKit

struct WeatherPlace: Decodable, Sendable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let admin1: String?
    let country: String?
    let feature_code: String?
    var population: Int? = nil
    var country_code: String? = nil
    var admin2: String? = nil
    var isRegion: Bool { feature_code?.hasPrefix("ADM") == true || feature_code?.hasPrefix("PCL") == true }
}

enum WeatherNameMatching {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // Bounded Damerau-Levenshtein handles adjacent transposition in dictation.
    static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(normalized(lhs).prefix(120)), b = Array(normalized(rhs).prefix(120))
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }; for j in 0...b.count { d[0][j] = j }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        for i in 1...a.count { for j in 1...b.count {
            d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1] + (a[i-1] == b[j-1] ? 0 : 1))
            if i > 1, j > 1, a[i-1] == b[j-2], a[i-2] == b[j-1] { d[i][j] = min(d[i][j], d[i-2][j-2]+1) }
        } }
        return d[a.count][b.count]
    }
    static func closest(_ input: String, among places: [WeatherPlace]) -> WeatherPlace? {
        let name = input.components(separatedBy: ",")[0]
        let candidates = places.filter { matches(input, place: $0) }
        let ranked = candidates.map { ($0, nameDistance(input, place: $0)) }.sorted { a, b in
            a.1 == b.1 ? (a.0.population ?? 0) > (b.0.population ?? 0) : a.1 < b.1
        }
        guard let first = ranked.first, first.1 <= (name.count >= 6 ? 2 : 1) else { return nil }
        if let second = ranked.dropFirst().first, first.1 == second.1,
           first.0.country != second.0.country || first.0.admin1 != second.0.admin1 {
            guard (first.0.population ?? 0) >= 2000, (first.0.population ?? 0) > 4 * max(1, second.0.population ?? 0) else { return nil }
        }
        return first.0
    }

    private static let ignored: Set<String> = ["em", "no", "na", "in", "at", "de", "do", "da", "dos", "das", "the", "estado", "state", "pais", "country", "regiao", "region", "distrito", "district"]
    private static func words(_ value: String) -> [String] {
        normalized(value).components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty && !ignored.contains($0) }
    }
    private static let countryAliases: [String: Set<String>] = {
        let locales = ["pt_BR", "en_US", "fr_FR", "es_ES"].map(Locale.init(identifier:))
        var result: [String: Set<String>] = [:]
        for code in Locale.isoRegionCodes {
            let names = Set(([code] + locales.compactMap { $0.localizedString(forRegionCode: code) }).map(normalized))
            for name in names { result[name] = names }
        }
        return result
    }()
    /// Verify the requested name and every qualifier, even when a provider
    /// returns an unrelated first result for a partial interpretation.
    static func matches(_ input: String, place: WeatherPlace) -> Bool {
        guard place.feature_code == nil || place.feature_code!.hasPrefix("PPL") || place.isRegion || place.feature_code == "AREA" else { return false }
        let query = words(input), name = words(place.name)
        guard !query.isEmpty, !name.isEmpty, query.count >= name.count else { return false }
        var metadata = [place.admin1, place.admin2, place.country, place.country_code].compactMap { $0 }
        for country in [place.country, place.country_code].compactMap({ $0 }) {
            metadata += Array(countryAliases[normalized(country)] ?? [])
        }
        let qualifierWords = Set(metadata.flatMap(words)), limit = place.name.count >= 6 ? 2 : 1
        for start in 0...(query.count - name.count) {
            let end = start + name.count
            if distance(query[start..<end].joined(separator: " "), name.joined(separator: " ")) <= limit {
                let qualifiers = Array(query[..<start]) + Array(query[end...])
                if qualifiers.allSatisfy({ qualifierWords.contains($0) }) { return true }
            }
        }
        return false
    }
    private static func nameDistance(_ input: String, place: WeatherPlace) -> Int {
        let query = words(input), count = words(place.name).count
        guard count > 0, query.count >= count else { return 120 }
        return (0...(query.count-count)).map { distance(query[$0..<($0+count)].joined(separator: " "), words(place.name).joined(separator: " ")) }.min() ?? 120
    }
}

/// A named-location search; it never requests or reads the user's location.
@MainActor final class WeatherMapLookup {
    private var search: MKLocalSearch?
    private var cancelGeocoding: (() -> Void)?
    private var continuation: CheckedContinuation<WeatherPlace?, Never>?
    private var timeout: Task<Void, Never>?
    static func resolve(_ name: String, timeoutSeconds: Double = 6) async -> WeatherPlace? {
        let lookup = WeatherMapLookup()
        return await withTaskCancellationHandler {
            await lookup.run(name, timeoutSeconds: timeoutSeconds)
        } onCancel: { Task { @MainActor in lookup.finish(nil) } }
    }
    private func run(_ name: String, timeoutSeconds: Double) async -> WeatherPlace? {
        guard !Task.isCancelled else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            if #available(macOS 26.0, *), let request = MKGeocodingRequest(addressString: name) {
                request.preferredLocale = Locale(identifier: "pt_BR")
                cancelGeocoding = { request.cancel() }
                request.getMapItems { items, _ in
                    Task { @MainActor [weak self] in self?.finish(Self.place(name, items: items ?? [])) }
                }
            } else {
                let request = MKLocalSearch.Request(); request.naturalLanguageQuery = name; request.resultTypes = .address
                let search = MKLocalSearch(request: request); self.search = search
                search.start { response, _ in
                    Task { @MainActor [weak self] in self?.finish(Self.place(name, items: response?.mapItems ?? [])) }
                }
            }
            timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(max(0.1, min(6, timeoutSeconds)))) } catch { return }
                self?.finish(nil)
            }
        }
    }
    private static func place(_ name: String, items: [MKMapItem]) -> WeatherPlace? {
        let places = items.map { item in
            WeatherPlace(name: item.name ?? item.placemark.locality ?? name,
                latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude,
                admin1: item.placemark.administrativeArea, country: item.placemark.country,
                feature_code: item.placemark.locality == nil ? "ADM1" : "PPL", country_code: item.placemark.isoCountryCode)
        }
        return WeatherNameMatching.closest(name, among: places)
    }
    private func finish(_ place: WeatherPlace?) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); timeout = nil; search?.cancel(); search = nil; cancelGeocoding?(); cancelGeocoding = nil
        continuation.resume(returning: place)
    }
}
