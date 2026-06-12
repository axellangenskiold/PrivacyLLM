import Foundation
import Testing
@testable import PrivacyLLM

struct RegenerateTests {
    private func makeFixture(scriptedReply: String) async throws -> (ChatOrchestrator, AppDatabase, Conversation) {
        let database = try AppDatabase.inMemory()
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)
        let orchestrator = ChatOrchestrator(
            inference: MockInferenceService(tokenDelay: .milliseconds(1), scriptedReply: scriptedReply),
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            messageStore: MessageStore(database: database),
            conversationStore: ConversationStore(database: database),
            settingsStore: SettingsStore(database: database)
        )
        return (orchestrator, database, conversation)
    }

    @Test func regenerateProducesNewAssistantReply() async throws {
        let (orchestrator, database, conversation) = try await makeFixture(scriptedReply: "regenerated reply")
        let messageStore = MessageStore(database: database)

        // Seed: a user message already persisted (as after deleting a bad reply).
        let userMessage = Message(conversationID: conversation.id, role: .user, content: "Tell me a joke")
        try await messageStore.append(userMessage)

        var completed: Message?
        let stream = await orchestrator.regenerate(conversation: conversation, history: [userMessage])
        for await event in stream {
            if case .assistantCompleted(let message) = event { completed = message }
            if case .turnFailed(let reason, _) = event { Issue.record("Unexpected failure: \(reason)") }
        }

        #expect(completed?.content == "regenerated reply")
        let persisted = try await messageStore.fetchAll(conversationID: conversation.id)
        #expect(persisted.map(\.role) == [.user, .assistant])
        #expect(persisted.last?.content == "regenerated reply")
    }

    @Test func regenerateFailsWithoutTrailingUserMessage() async throws {
        let (orchestrator, _, conversation) = try await makeFixture(scriptedReply: "x")
        var failed = false
        let stream = await orchestrator.regenerate(conversation: conversation, history: [])
        for await event in stream {
            if case .turnFailed = event { failed = true }
        }
        #expect(failed)
    }
}

struct ConversationExporterTests {
    @Test func markdownExportStructure() {
        let conversation = Conversation(title: "Trip ideas")
        let messages = [
            Message(conversationID: conversation.id, role: .user, content: "Where should I go?"),
            Message(
                conversationID: conversation.id,
                role: .assistant,
                content: "Try **Lofoten**.",
                sources: [SourceAttribution(kind: .web, title: "Travel guide", urlString: "https://example.com/guide")]
            ),
        ]
        let markdown = ConversationExporter.markdown(conversation: conversation, messages: messages)
        #expect(markdown.contains("# Trip ideas"))
        #expect(markdown.contains("## You"))
        #expect(markdown.contains("## Assistant"))
        #expect(markdown.contains("Try **Lofoten**."))
        #expect(markdown.contains("[Travel guide](https://example.com/guide)"))
    }

    @Test func plainTextExportSkipsToolMessages() {
        let conversation = Conversation(title: "T")
        let messages = [
            Message(conversationID: conversation.id, role: .user, content: "hi"),
            Message(conversationID: conversation.id, role: .tool, content: "tool noise"),
            Message(conversationID: conversation.id, role: .assistant, content: "hello"),
        ]
        let text = ConversationExporter.plainText(conversation: conversation, messages: messages)
        #expect(text.contains("You:\nhi"))
        #expect(text.contains("Assistant:\nhello"))
        #expect(!text.contains("tool noise"))
    }

    @Test func attachmentsRenderAsAttachedLines() {
        let conversation = Conversation(title: "Lease questions")
        let messages = [
            Message(conversationID: conversation.id, role: .attachment, content: "lease"),
            Message(conversationID: conversation.id, role: .user, content: "what's the rent?"),
            Message(conversationID: conversation.id, role: .assistant, content: "9 500 kr."),
        ]
        let markdown = ConversationExporter.markdown(conversation: conversation, messages: messages)
        #expect(markdown.contains("📎 Attached: lease"))
        let text = ConversationExporter.plainText(conversation: conversation, messages: messages)
        #expect(text.contains("📎 Attached: lease"))
    }
}

@MainActor
struct AttachmentFlowTests {
    /// FR-26/OD-6 follow-up: attaching a PDF leaves a persistent transcript
    /// marker instead of a transient notice.
    @Test func attachPersistsAnAttachmentMessage() async throws {
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
        let viewModel = ChatViewModel(conversation: conversation, environment: environment)

        viewModel.attachDocument(at: URL(fileURLWithPath: "/tmp/lease.pdf"))
        for _ in 0..<300 where viewModel.isIndexingAttachment || viewModel.messages.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.attachmentNotice == nil)
        #expect(viewModel.messages.last?.role == .attachment)
        #expect(viewModel.messages.last?.content == "lease")
        let persisted = try await environment.messageStore.fetchAll(conversationID: conversation.id)
        #expect(persisted.map(\.role) == [.attachment])
        #expect(persisted.first?.sources.first?.kind == .document)
        #expect(persisted.first?.sources.first?.documentID != nil)
    }

    /// A failed import keeps the dismissible notice and persists nothing.
    @Test func failedAttachShowsNoticeOnly() async throws {
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
        let viewModel = ChatViewModel(conversation: conversation, environment: environment)

        viewModel.attachDocument(at: URL(fileURLWithPath: "/tmp/notes.txt"))
        for _ in 0..<300 where viewModel.isIndexingAttachment || viewModel.attachmentNotice == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.attachmentNotice != nil)
        #expect(viewModel.messages.isEmpty)
        let persisted = try await environment.messageStore.fetchAll(conversationID: conversation.id)
        #expect(persisted.isEmpty)
    }
}
