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
    private func makeViewModel(script: [String]) async throws -> ChatViewModel {
        let environment = AppEnvironment(
            database: try AppDatabase.inMemory(),
            inference: MockInferenceService(tokenDelay: .milliseconds(1)),
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            search: MockSearchService(),
            documents: MockDocumentService(),
            voice: MockVoiceService(script: script, partialDelay: .milliseconds(5))
        )
        let conversation = Conversation()
        try await environment.conversationStore.insert(conversation)
        return ChatViewModel(conversation: conversation, environment: environment)
    }

    /// TR-10 / FR-34: the finished transcript is held for review (never
    /// auto-sent), then sends on demand.
    @Test func transcriptHeldForReviewThenSends() async throws {
        let viewModel = try await makeViewModel(script: ["What is", "What is the weather"])

        viewModel.startVoiceRecording()
        try await until { viewModel.isRecording }
        try await until { !viewModel.liveTranscript.isEmpty }

        viewModel.finishVoiceRecording()
        try await until { !viewModel.isRecording }

        #expect(viewModel.pendingVoiceTranscript == "What is the weather")
        #expect(viewModel.draft.isEmpty)
        #expect(viewModel.messages.isEmpty) // nothing sent yet (FR-34)

        viewModel.sendVoiceTranscript()
        #expect(viewModel.pendingVoiceTranscript == nil)
        try await until { viewModel.messages.contains { $0.role == .user } }
        #expect(viewModel.messages.first(where: { $0.role == .user })?.content == "What is the weather")
    }

    @Test func dictationAppendsToExistingDraft() async throws {
        let viewModel = try await makeViewModel(script: ["tomorrow"])
        viewModel.draft = "Remind me"

        viewModel.startVoiceRecording()
        try await until { viewModel.isRecording }
        viewModel.finishVoiceRecording()
        try await until { !viewModel.isRecording }

        #expect(viewModel.pendingVoiceTranscript == "Remind me tomorrow")
    }

    /// FR-33: a pause in speech auto-stops dictation with no manual tap.
    @Test func silenceAutoStopsRecording() async throws {
        let viewModel = try await makeViewModel(script: ["a", "ab", "abc"])
        viewModel.silenceTimeout = .milliseconds(80)

        viewModel.startVoiceRecording()
        try await until { !viewModel.isRecording && viewModel.pendingVoiceTranscript != nil }

        #expect(viewModel.pendingVoiceTranscript == "abc")
    }

    @Test func cancelDiscardsTranscript() async throws {
        let viewModel = try await makeViewModel(script: ["a", "ab", "abc"])

        viewModel.startVoiceRecording()
        try await until { viewModel.isRecording }
        try await until { !viewModel.liveTranscript.isEmpty }
        viewModel.cancelVoiceRecording()
        try await until { !viewModel.isRecording }

        #expect(viewModel.pendingVoiceTranscript == nil)
        #expect(viewModel.draft.isEmpty)
    }

    /// Polls until `condition` holds or times out — no fixed sleeps.
    private func until(_ condition: () -> Bool, timeout: Duration = .seconds(3)) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if start.duration(to: .now) > timeout { break }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
