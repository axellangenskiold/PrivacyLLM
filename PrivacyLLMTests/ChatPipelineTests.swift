import Foundation
import Testing
@testable import PrivacyLLM

struct PromptBuilderTests {
    private func message(_ role: ChatRole, _ content: String, at seconds: Double) -> Message {
        Message(
            conversationID: UUID(),
            role: role,
            content: content,
            createdAt: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }

    @Test func systemPromptComesFirstAndHistoryKeepsOrder() async {
        let builder = PromptBuilder()
        let history = [
            message(.user, "first question", at: 1),
            message(.assistant, "first answer", at: 2),
            message(.user, "second question", at: 3),
        ]
        let input = await builder.build(
            systemPrompt: "Be concise.",
            history: history,
            config: GenerationConfig(contextLength: 4096)
        )
        #expect(input.messages.first == PromptMessage(role: .system, content: "Be concise."))
        #expect(input.messages.dropFirst().map(\.content) == ["first question", "first answer", "second question"])
    }

    @Test func oldHistoryIsDroppedWhenBudgetIsTight() async {
        let builder = PromptBuilder()
        let oldPadding = String(repeating: "x", count: 4000)
        let history = [
            message(.user, oldPadding, at: 1),
            message(.assistant, "short answer", at: 2),
            message(.user, "newest question", at: 3),
        ]
        // Budget: max(256, 1100 - 100) = 1000 tokens ≈ 4000 chars; the old
        // 1000-token message can't fit alongside the newer ones.
        var config = GenerationConfig(contextLength: 1100)
        config.sampling.maxTokens = 100
        let input = await builder.build(systemPrompt: nil, history: history, config: config)
        #expect(input.messages.map(\.content) == ["short answer", "newest question"])
    }

    @Test func newestMessageSurvivesEvenWhenOversized() async {
        let builder = PromptBuilder()
        let huge = String(repeating: "y", count: 100_000)
        let history = [message(.user, huge, at: 1)]
        var config = GenerationConfig(contextLength: 1024)
        config.sampling.maxTokens = 256
        let input = await builder.build(systemPrompt: "sys", history: history, config: config)
        let userMessages = input.messages.filter { $0.role == .user }
        #expect(userMessages.count == 1)
        let kept = userMessages[0].content
        #expect(!kept.isEmpty)
        #expect(kept.count < huge.count)
        #expect(huge.hasSuffix(kept))
    }

    @Test func toolMessagesRideAlongButHistorySystemIsExcluded() async {
        let builder = PromptBuilder()
        let history = [
            message(.system, "stray system in history", at: 0),
            message(.assistant, "<tool_call>…</tool_call>", at: 1),
            message(.tool, "tool output", at: 2),
            message(.user, "hi", at: 3),
        ]
        let input = await builder.build(systemPrompt: "real system", history: history, config: GenerationConfig())
        // The only system message is the one the builder injects itself.
        #expect(input.messages.map(\.role) == [.system, .assistant, .tool, .user])
        #expect(input.messages.first?.content == "real system")
    }

    @Test func attachmentMessagesNeverReachTheModel() async {
        let builder = PromptBuilder()
        let history = [
            message(.user, "read this", at: 1),
            message(.attachment, "lease.pdf", at: 2),
            message(.user, "what's the rent?", at: 3),
        ]
        let input = await builder.build(systemPrompt: nil, history: history, config: GenerationConfig())
        #expect(input.messages.map(\.role) == [.user, .user])
        #expect(!input.messages.map(\.content).contains("lease.pdf"))
    }

    @Test func customTokenCounterDrivesBudgeting() async {
        let builder = PromptBuilder()
        let history = [
            message(.user, String(repeating: "a", count: 200), at: 1),
            message(.assistant, String(repeating: "b", count: 50), at: 2),
            message(.user, String(repeating: "c", count: 10), at: 3),
        ]
        var config = GenerationConfig(contextLength: 512)
        config.sampling.maxTokens = 256
        // 1 token per character: budget 256 fits 10 + 50 but not the 200.
        let input = await builder.build(
            systemPrompt: nil,
            history: history,
            config: config,
            countTokens: { @Sendable text in text.count }
        )
        #expect(input.messages.count == 2)
        #expect(input.messages.map(\.content).contains(String(repeating: "b", count: 50)))
    }
}

struct ThinkStreamParserTests {
    private func run(_ chunks: [String]) -> (reasoning: String, content: String) {
        var parser = ThinkStreamParser()
        var reasoning = ""
        var content = ""
        for chunk in chunks {
            let out = parser.feed(chunk)
            reasoning += out.reasoning
            content += out.content
        }
        let tail = parser.finish()
        reasoning += tail.reasoning
        content += tail.content
        return (reasoning, content)
    }

