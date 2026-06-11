import Foundation
import Testing
@testable import PrivacyLLM

struct VoiceServiceTests {
    @Test func mockStreamsPartialsThenFinal() async throws {
        let service = MockVoiceService(
            script: ["Hello", "Hello there", "Hello there world"],
            partialDelay: .milliseconds(5)
        )
        let stream = try await service.startTranscribing()

        let collector = PartialCollector()
        let consumer = Task {
            for try await transcript in stream {
                switch transcript {
                case .partial(let text): await collector.addPartial(text)
                case .final(let text): await collector.setFinal(text)
                }
            }
        }
        // Wait for at least one partial before stopping (no fixed sleeps).
        for _ in 0..<200 where await collector.partials.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        await service.stopTranscribing()
        try await consumer.value

        #expect(await !collector.partials.isEmpty)
        #expect(await collector.finalText == "Hello there world")
    }

    private actor PartialCollector {
        private(set) var partials: [String] = []
        private(set) var finalText: String?

        func addPartial(_ text: String) { partials.append(text) }
        func setFinal(_ text: String) { finalText = text }
    }
}

@MainActor
struct VoiceInputFlowTests {
    /// TR-10: mocked recognizer → live partials and the final transcript land
    /// in the input field for review, never auto-sent (FR-33/34).
    @Test func transcriptFlowsIntoDraftWithoutSending() async throws {
        let environment = AppEnvironment(
            database: try AppDatabase.inMemory(),
            inference: MockInferenceService(tokenDelay: .milliseconds(1)),
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            search: MockSearchService(),
            documents: MockDocumentService(),
            voice: MockVoiceService(script: ["What is", "What is the weather"], partialDelay: .milliseconds(5))
        )
        let conversation = Conversation()
        try await environment.conversationStore.insert(conversation)
        let viewModel = ChatViewModel(conversation: conversation, environment: environment)

        viewModel.toggleRecording()
        // Wait for recording to start and partials to arrive.
        for _ in 0..<100 where !viewModel.isRecording {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.isRecording)
        for _ in 0..<100 where viewModel.draft.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        viewModel.toggleRecording()
        for _ in 0..<100 where viewModel.isRecording {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.draft == "What is the weather")
        #expect(viewModel.isRecording == false)
        // Review-before-send: nothing was sent (FR-34).
        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.phase == .idle)
    }

    @Test func dictationAppendsToExistingDraft() async throws {
        let environment = AppEnvironment(
            database: try AppDatabase.inMemory(),
            inference: MockInferenceService(tokenDelay: .milliseconds(1)),
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            search: MockSearchService(),
            documents: MockDocumentService(),
            voice: MockVoiceService(script: ["tomorrow"], partialDelay: .milliseconds(5))
        )
        let conversation = Conversation()
        try await environment.conversationStore.insert(conversation)
        let viewModel = ChatViewModel(conversation: conversation, environment: environment)
        viewModel.draft = "Remind me"

        viewModel.toggleRecording()
        for _ in 0..<100 where !viewModel.isRecording {
            try await Task.sleep(for: .milliseconds(10))
        }
        viewModel.toggleRecording()
        for _ in 0..<100 where viewModel.isRecording {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.draft == "Remind me tomorrow")
    }
}
