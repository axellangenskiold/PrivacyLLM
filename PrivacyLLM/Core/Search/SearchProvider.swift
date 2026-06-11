import Foundation

/// A scrape-based search provider described entirely by data (FR-23, NFR-22):
/// swapping or fixing a provider is a JSON edit, not a code change.
nonisolated struct SearchProvider: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var displayName: String
    var host: String
    /// "{query}" is replaced with the percent-encoded query.
    var queryURLTemplate: String
    var resultSelector: String
    var titleSelector: String
    var snippetSelector: String
    /// Substrings that indicate a block/captcha page rather than results.
    var blockedMarkers: [String]
}

nonisolated struct SearchProvidersFile: Codable, Sendable {
    var version: Int
    var defaultProviderID: String
    var providers: [SearchProvider]
}

nonisolated enum SearchProviderLoader {
    static func load(bundle: Bundle = .main) -> SearchProvidersFile {
        guard let url = bundle.url(forResource: "SearchProviders", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SearchProvidersFile.self, from: data)
        else {
            return SearchProvidersFile(version: 0, defaultProviderID: "duckduckgo", providers: [])
        }
        return file
    }
}
