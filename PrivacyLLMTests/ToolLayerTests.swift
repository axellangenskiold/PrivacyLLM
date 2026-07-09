import Foundation
import Testing
@testable import PrivacyLLM

struct ToolCallParserTests {
    private func run(_ chunks: [String]) -> (visible: String, calls: [ParsedToolCall]) {
        var parser = ToolCallParser()
        var visible = ""
        var calls: [ParsedToolCall] = []
        for chunk in chunks {
            let out = parser.feed(chunk)
            visible += out.visible
            calls += out.calls
        }
        let tail = parser.finish()
        visible += tail.visible
        calls += tail.calls
        return (visible, calls)
    }

    @Test func validCallSplitAcrossChunks(/* TR-4: valid */) {
        let result = run([
            "Let me check. <tool_c",
            "all>{\"name\": \"calculate\", \"arguments\": {\"expression\": \"2+2\"}}</tool",
            "_call> Done.",
        ])
        #expect(result.visible == "Let me check.  Done.")
        #expect(result.calls.count == 1)
        #expect(result.calls[0].call?.name == "calculate")
        #expect(result.calls[0].call?.argumentsJSON.contains("2+2") == true)
        #expect(result.calls[0].parseError == nil)
    }

    @Test func malformedJSONIsReportedNotCrashed(/* TR-4: malformed */) {
        let result = run(["<tool_call>{not json at all</tool_call>"])
        #expect(result.calls.count == 1)
        #expect(result.calls[0].call == nil)
        #expect(result.calls[0].parseError != nil)
    }

    @Test func missingNameIsAParseError() {
        let result = run(["<tool_call>{\"arguments\": {}}</tool_call>"])
        #expect(result.calls[0].call == nil)
        #expect(result.calls[0].parseError == "missing tool name")
    }

    @Test func unterminatedCallIsReportedOnFinish(/* TR-4: partial */) {
        let result = run(["<tool_call>{\"name\": \"calculate\""])
        #expect(result.calls.count == 1)
        #expect(result.calls[0].call == nil)
        #expect(result.calls[0].parseError == "tool call was never closed")
    }

    @Test func multipleCallsInOneStream() {
        let result = run([
            "<tool_call>{\"name\": \"a\", \"arguments\": {}}</tool_call>",
            "and <tool_call>{\"name\": \"b\", \"arguments\": {}}</tool_call>",
        ])
        #expect(result.calls.map { $0.call?.name } == ["a", "b"])
        #expect(result.visible == "and ")
    }

    @Test func plainTextWithAnglesPassesThrough() {
        let result = run(["a < b and <tools are", " fun>"])
        #expect(result.calls.isEmpty)
        #expect(result.visible == "a < b and <tools are fun>")
    }
}

struct BuiltinToolTests {
    @Test func calculatorEvaluatesExpressions() throws {
        #expect(try ExpressionEvaluator.evaluate("2+2") == 4)
        #expect(try ExpressionEvaluator.evaluate("(12.5 * 4) / 3 - 1") == (12.5 * 4) / 3 - 1)
        #expect(try ExpressionEvaluator.evaluate("2^10") == 1024)
        #expect(try ExpressionEvaluator.evaluate("-3 * -(2+1)") == 9)
        #expect(try ExpressionEvaluator.evaluate("10 % 3") == 1)
    }

    @Test func calculatorRejectsGarbage() {
        #expect(throws: (any Error).self) { try ExpressionEvaluator.evaluate("2 +") }
        #expect(throws: (any Error).self) { try ExpressionEvaluator.evaluate("DROP TABLE") }
        #expect(throws: (any Error).self) { try ExpressionEvaluator.evaluate("1/0") }
        #expect(throws: (any Error).self) { try ExpressionEvaluator.evaluate("(1+2") }
    }