    @Test func tagsSplitAcrossChunkBoundaries() {
        let result = run(["<thi", "nk>step one ", "and two</th", "ink>\n\nThe answer."])
        #expect(result.reasoning == "step one and two")
        #expect(result.content == "The answer.")
    }

    @Test func plainStreamPassesThrough() {
        let result = run(["Hello", " world", "!"])
        #expect(result.reasoning.isEmpty)
        #expect(result.content == "Hello world!")
    }

    @Test func leadingWhitespaceBeforeTagIsSwallowed() {
        let result = run(["\n\n", "<think>hmm</think>", "ok"])
        #expect(result.reasoning == "hmm")
        #expect(result.content == "ok")
    }

    @Test func emptyThinkBlock() {
        let result = run(["<think>", "</think>", "\n\nAnswer"])
        #expect(result.reasoning.isEmpty)
        #expect(result.content == "Answer")
    }

    @Test func unterminatedThinkFlushesAsReasoning() {
        let result = run(["<think>partial reasoning that never clo"])
        #expect(result.reasoning == "partial reasoning that never clo")
        #expect(result.content.isEmpty)
    }

    @Test func angleBracketContentIsNotMistakenForTag() {
        let result = run(["<p>not a think tag</p> hello"])
        #expect(result.reasoning.isEmpty)
        #expect(result.content == "<p>not a think tag</p> hello")
    }
}

struct ChatOrchestratorTests {
    private func makeFixture(
        downloadedModelIDs: Set<String> = [ModelSpec.previewFast.id],
        scriptedReply: String? = nil
    ) async throws -> (ChatOrchestrator, AppDatabase, Conversation) {
        let database = try AppDatabase.inMemory()
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)
        let orchestrator = ChatOrchestrator(
            inference: MockInferenceService(tokenDelay: .milliseconds(1), scriptedReply: scriptedReply),
            modelManager: MockModelManager(downloadedModelIDs: downloadedModelIDs),
            messageStore: MessageStore(database: database),
            conversationStore: ConversationStore(database: database),
            settingsStore: SettingsStore(database: database)
        )
        return (orchestrator, database, conversation)
    }

    @Test func fullTurnStreamsAndPersistsBothMessages() async throws {
        let (orchestrator, database, conversation) = try await makeFixture(scriptedReply: "Hello from the model")

        var sawUserSaved = false
        var streamed = ""
        var completed: Message?
        let stream = await orchestrator.send(text: "  Hi there  ", conversation: conversation, history: [])
        for await event in stream {
            switch event {
            case .userMessageSaved(let message):
                sawUserSaved = true
                #expect(message.content == "Hi there")
            case .assistantDelta(let piece):
                streamed += piece
            case .assistantReasoningDelta, .toolStarted, .toolFinished:
                break
            case .assistantCompleted(let message):
                completed = message
            case .modelLoadProgress:
                break
            case .turnFailed(let reason, _):
                Issue.record("Unexpected failure: \(reason)")
            }
        }

        #expect(sawUserSaved)
        #expect(streamed == "Hello from the model")
        #expect(completed?.content == "Hello from the model")
        #expect(completed?.modelID == ModelSpec.previewFast.id)
        #expect(completed?.stats?.completionTokens ?? 0 > 0)

        let persisted = try await MessageStore(database: database).fetchAll(conversationID: conversation.id)
        #expect(persisted.map(\.role) == [.user, .assistant])
        #expect(persisted.last?.content == "Hello from the model")
    }

    @Test func failsClearlyWhenNoModelIsDownloaded() async throws {
        let (orchestrator, database, conversation) = try await makeFixture(downloadedModelIDs: [])

        var failureReason: String?
        let stream = await orchestrator.send(text: "Hi", conversation: conversation, history: [])
        for await event in stream {
            if case .turnFailed(let reason, let partial) = event {
                failureReason = reason
                #expect(partial == nil)
            }
        }

        #expect(failureReason != nil)
        let persisted = try await MessageStore(database: database).fetchAll(conversationID: conversation.id)
        #expect(persisted.map(\.role) == [.user])
    }

    @Test func emptyInputDoesNothing() async throws {
        let (orchestrator, database, conversation) = try await makeFixture()
        let stream = await orchestrator.send(text: "   \n ", conversation: conversation, history: [])
        var eventCount = 0
        for await _ in stream { eventCount += 1 }
        #expect(eventCount == 0)
        let persisted = try await MessageStore(database: database).fetchAll(conversationID: conversation.id)
        #expect(persisted.isEmpty)
    }
}
