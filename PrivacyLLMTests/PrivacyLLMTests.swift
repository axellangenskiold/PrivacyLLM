import Foundation
import Testing
@testable import PrivacyLLM

struct DomainTests {
    @Test func messageCodableRoundTrip() throws {
        let original = Message(
            conversationID: UUID(),
            role: .assistant,
            content: "Hello **world**",
            reasoning: "thinking...",
            modelID: "mock-fast-1b",
            stats: GenerationStats(promptTokens: 12, completionTokens: 40, tokensPerSecond: 18.5, firstTokenSeconds: 0.4),
            sources: [SourceAttribution(kind: .web, title: "Example", urlString: "https://example.com")]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded == original)
    }

    @Test func documentScopeCodableRoundTrip() throws {
        let conversationID = UUID()
        for scope in [DocumentScope.global, .conversation(conversationID)] {
            let data = try JSONEncoder().encode(scope)
            let decoded = try JSONDecoder().decode(DocumentScope.self, from: data)
            #expect(decoded == scope)
        }
    }
}

struct MockInferenceServiceTests {
    @Test func streamsTokensThenFinishes() async throws {
        let service = MockInferenceService(tokenDelay: .milliseconds(1))
        try await service.loadModel(spec: .previewFast, directory: URL(filePath: "/tmp"), progress: { _ in })
        let loaded = await service.loadedModel
        #expect(loaded?.id == ModelSpec.previewFast.id)

        let input = PromptInput(messages: [PromptMessage(role: .user, content: "Hello")])
        let stream = await service.generate(input, config: GenerationConfig())

        var text = ""
        var stats: GenerationStats?
        for try await event in stream {
            switch event {
            case .token(let piece): text += piece
            case .finished(let finalStats): stats = finalStats
            }
        }
        #expect(text.contains("Hello"))
        #expect(stats != nil)
        #expect((stats?.completionTokens ?? 0) > 0)
    }

    @Test func respectsMaxTokens() async throws {
        let service = MockInferenceService(tokenDelay: .milliseconds(1))
        var config = GenerationConfig()
        config.sampling.maxTokens = 3
        let stream = await service.generate(
            PromptInput(messages: [PromptMessage(role: .user, content: "Hi")]),
            config: config
        )
        var tokenCount = 0
        for try await event in stream {
            if case .token = event { tokenCount += 1 }
        }
        #expect(tokenCount == 3)
    }

    @Test func cancellationStopsStream() async throws {
        let service = MockInferenceService(tokenDelay: .milliseconds(20))
        let stream = await service.generate(
            PromptInput(messages: [PromptMessage(role: .user, content: "Hello")]),
            config: GenerationConfig()
        )
        var tokenCount = 0
        for try await event in stream {
            if case .token = event {
                tokenCount += 1
                if tokenCount == 2 {
                    await service.cancelGeneration()
                }
            }
        }
        // The full canned reply is far longer; cancellation must cut it short.
        #expect(tokenCount < 20)
    }
}

struct MockModelManagerTests {
    @Test func downloadLifecycle() async throws {
        let manager = MockModelManager(downloadTickDelay: .milliseconds(5))
        await manager.startDownload(ModelSpec.previewFast.id)
        var sawDownloading = false
        for await snapshot in await manager.stateUpdates() {
            guard let state = snapshot.first(where: { $0.id == ModelSpec.previewFast.id }) else { continue }
            if case .downloading = state.phase { sawDownloading = true }
            if state.phase == .downloaded { break }
        }
        #expect(sawDownloading)
        let activeFast = await manager.activeModelID(for: .fast)
        #expect(activeFast == ModelSpec.previewFast.id)
        let directory = await manager.localDirectory(for: ModelSpec.previewFast.id)
        #expect(directory != nil)
    }
}
