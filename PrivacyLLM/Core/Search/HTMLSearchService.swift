import Foundation
import SwiftSoup

/// Fetches and parses a provider's HTML results page (FR-19). This and the
/// model downloader are the only code paths in the app that touch the
/// network (PR-2); every call is announced through the egress reporter first.
nonisolated struct HTMLSearchService: SearchServicing {
    /// A stable mobile UA keeps the lightweight HTML endpoints cooperative.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    var provider: SearchProvider
    var session: URLSession
    var egress: any EgressReporting

    static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return URLSession(configuration: configuration)
    }

    func search(_ query: String, maxResults: Int) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SearchError.noResults }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: provider.queryURLTemplate.replacingOccurrences(of: "{query}", with: encoded))
        else { throw SearchError.network("bad query") }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        // The indicator turns on before any byte leaves the device (PR-13).
        await egress.searchWillFire(query: trimmed, host: provider.host)
        defer { Task { await egress.searchDidFinish() } }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SearchError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw SearchError.network("no response") }
        guard http.statusCode == 200 else { throw SearchError.blockedOrCaptcha }

        let html = String(decoding: data, as: UTF8.self)
        let results = try Self.parse(html: html, provider: provider, maxResults: maxResults)
        guard !results.isEmpty else { throw SearchError.noResults }
        return results
    }

    /// Pure parsing, separated for fixture tests (TR-3). Never executes any
    /// script — SwiftSoup only reads markup (PR-16).
    static func parse(html: String, provider: SearchProvider, maxResults: Int) throws -> [SearchResult] {
        for marker in provider.blockedMarkers where html.contains(marker) {
            throw SearchError.blockedOrCaptcha
        }
        let document: Document
        do {
            document = try SwiftSoup.parse(html)
        } catch {
            throw SearchError.parseFailure
        }

        var results: [SearchResult] = []
        let elements = (try? document.select(provider.resultSelector)) ?? Elements()
        for element in elements {
            guard results.count < maxResults else { break }
            guard let titleElement = try? element.select(provider.titleSelector).first(),
                  let title = try? titleElement.text(),
                  !title.isEmpty,
                  var href = try? titleElement.attr("href"),
                  !href.isEmpty
            else { continue }
            href = decodeRedirect(href)
            guard href.hasPrefix("https://") || href.hasPrefix("http://") else { continue }
            let snippet = (try? element.select(provider.snippetSelector).first()?.text()) ?? ""
            results.append(SearchResult(title: title, snippet: snippet ?? "", urlString: href))
        }
        return results
    }

    /// DuckDuckGo historically wrapped links as /l/?uddg=<encoded-url>.
    private static func decodeRedirect(_ href: String) -> String {
        guard href.contains("uddg=") else { return href }
        let absolute = href.hasPrefix("//") ? "https:" + href : href
        guard let components = URLComponents(string: absolute),
              let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value
        else { return href }
        return target
    }
}

/// Resolves the user's selected provider on every call, so a settings change
/// applies immediately (FR-23).
nonisolated struct ConfiguredSearchService: SearchServicing {
    var providersFile: SearchProvidersFile
    var settingsStore: SettingsStore
    var session: URLSession
    var egress: any EgressReporting

    init(
        providersFile: SearchProvidersFile = SearchProviderLoader.load(),
        settingsStore: SettingsStore,
        session: URLSession = HTMLSearchService.makeSession(),
        egress: any EgressReporting
    ) {
        self.providersFile = providersFile
        self.settingsStore = settingsStore
        self.session = session
        self.egress = egress
    }

    func search(_ query: String, maxResults: Int) async throws -> [SearchResult] {
        let selectedID: String = (try? await settingsStore.value(
            for: .searchProviderID,
            default: providersFile.defaultProviderID
        )) ?? providersFile.defaultProviderID
        guard let provider = providersFile.providers.first(where: { $0.id == selectedID })
            ?? providersFile.providers.first
        else { throw SearchError.network("no providers configured") }
        let service = HTMLSearchService(provider: provider, session: session, egress: egress)
        return try await service.search(query, maxResults: maxResults)
    }
}