    @Test func calculatorToolFormatsResult() async {
        let output = await CalculatorTool().execute(argumentsJSON: #"{"expression": "6*7"}"#)
        #expect(output.content == "6*7 = 42")
        #expect(!output.isError)
    }

    @Test func unitConversionConverts() async {
        let output = await UnitConversionTool().execute(argumentsJSON: #"{"value": 100, "from": "c", "to": "f"}"#)
        #expect(output.content.contains("212"))
        let crossKind = await UnitConversionTool().execute(argumentsJSON: #"{"value": 1, "from": "kg", "to": "km"}"#)
        #expect(crossKind.isError)
    }

    @Test func dateTimeToolReturnsSomething() async {
        let output = await DateTimeTool().execute(argumentsJSON: "{}")
        #expect(output.content.count > 10)
    }
}

struct ToolRouterTests {
    private func makeRouter(searchEnabled: Bool) async throws -> ToolRouter {
        let database = try AppDatabase.inMemory()
        let settings = SettingsStore(database: database)
        try await settings.set(searchEnabled, for: .searchEnabled)
        struct FakeEgressTool: LocalTool {
            var spec: ToolSpec {
                ToolSpec(name: "web_search", summary: "fake", parametersJSONSchema: "{}", causesEgress: true)
            }

            func execute(argumentsJSON: String) async -> ToolOutput {
                ToolOutput(content: "results!")
            }
        }
        return ToolRouter(tools: [CalculatorTool(), FakeEgressTool()], settingsStore: settings)
    }

    @Test func egressToolsHiddenWhenSearchOff() async throws {
        let router = try await makeRouter(searchEnabled: false)
        #expect(router.specs(includeEgressTools: false).map(\.name) == ["calculate"])
        #expect(router.specs(includeEgressTools: true).map(\.name) == ["calculate", "web_search"])
    }

    @Test func egressToolBlockedAtCallTimeWhenDisabled(/* TL-4 */) async throws {
        let router = try await makeRouter(searchEnabled: false)
        let call = ParsedToolCall(
            call: ToolCall(name: "web_search", argumentsJSON: "{}"),
            rawBlock: ""
        )
        let result = await router.execute(call)
        #expect(result.isError)
        #expect(result.content.contains("disabled"))
    }

    @Test func egressToolRunsWhenEnabled() async throws {
        let router = try await makeRouter(searchEnabled: true)
        let call = ParsedToolCall(call: ToolCall(name: "web_search", argumentsJSON: "{}"), rawBlock: "")
        let result = await router.execute(call)
        #expect(!result.isError)
        #expect(result.content == "results!")
    }

    @Test func unknownToolGetsHelpfulError() async throws {
        let router = try await makeRouter(searchEnabled: false)
        let call = ParsedToolCall(call: ToolCall(name: "nope", argumentsJSON: "{}"), rawBlock: "")
        let result = await router.execute(call)
        #expect(result.isError)
        #expect(result.content.contains("calculate"))
    }
}

struct AgentLoopTests {
    private func makeOrchestrator(replies: [String], database: AppDatabase) -> ChatOrchestrator {
        ChatOrchestrator(
            inference: MockInferenceService(tokenDelay: .milliseconds(1), replies: replies),
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            messageStore: MessageStore(database: database),
            conversationStore: ConversationStore(database: database),
            settingsStore: SettingsStore(database: database)
        )
    }

    @Test func toolCallRoundTripProducesFinalAnswer() async throws {
        let database = try AppDatabase.inMemory()
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)
        let orchestrator = makeOrchestrator(
            replies: [
                "<tool_call>{\"name\": \"calculate\", \"arguments\": {\"expression\": \"6*7\"}}</tool_call>",
                "The answer is 42.",
            ],
            database: database
        )

        var toolStarted: [String] = []
        var completed: Message?
        let stream = await orchestrator.send(text: "What is 6*7?", conversation: conversation, history: [])
        for await event in stream {
            switch event {
            case .toolStarted(let name): toolStarted.append(name)
            case .assistantCompleted(let message): completed = message
            case .turnFailed(let reason, _): Issue.record("failed: \(reason)")
            default: break
            }
        }

        #expect(toolStarted == ["calculate"])
        #expect(completed?.content == "The answer is 42.")
    }

    @Test func loopIsBoundedWhenModelKeepsCallingTools(/* TL-2 */) async throws {
        let database = try AppDatabase.inMemory()
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)
        // The mock repeats the last reply forever: an unbounded loop would never finish.
        let orchestrator = makeOrchestrator(
            replies: ["<tool_call>{\"name\": \"current_datetime\", \"arguments\": {}}</tool_call>"],
            database: database
        )

        var toolRuns = 0
        var finished = false
        let stream = await orchestrator.send(text: "loop forever", conversation: conversation, history: [])
        for await event in stream {
            switch event {
            case .toolStarted: toolRuns += 1
            case .assistantCompleted, .turnFailed: finished = true
            default: break
            }
        }

        #expect(toolRuns == ChatOrchestrator.maxToolRounds)
        #expect(finished)
    }

    @Test func malformedToolCallFeedsErrorBackAndRecovers() async throws {
        let database = try AppDatabase.inMemory()
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)
        let orchestrator = makeOrchestrator(
            replies: [
                "<tool_call>{broken json</tool_call>",
                "Sorry, here is a plain answer.",
            ],
            database: database
        )

        var sawErrorTool = false
        var completed: Message?
        let stream = await orchestrator.send(text: "go", conversation: conversation, history: [])
        for await event in stream {
            switch event {
            case .toolFinished(_, let isError): sawErrorTool = sawErrorTool || isError
            case .assistantCompleted(let message): completed = message
            default: break
            }
        }

        #expect(sawErrorTool)
        #expect(completed?.content == "Sorry, here is a plain answer.")
    }

