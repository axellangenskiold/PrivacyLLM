import Foundation

/// The model's gateway to the web (FR-19). Only registered behind the global
/// search toggle, re-checked at call time by the router (TL-4); the query is
/// whatever keywords the model distilled — never raw conversation text (PR-3).
nonisolated struct WebSearchTool: LocalTool {
    private struct Arguments: Decodable {
        var query: String
    }

    let search: any SearchServicing
    var maxResults = 5

    var spec: ToolSpec {
        ToolSpec(
            name: "web_search",
            summary: "Searches the web for current or factual information. The query must be short keywords, not full sentences. Cite the sources you use.",
            parametersJSONSchema: #"{"type":"object","properties":{"query":{"type":"string","description":"Search keywords"}},"required":["query"]}"#,
            causesEgress: true
        )
    }

    func execute(argumentsJSON: String) async -> ToolOutput {
        guard let arguments = decodeArguments(Arguments.self, from: argumentsJSON),
              !arguments.query.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return ToolOutput(content: "Missing \"query\" argument.", isError: true)
        }
        do {
            let results = try await search.search(arguments.query, maxResults: maxResults)
            let listing = results.enumerated().map { index, result in
                "\(index + 1). \(result.title)\n\(result.snippet)\nURL: \(result.urlString)"
            }
            .joined(separator: "\n\n")
            let sources = results.map {
                SourceAttribution(kind: .web, title: $0.title, urlString: $0.urlString)
            }
            return ToolOutput(
                content: "Search results for \"\(arguments.query)\":\n\n\(listing)\n\nAnswer using these results and mention which sources you used.",
                sources: sources
            )
        } catch {
            // Graceful failure (FR-22): the model answers locally and says so.
            let reason: String = switch error as? SearchError {
            case .blockedOrCaptcha: "the search provider blocked the request"
            case .noResults: "no results were found"
            case .searchDisabled: "search is disabled"
            case .parseFailure: "the results could not be read"
            case .network(let detail): "a network problem (\(detail))"
            case nil: error.localizedDescription
            }
            return ToolOutput(
                content: "Web search failed: \(reason). Answer from your own knowledge and tell the user that live results were unavailable.",
                isError: true
            )
        }
    }
}
