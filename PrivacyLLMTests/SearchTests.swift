import Foundation
import Testing
@testable import PrivacyLLM

private final class FixtureToken {}

private func fixtureHTML(_ name: String) throws -> String {
    let bundle = Bundle(for: FixtureToken.self)
    let url = bundle.url(forResource: name, withExtension: "html")
        ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")
    guard let url else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try String(contentsOf: url, encoding: .utf8)
}

private var duckDuckGoProvider: SearchProvider {
    SearchProviderLoader.load().providers.first { $0.id == "duckduckgo" }!
}

struct SearchParsingTests {
    @Test func parsesSavedDuckDuckGoPage(/* TR-3 */) throws {
        let html = try fixtureHTML("ddg-results")
        let results = try HTMLSearchService.parse(html: html, provider: duckDuckGoProvider, maxResults: 5)
        #expect(results.count == 5)
        #expect(results.allSatisfy { !$0.title.isEmpty })
        #expect(results.allSatisfy { $0.urlString.hasPrefix("http") })
        #expect(results.contains { $0.urlString.contains("swift.org") })
        #expect(results.contains { !$0.snippet.isEmpty })
    }

    @Test func emptyAndMalformedPagesYieldNoResults() throws {
        let empty = try HTMLSearchService.parse(html: "<html><body></body></html>", provider: duckDuckGoProvider, maxResults: 5)
        #expect(empty.isEmpty)
        let garbage = try HTMLSearchService.parse(html: "not html at all >>>", provider: duckDuckGoProvider, maxResults: 5)
        #expect(garbage.isEmpty)
    }

    @Test func blockedMarkerThrows() {
        #expect(throws: SearchError.blockedOrCaptcha) {
            _ = try HTMLSearchService.parse(
                html: "<html><div class=\"anomaly-modal\">prove you are human</div></html>",
                provider: duckDuckGoProvider,
                maxResults: 5
            )
        }
    }

    @Test func duckDuckGoRedirectLinksAreDecoded() throws {
        let html = """
        <div class="result">
            <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpage&rut=abc">Example</a>
            <a class="result__snippet">A snippet.</a>
        </div>
        """
        let results = try HTMLSearchService.parse(html: html, provider: duckDuckGoProvider, maxResults: 5)
        #expect(results.first?.urlString == "https://example.com/page")
    }

    @Test func mojeekProviderParsesItsMarkup() throws {
        let provider = SearchProviderLoader.load().providers.first { $0.id == "mojeek" }!
        let html = """
        <ul class="results-standard">
        <li class="r1"><a title="https://www.swift.org/" href="https://www.swift.org/" class="ob"></a>
        <h2><a class="title" href="https://www.swift.org/">Swift Programming Language</a></h2>
        <p class="s">Swift supports patterns.</p></li>
        </ul>
        """
        let results = try HTMLSearchService.parse(html: html, provider: provider, maxResults: 5)
        #expect(results.count == 1)
        #expect(results[0].title == "Swift Programming Language")
        #expect(results[0].snippet == "Swift supports patterns.")
    }
}

