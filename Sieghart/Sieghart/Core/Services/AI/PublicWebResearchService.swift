import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct ResearchSource: Codable, Equatable, Sendable {
    let title: String
    let url: URL
    let excerpt: String
}
protocol ResearchProviding: Sendable {
    func research(topic: String, language: String) async throws -> ResearchArtifact
    func research(topic: String, language: String, progress: @escaping @Sendable (String,Double) async -> Void) async throws -> ResearchArtifact
}
extension ResearchProviding {
    func research(topic: String, language: String, progress: @escaping @Sendable (String,Double) async -> Void) async throws -> ResearchArtifact { try await research(topic:topic,language:language) }
}
struct UnavailableResearchProvider: ResearchProviding {
    func research(topic: String, language: String) async throws -> ResearchArtifact { throw ResearchFailure.unavailable }
}
enum ResearchFailure: Error { case unavailable, invalidResponse, noSources }

/// Public search snippets, never manufactured findings. The public RSS endpoint
/// is replaceable through ResearchProviding; no account or private browsing data
/// is read. Failure returns a visible error, not an offline stock artifact.
actor PublicWebResearchService: ResearchProviding {
    private let session: URLSession
    private let pageFetcher: any ResearchPageFetching
    private let summarizer: any ResearchSummarizing
    init(session: URLSession? = nil, pageFetcher: any ResearchPageFetching = PublicResearchPageFetcher(), summarizer: any ResearchSummarizing = AppleResearchSummarizer()) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        self.session = session ?? URLSession(configuration: config)
        self.pageFetcher = pageFetcher; self.summarizer = summarizer
    }
    func research(topic: String, language: String) async throws -> ResearchArtifact {
        try await research(topic:topic,language:language,progress:{_,_ in})
    }
    func research(topic: String, language: String, progress: @escaping @Sendable (String,Double) async -> Void) async throws -> ResearchArtifact {
        guard !topic.isEmpty, topic.count <= 700 else { throw ResearchFailure.invalidResponse }
        let english = language.hasPrefix("en")
        await progress(english ? "Finding sources…" : "Buscando fontes…",0.1)
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [.init(name: "q", value: topic), .init(name: "format", value: "rss"),
            .init(name: "setlang", value: language.hasPrefix("en") ? "en" : "pt-br")]
        var request = URLRequest(url: components.url!)
        request.setValue("Sieghart/1.0 Desktop research", forHTTPHeaderField: "User-Agent")
        var sources: [ResearchSource] = []
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            if (response as? HTTPURLResponse)?.statusCode == 200 { sources = Self.relevant((try? Self.sources(from: data)) ?? [], to: topic) }
        } catch is CancellationError { throw CancellationError() }
        catch { /* Try the encyclopedia source before reporting failure. */ }
        try Task.checkCancellation()
        if sources.count < 2, let encyclopedia = try? await encyclopediaSources(topic: topic, language: language) {
            sources = Self.relevant(encyclopedia + sources, to: topic)
        }
        try Task.checkCancellation()
        guard !sources.isEmpty else { throw ResearchFailure.noSources }
        sources = Array(sources.prefix(5))
        await progress(english ? "Reading public pages…" : "Lendo páginas públicas…",0.3)
        var pages: [ResearchPage] = []
        // Read a bounded number of pages, in order. One provider job owns this
        // work, so cancelling or pausing stops subsequent network requests.
        for source in sources.prefix(3) {
            try Task.checkCancellation()
            do { pages.append(try await pageFetcher.page(for: source)) }
            catch is CancellationError { throw CancellationError() }
            catch { continue }
            await progress(english ? "Read \(pages.count) page(s)…" : "Li \(pages.count) página(s)…",0.3+Double(pages.count)*0.12)
        }
        try Task.checkCancellation()
        await progress(english ? "Comparing sources and preparing citations…" : "Comparando fontes e preparando citações…",0.75)
        if !pages.isEmpty, let answer = try? await summarizer.summarize(topic: topic, pages: pages, language: language),
           ResearchCitationValidation.validate(answer, sourceCount: pages.count) {
            try Task.checkCancellation()
            return ResearchArtifact(topic: topic, title: String(topic.prefix(80)), summary: answer,
                bulletPoints: [], sources: pages.map(\.source), pagesRead: pages.count)
        }
        try Task.checkCancellation()
        return ResearchArtifact(topic: topic, title: english ? "Sources · \(topic.prefix(80))" : "Fontes · \(topic.prefix(80))",
            summary: english ? "I found \(sources.count) references but couldn't complete a cited synthesis. These are search excerpts; open the sources for details." : "Encontrei \(sources.count) referências, mas não consegui concluir uma síntese com citações. Estes são trechos da busca; abra as fontes para consultar o conteúdo completo.",
            bulletPoints: sources.map { "\($0.title): \($0.excerpt)" }, sources: sources, pagesRead: pages.count)
    }
    private func encyclopediaSources(topic: String, language: String) async throws -> [ResearchSource] {
        let locale = language.hasPrefix("en") ? "en" : "pt"
        var url = URLComponents(string: "https://\(locale).wikipedia.org/w/api.php")!
        url.queryItems = [.init(name: "action", value: "query"), .init(name: "generator", value: "search"),
            .init(name: "gsrsearch", value: topic), .init(name: "gsrlimit", value: "4"),
            .init(name: "prop", value: "extracts|info"), .init(name: "exintro", value: "1"),
            .init(name: "explaintext", value: "1"), .init(name: "inprop", value: "url"), .init(name: "format", value: "json")]
        var request = URLRequest(url: url.url!)
        request.setValue("Sieghart/1.0 Desktop educational research", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 800_000 else { throw ResearchFailure.invalidResponse }
        struct Page: Decodable { let title: String; let extract: String?; let fullurl: URL?; let index: Int? }
        struct Query: Decodable { let pages: [String: Page]? }
        struct Result: Decodable { let query: Query? }
        let result = try JSONDecoder().decode(Result.self, from: data)
        return (result.query?.pages?.values.sorted { ($0.index ?? 99) < ($1.index ?? 99) } ?? []).compactMap { page in
            guard let url = page.fullurl, url.scheme == "https", let text = page.extract, !text.isEmpty else { return nil }
            return .init(title: page.title, url: url, excerpt: String(text.prefix(1000)))
        }
    }

    nonisolated static func relevant(_ sources: [ResearchSource], to topic: String) -> [ResearchSource] {
        func words(_ text: String) -> Set<String> {
            let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US"))
            let stop: Set<String> = ["a","o","as","os","de","da","do","das","dos","em","no","na","e","com","um","uma","sobre","para","como","the","of","in","and","on","about","for","how","what","is"]
            return Set(normalized.components(separatedBy: .alphanumerics.inverted).filter { $0.count >= 2 && !stop.contains($0) })
        }
        let query = words(topic)
        guard !query.isEmpty else { return [] }
        var seen: Set<URL> = []
        return sources.enumerated().compactMap { index, source -> (ResearchSource, Int, Int)? in
            guard seen.insert(source.url).inserted else { return nil }
            let score = query.intersection(words(source.title + " " + source.excerpt)).count
            guard score >= max(1, Int(ceil(Double(query.count) * 0.75))) else { return nil }
            return (source, score, index)
        }.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 > $1.1 }.map { $0.0 }
    }
    nonisolated static func sources(from data: Data) throws -> [ResearchSource] {
        guard data.count <= 350_000 else { throw ResearchFailure.invalidResponse }
        let delegate = ResearchRSSParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw ResearchFailure.invalidResponse }
        guard !delegate.sources.isEmpty else { throw ResearchFailure.noSources }
        return delegate.sources
    }
}

private final class ResearchRSSParser: NSObject, XMLParserDelegate {
    var sources: [ResearchSource] = []
    private var inItem = false
    private var field = ""
    private var fields: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" { inItem = true; fields = [:] }
        field = elementName
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem, ["title", "link", "description"].contains(field), (fields[field]?.count ?? 0) < 4000 else { return }
        fields[field, default: ""] += string
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { field = "" }
        guard elementName == "item" else { return }
        inItem = false
        guard sources.count < 5, let raw = fields["link"], let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil,
              !sources.contains(where: { $0.url == url }) else { return }
        let title = clean(fields["title"] ?? "", limit: 200), excerpt = clean(fields["description"] ?? "", limit: 1000)
        guard !title.isEmpty, !excerpt.isEmpty else { return }
        sources.append(.init(title: title, url: url, excerpt: excerpt))
    }
    private func clean(_ text: String, limit: Int) -> String {
        String(text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}