    /// The orchestrator teaches the model *when* to search: with search on and
    /// web_search registered, the system prompt carries the trigger rules.
    @Test func searchGuidanceInjectedWhenSearchAvailable() async throws {
        let database = try AppDatabase.inMemory()
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)
        let settings = SettingsStore(database: database)
        try await settings.set(true, for: .searchEnabled)
        let mock = MockInferenceService(tokenDelay: .milliseconds(1), scriptedReply: "ok")
        let orchestrator = ChatOrchestrator(
            inference: mock,
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            messageStore: MessageStore(database: database),
            conversationStore: ConversationStore(database: database),
            settingsStore: settings,
            tools: [CalculatorTool(), WebSearchTool(search: MockSearchService())]
        )

        for await _ in await orchestrator.send(text: "who won brazil vs norway?", conversation: conversation, history: []) {}

        let system = await mock.lastInput?.messages.first { $0.role == .system }
        #expect(system?.content.contains("web_search tool") == true)
        #expect(system?.content.contains("unsure") == true)
    }

    /// With search off the guidance flips: no web claim, admit staleness.
    @Test func noWebGuidanceWhenSearchOff() async throws {
        let database = try AppDatabase.inMemory()
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)
        let settings = SettingsStore(database: database)
        try await settings.set(false, for: .searchEnabled)
        let mock = MockInferenceService(tokenDelay: .milliseconds(1), scriptedReply: "ok")
        let orchestrator = ChatOrchestrator(
            inference: mock,
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            messageStore: MessageStore(database: database),
            conversationStore: ConversationStore(database: database),
            settingsStore: settings,
            tools: [CalculatorTool(), WebSearchTool(search: MockSearchService())]
        )

        for await _ in await orchestrator.send(text: "who won brazil vs norway?", conversation: conversation, history: []) {}

        let system = await mock.lastInput?.messages.first { $0.role == .system }
        #expect(system?.content.contains("cannot access the web") == true)
        #expect(system?.content.contains("web_search tool") == false)
    }
}
