import Foundation

/// Fetches and parses web results from the configured privacy search provider.
/// Implementations must contain the only network call besides model downloads (PR-2)
/// and must be gated by the global search toggle at call time (TL-4).
nonisolated protocol SearchServicing: Sendable {
    func search(_ query: String, maxResults: Int) async throws -> [SearchResult]
}

/// Canned results for simulator, previews, and tests. Never touches the network.
nonisolated struct MockSearchService: SearchServicing {
    var results: [SearchResult]
    var error: SearchError?
    var delay: Duration

    init(results: [SearchResult] = MockSearchService.defaultResults, error: SearchError? = nil, delay: Duration = .milliseconds(400)) {
        self.results = results
        self.error = error
        self.delay = delay
    }

    func search(_ query: String, maxResults: Int) async throws -> [SearchResult] {
        try? await Task.sleep(for: delay)
        if let error { throw error }
        return Array(results.prefix(maxResults))
    }

    static let defaultResults: [SearchResult] = [
        SearchResult(
            title: "Example result one",
            snippet: "A short snippet describing the first mock search result.",
            urlString: "https://example.com/one"
        ),
        SearchResult(
            title: "Example result two",
            snippet: "A short snippet describing the second mock search result.",
            urlString: "https://example.com/two"
        ),
        SearchResult(
            title: "Example result three",
            snippet: "A short snippet describing the third mock search result.",
            urlString: "https://example.com/three"
        ),
    ]
}