/// Search-specific URL mock — deliberately separate from HFMockURLProtocol so
/// the two serialized suites can't race each other's static fixtures.
private final class SearchMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let body = Self.responses[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Records egress notifications without any UI.
private actor EgressRecorder: EgressReporting {
    private(set) var fired: [(query: String, host: String)] = []
    private(set) var finished = 0

    func searchWillFire(query: String, host: String) {
        fired.append((query, host))
    }

    func searchDidFinish() {
        finished += 1
    }

    func snapshot() -> (fired: [(query: String, host: String)], finished: Int) {
        (fired, finished)
    }
}

@Suite(.serialized)
struct SearchServiceTests {
    @Test func searchFiresEgressExactlyOncePerRequest(/* TR-22 logic */) async throws {
        SearchMockURLProtocol.responses = [
            "https://html.duckduckgo.com/html/?q=weather%20stockholm": Data(try fixtureHTML("ddg-results").utf8),
        ]
        let recorder = EgressRecorder()
        let service = HTMLSearchService(
            provider: duckDuckGoProvider,
            session: HTMLSearchService.makeSession(protocolClasses: [SearchMockURLProtocol.self]),
            egress: recorder
        )
        let results = try await service.search("weather stockholm", maxResults: 3)
        #expect(results.count == 3)
        try? await Task.sleep(for: .milliseconds(100))
        let snapshot = await recorder.snapshot()
        #expect(snapshot.fired.count == 1)
        #expect(snapshot.fired.first?.host == "html.duckduckgo.com")
        #expect(snapshot.fired.first?.query == "weather stockholm")
        #expect(snapshot.finished == 1)
    }

    @Test func networkFailureStillEndsEgress() async throws {
        SearchMockURLProtocol.responses = [:]
        let recorder = EgressRecorder()
        let service = HTMLSearchService(
            provider: duckDuckGoProvider,
            session: HTMLSearchService.makeSession(protocolClasses: [SearchMockURLProtocol.self]),
            egress: recorder
        )
        await #expect(throws: SearchError.self) {
            _ = try await service.search("anything", maxResults: 3)
        }
        try? await Task.sleep(for: .milliseconds(100))
        let snapshot = await recorder.snapshot()
        #expect(snapshot.fired.count == 1)
        #expect(snapshot.finished == 1)
    }
}

struct SearchPipelineTests {
    /// TR-8: model asks for a search → results injected → final answer carries
    /// web citations, all with mocked network.
    @Test func searchAugmentedTurnProducesCitedAnswer() async throws {
        let database = try AppDatabase.inMemory()
        let settings = SettingsStore(database: database)
        try await settings.set(true, for: .searchEnabled)
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)

        let searchTool = WebSearchTool(search: MockSearchService(delay: .milliseconds(1)))
        let orchestrator = ChatOrchestrator(
            inference: MockInferenceService(tokenDelay: .milliseconds(1), replies: [
                "<tool_call>{\"name\": \"web_search\", \"arguments\": {\"query\": \"swift 6 release date\"}}</tool_call>",
                "Swift 6 shipped in 2024, according to Example result one.",
            ]),
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            messageStore: MessageStore(database: database),
            conversationStore: ConversationStore(database: database),
            settingsStore: settings,
            tools: [searchTool]
        )

        var completed: Message?
        let stream = await orchestrator.send(text: "When did Swift 6 ship?", conversation: conversation, history: [])
        for await event in stream {
            if case .assistantCompleted(let message) = event { completed = message }
            if case .turnFailed(let reason, _) = event { Issue.record("failed: \(reason)") }
        }

        #expect(completed?.content.contains("Swift 6 shipped") == true)
        #expect(completed?.sources.isEmpty == false)
        #expect(completed?.sources.allSatisfy { $0.kind == .web } == true)

        // Citations survive persistence (FR-20).
        let persisted = try await MessageStore(database: database).fetchAll(conversationID: conversation.id)
        #expect(persisted.last?.sources.count == completed?.sources.count)
    }

    @Test func searchOffMeansToolIsBlockedAndTurnStillCompletes(/* FR-22 */) async throws {
        let database = try AppDatabase.inMemory()
        let settings = SettingsStore(database: database)
        // searchEnabled defaults to false (FR-18) — not set on purpose.
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)

        let orchestrator = ChatOrchestrator(
            inference: MockInferenceService(tokenDelay: .milliseconds(1), replies: [
                "<tool_call>{\"name\": \"web_search\", \"arguments\": {\"query\": \"x\"}}</tool_call>",
                "I couldn't fetch live results, but from my knowledge…",
            ]),
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            messageStore: MessageStore(database: database),
            conversationStore: ConversationStore(database: database),
            settingsStore: settings,
            tools: [WebSearchTool(search: MockSearchService(delay: .milliseconds(1)))]
        )

        var toolErrored = false
        var completed: Message?
        let stream = await orchestrator.send(text: "What's new?", conversation: conversation, history: [])
        for await event in stream {
            if case .toolFinished(_, let isError) = event { toolErrored = toolErrored || isError }
            if case .assistantCompleted(let message) = event { completed = message }
        }

        #expect(toolErrored)
        #expect(completed?.content.contains("couldn't fetch live results") == true)
        #expect(completed?.sources.isEmpty == true)
    }
}
