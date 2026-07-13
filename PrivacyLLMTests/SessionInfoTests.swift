import Foundation
import Testing
@testable import PrivacyLLM

struct ContextWindowTests {
    /// The on-device window is capped by device RAM and an optional user cap,
    /// and never exceeds the model's own trained window.
    @Test func resolvedContextCapsToRAMAndUserCap() {
        let gb: UInt64 = 1_073_741_824
        let model = ModelSpec.previewThinking // trained window 16384

        // Auto: high-RAM device caps at 8192, low-RAM at 4096.
        #expect(model.resolvedContextLength(userCap: 0, physicalMemoryBytes: 8 * gb) == 8192)
        #expect(model.resolvedContextLength(userCap: 0, physicalMemoryBytes: 4 * gb) == 4096)

        // A user cap lowers it further; a cap above the RAM ceiling can't raise it.
        #expect(model.resolvedContextLength(userCap: 2048, physicalMemoryBytes: 8 * gb) == 2048)
        #expect(model.resolvedContextLength(userCap: 16384, physicalMemoryBytes: 8 * gb) == 8192)

        // Never exceeds the model's own window (8192 model, high RAM → 8192).
        let small = ModelSpec.previewFast
        #expect(small.resolvedContextLength(userCap: 0, physicalMemoryBytes: 8 * gb) == small.contextLength)
    }
}

@MainActor
struct SessionStatsTests {
    /// FR-24: token and web-search counts sum across the conversation, and the
    /// context window/usage are populated from the active model.
    @Test func sessionStatsAggregatesAcrossMessages() async throws {
        let environment = AppEnvironment(
            database: try AppDatabase.inMemory(),
            inference: MockInferenceService(tokenDelay: .milliseconds(1)),
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            search: MockSearchService(),
            documents: MockDocumentService(),
            voice: MockVoiceService()
        )
        let conversation = Conversation()
        try await environment.conversationStore.insert(conversation)
        let store = environment.messageStore
        try await store.append(Message(conversationID: conversation.id, role: .user, content: "hi"))
        try await store.append(Message(
            conversationID: conversation.id, role: .assistant, content: "hello",
            stats: GenerationStats(promptTokens: 10, completionTokens: 5, webSearchCount: 1)
        ))
        try await store.append(Message(
            conversationID: conversation.id, role: .assistant, content: "again",
            stats: GenerationStats(promptTokens: 20, completionTokens: 7, tokensPerSecond: 12.5, webSearchCount: 2)
        ))

        let viewModel = ChatViewModel(conversation: conversation, environment: environment)
        await viewModel.loadMessages()
        let stats = await viewModel.sessionStats()

        #expect(stats.promptTokensTotal == 30)
        #expect(stats.completionTokensTotal == 12)
        #expect(stats.webSearchCount == 3)
        #expect(stats.lastTokensPerSecond == 12.5)
        #expect(stats.contextWindow > 0)
        #expect(stats.contextUsed > 0)
    }
}
