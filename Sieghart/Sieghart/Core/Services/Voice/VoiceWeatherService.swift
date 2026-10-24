import Foundation

struct VoiceWeatherQuery: Equatable, Sendable {
    let city: String?
    let future: Bool

    static func parse(_ question: String, previousCity: String? = nil, expectsLocation: Bool = false) -> Self? {
        let text = SearchVoiceParser.requestText(question).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Recent weather alone does not make every short utterance a place.
        // Bare names answer an explicit location question; ellipses need a
        // continuation marker so a new explanation retains its own intent.
        let locationContinuation = text.range(of: #"^(?:e|and|what about)\s+"#, options: .regularExpression) != nil
        let locationText = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "?!.")))
            .replacingOccurrences(of: #"^(?:e|and|what about)\s+(?:(?:em|no|na|in|at)\s+)?"#, with: "", options: .regularExpression)
        let shortLocation = locationText.range(of: #"^[\p{L}][\p{L}\s,.’'\-]{1,100}$"#, options: .regularExpression) != nil && locationText.split(separator: " ").count <= 5
        let isCourtesyOrAction = locationText.range(of: #"^(?:obrigad\w*|muito obrigad\w*|valeu|ok|sim|nao|yes|no|thanks|thank|pare|stop|cancele|cancel|sieg|siri|oi|ola|hello|me|eu|voce|i|you|pode|poderia|consegue|continu\w*|vamos|entao|o que|fa[cz]\w*|crie|desenh\w*|leia|traduz\w*|abre|abra|ativ\w*|expli\w*|explain\w*|draw\w*|sketch\w*|read|translate|tell|teach|open|enable|disable|como|qual|what|how)\b"#, options: .regularExpression) != nil
        if (expectsLocation || (previousCity != nil && locationContinuation)), shortLocation, !isCourtesyOrAction,
           text.range(of: #"\b(?:tempo|clima|weather|temperatura|temperature|chov\w*|rain\w*|frio|cold|quente|hot)\b"#, options: .regularExpression) == nil {
            return .init(city: locationText, future: false)
        }
        let weatherWords = #"\b(?:temperatura|temperature|tempo|clima|weather|degrees|graus|chov\w*|chuva|rain\w*|frio|calor|nev\w*|snow\w*|quente|ensolarado|nublado|cold|hot|sunny)\b"#
        let followup = previousCity != nil && text.range(of: #"^(?:e\s+(?:em|no|na)|and\s+(?:in|at)|what about|e\s+(?:la|ai))\b"#, options: .regularExpression) != nil
        guard followup || text.range(of: weatherWords, options: .regularExpression) != nil,
              text.range(of: #"\b(?:mac|pc|computador|cpu|gpu|processador|bateria|pomodoro|timer|duracao|cozimento|viagem)\b"#, options: .regularExpression) == nil,
              text.range(of: #"^(?:o que e|como funciona|explique|explica|what is a|how does)\b"#, options: .regularExpression) == nil else { return nil }
        var city: String?
        let patterns = [
            #"\b(?:temperatura|temperature|tempo|clima|weather)\s+(?:atual\s+)?(?:d[aeo]|of|for)\s+(.+)$"#,
            #"\b(?:em|no|na|in|at)\s+(.+)$"#,
            #"^(?:e\s+|and\s+)?what about\s+(.+)$"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) {
                city = String(text[range]); break
            }
        }
        if let value = city {
            city = value.replacingOccurrences(of: #"^(?:a\s+)?(?:cidade|city)\s+(?:d[ae]|of)\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+(?:agora|hoje|atualmente|amanha|now|today|tomorrow|por favor|please|(?:nesse|neste)(?: exato)? momento|no momento)\b.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "?!.,")))
        }
        if let value = city, ["la", "ai", "there", "aqui", "here"].contains(value) { city = nil }
        let future = text.range(of: #"\b(?:amanha|tomorrow|semana|week|ontem|yesterday)\b"#, options: .regularExpression) != nil
        // An ellipsis may reuse a verified location, never its old weather values.
        let refersBack = followup || text.range(of: #"\b(?:la|ai|there|nessa cidade|nesta cidade|that city)\b"#, options: .regularExpression) != nil
        return .init(city: city.flatMap { $0.isEmpty ? nil : $0 } ?? (refersBack ? previousCity : nil), future: future)
    }
}

struct VoiceWeatherObservation: Equatable, Sendable {
    let location: String
    let temperature: Double
    let feelsLike: Double
    let date: Date
    let timezone: String
    let code: Int?
    let isDay: Bool
    var regionEstimate = false

    var symbol: String {
        switch code ?? -1 {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }

    func condition(language: String) -> String {
        let en = language.hasPrefix("en")
        switch code ?? -1 {
        case 0: return en ? "Clear" : "Céu limpo"
        case 1, 2: return en ? "Partly cloudy" : "Parcialmente nublado"
        case 3: return en ? "Overcast" : "Nublado"
        case 45, 48: return en ? "Fog" : "Nevoeiro"
        case 51...57: return en ? "Drizzle" : "Garoa"
        case 61...67, 80...82: return en ? "Rain" : "Chuva"
        case 71...77, 85, 86: return en ? "Snow" : "Neve"
        case 95...99: return en ? "Thunderstorms" : "Trovoadas"
        default: return en ? "Current estimate" : "Estimativa atual"
        }
    }
}

struct VoiceWeatherReport: Equatable, Sendable {
    let reply: String
    let observation: VoiceWeatherObservation?
    func spokenReply(language: String) -> String {
        guard let observation else { return reply }
        let en = language.hasPrefix("en"), name = observation.location.components(separatedBy: ",")[0]
        let temperature = Int(observation.temperature.rounded()), feels = Int(observation.feelsLike.rounded())
        let result = en ? "In \(name), it is \(temperature) degrees Celsius and feels like \(feels). \(observation.condition(language: language))." : "Em \(name), está \(temperature) graus, com sensação de \(feels). \(observation.condition(language: language))."
        return result + (observation.regionEstimate ? (en ? " This is a regional reference point; weather varies locally." : " É uma referência regional; o clima varia conforme a cidade.") : "")
    }
}

protocol VoiceWeatherProviding: Sendable {
    func reply(to query: VoiceWeatherQuery) async throws -> String
    func report(to query: VoiceWeatherQuery, language: String) async throws -> VoiceWeatherReport
}

extension VoiceWeatherProviding {
    func report(to query: VoiceWeatherQuery, language: String) async throws -> VoiceWeatherReport {
        .init(reply: try await reply(to: query), observation: nil)
    }
}

/// Current model estimates from Open-Meteo. No browser, location permission,
/// API key or language-model guess is needed for a named city's temperature.
struct VoiceWeatherService: VoiceWeatherProviding {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    private let now: @Sendable () -> Date
    private let resolvesWithMaps: Bool

    init(transport: Transport? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.resolvesWithMaps = transport == nil
        self.transport = transport ?? { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
        }
        self.now = now
    }

    func reply(to query: VoiceWeatherQuery) async throws -> String {
        try await report(to: query, language: "pt-BR").reply
    }

    func report(to query: VoiceWeatherQuery, language: String) async throws -> VoiceWeatherReport {
        let en = language.hasPrefix("en")
        guard let city = query.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty, city.count <= 120 else { return .init(reply: en ? "Which city's temperature would you like?" : "De qual cidade você quer saber a temperatura?", observation: nil) }
        guard !query.future else { return .init(reply: en ? "I can check current conditions. Ask about the weather now in \(city)." : "Por enquanto consigo consultar a temperatura atual. Pergunte como está o tempo agora em \(city).", observation: nil) }
        let deadline = ContinuousClock.now + .seconds(12)
        var resolved: Place?
        // Speech recognition often omits the comma between city and region.
        // Keep every word: never silently drop an unrecognized qualifier.
        for name in Self.geocodingNames(for: city) {
            try Task.checkCancellation()
            let locations: Locations = try await get("https://geocoding-api.open-meteo.com/v1/search", items: [
                .init(name: "name", value: name), .init(name: "count", value: "30"), .init(name: "language", value: en ? "en" : "pt")
            ], deadline: deadline)
            if let place = WeatherNameMatching.closest(city, among: locations.results ?? []),
               place.latitude.isFinite, place.longitude.isFinite,
               (-90...90).contains(place.latitude), (-180...180).contains(place.longitude) {
                resolved = place
                break
            }
        }
        if resolved == nil {
            let pieces = city.split(separator: ",", maxSplits: 1).map(String.init)
            let base = pieces[0].trimmingCharacters(in: .whitespaces)
            if base.count >= 5 {
                let qualifier = pieces.count > 1 ? "," + pieces[1] : ""
                let nearby: Locations = try await get("https://geocoding-api.open-meteo.com/v1/search", items: [
                    .init(name: "name", value: String(base.prefix(4)) + qualifier), .init(name: "count", value: "100"), .init(name: "language", value: en ? "en" : "pt")
                ], deadline: deadline)
                resolved = WeatherNameMatching.closest(city, among: nearby.results ?? [])
            }
        }
        if resolvesWithMaps, resolved == nil || (!city.contains(",") && (resolved?.population ?? 0) < 2000) {
            let remaining = ContinuousClock.now.duration(to: deadline).secondsValue
            if remaining > 0.2, let mapped = await WeatherMapLookup.resolve(city, timeoutSeconds: remaining), resolved == nil || mapped.isRegion { resolved = mapped }
        }
        try Task.checkCancellation()
        guard let place = resolved, place.latitude.isFinite, place.longitude.isFinite,
            (-90...90).contains(place.latitude), (-180...180).contains(place.longitude) else {
            return .init(reply: en ? "I couldn't find that location. Try another spelling. A country or region is optional and can help distinguish places." : "Não encontrei essa localidade. Tente outra grafia. Estado ou país são opcionais e ajudam se houver lugares com o mesmo nome.", observation: nil)
        }
        let weather: Forecast = try await get("https://api.open-meteo.com/v1/forecast", items: [
            .init(name: "latitude", value: String(place.latitude)), .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            .init(name: "temperature_unit", value: "celsius"), .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"), .init(name: "forecast_days", value: "1")
        ], deadline: deadline)
        let current = weather.current
        guard current.temperature_2m.isFinite, current.apparent_temperature.isFinite,
              (-100...65).contains(current.temperature_2m),
              (-150...100).contains(current.apparent_temperature),
              abs(now().timeIntervalSince1970 - current.time) <= 10_800 else { throw URLError(.cannotParseResponse) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: en ? "en_US" : "pt_BR")
        guard let timezone = TimeZone(identifier: weather.timezone) else { throw URLError(.cannotParseResponse) }
        formatter.timeZone = timezone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: Date(timeIntervalSince1970: current.time))
        let location = [place.name, place.admin1, place.country].compactMap { $0 }.joined(separator: ", ")
        let observation = VoiceWeatherObservation(location: location, temperature: current.temperature_2m,
            feelsLike: current.apparent_temperature, date: Date(timeIntervalSince1970: current.time),
            timezone: weather.timezone, code: current.weather_code, isDay: current.is_day != 0, regionEstimate: place.isRegion)
        let temperature = Int(current.temperature_2m.rounded()), feels = Int(current.apparent_temperature.rounded())
        let reply = en
            ? "According to Open-Meteo, the estimated temperature in \(location) is \(temperature) degrees Celsius and feels like \(feels). \(observation.condition(language: language)). Updated at \(time), local time."
            : "Segundo a Open-Meteo, em \(location) a temperatura estimada é de \(temperature) graus Celsius, com sensação de \(feels) graus. \(observation.condition(language: language)). Dados das \(time), no horário local."
        let regionNote = place.isRegion ? (en ? " This is an estimate for a reference point in this region; conditions vary by city." : " É uma estimativa para um ponto dessa região; o clima varia entre as cidades.") : ""
        return .init(reply: reply + regionNote, observation: observation)
    }

    static func geocodingNames(for city: String) -> [String] {
        let clean = city.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ",.;?!")))
        guard !clean.isEmpty, clean.count <= 120 else { return [] }
        var names = [clean]
        let qualified = clean.replacingOccurrences(of: #"\s+(?:no estado d[eo]|no distrito d[eo]|na regiao d[eo]|in the state of|in the district of|em|no|na|in)\s+"#,
            with: ", ", options: [.regularExpression, .caseInsensitive])
        if qualified != clean { names.append(qualified) }
        let explicitParts = qualified.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if explicitParts.count > 1 {
            if clean.contains(","), explicitParts.count == 2 { names.append(explicitParts.reversed().joined(separator: ", ")) }
            // Searching the name alone is useful, but acceptance still checks
            // every original qualifier against the returned metadata.
            names.append(explicitParts[0]); names.append(explicitParts[explicitParts.count - 1])
        }
        if clean.contains(",") {
            let parts = clean.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count == 2 { names.append(parts.reversed().joined(separator: ", ")) }
        } else {
            let words = clean.split(separator: " ").map(String.init)
            if (2...8).contains(words.count) {
                // Longer city names get a chance before shorter prefixes.
                for split in stride(from: words.count - 1, through: 1, by: -1) {
                    names.append(words[..<split].joined(separator: " ") + ", " + words[split...].joined(separator: " "))
                }
                if words.count == 2 { names.append(words.reversed().joined(separator: ", ")) }
            }
        }
        var unique: [String] = []
        for name in names where !unique.contains(name) { unique.append(name) }
        return Array(unique.prefix(7))
    }

    private func get<T: Decodable>(_ endpoint: String, items: [URLQueryItem], deadline: ContinuousClock.Instant) async throws -> T {
        try Task.checkCancellation()
        let remaining = ContinuousClock.now.duration(to: deadline).secondsValue
        guard remaining > 0 else { throw URLError(.timedOut) }
        var parts = URLComponents(string: endpoint)!
        parts.queryItems = items
        var request = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: min(4, remaining))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result: (Data, HTTPURLResponse)
        do { result = try await transport(request) }
        catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
            // A cold connection can time out while the system falls back from
            // QUIC. Retry once, retaining the same bounded request and task.
            try Task.checkCancellation()
            let remaining = ContinuousClock.now.duration(to: deadline).secondsValue
            guard remaining > 0.2 else { throw URLError(.timedOut) }
            request.timeoutInterval = min(4, remaining)
            result = try await transport(request)
        }
        let (data, response) = result
        try Task.checkCancellation()
        guard response.statusCode == 200, data.count <= 512_000 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct Locations: Decodable { let results: [Place]? }
    private typealias Place = WeatherPlace
    private struct Forecast: Decodable {
        let timezone: String
        let current: Current
        struct Current: Decodable {
            let time: Double
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int?
            let is_day: Int?
        }
    }
}

private extension Duration {
    var secondsValue: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
