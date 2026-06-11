import Foundation

nonisolated struct SearchResult: Hashable, Codable, Sendable {
    var title: String
    var snippet: String
    var urlString: String
}

nonisolated enum SearchError: Error, Sendable, Equatable {
    /// The global search toggle is off; no query may leave the device.
    case searchDisabled
    case network(String)
    case blockedOrCaptcha
    case parseFailure
    case noResults
}
