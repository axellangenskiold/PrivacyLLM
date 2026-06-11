import Foundation
import Testing
@testable import PrivacyLLM

struct DataControlsTests {
    @Test func eraseAllContentEmptiesEveryTable(/* FR-40 */) async throws {
        let database = try AppDatabase.inMemory()
        let conversations = ConversationStore(database: database)
        let messages = MessageStore(database: database)
        let documentStore = DocumentStore(database: database)
        let settings = SettingsStore(database: database)
        let egress = EgressEventStore(database: database)

        let conversation = Conversation()
        try await conversations.insert(conversation)
        try await messages.append(Message(conversationID: conversation.id, role: .user, content: "hello"))
        let meta = DocumentMeta(title: "Doc", fileName: "d.pdf", pageCount: 1, byteSize: 1)
        try await documentStore.insert(meta)
        try await documentStore.insertChunks([Chunk(documentID: meta.id, ordinal: 0, text: "x", embedding: [1])])
        try await settings.set(true, for: .searchEnabled)
        try await egress.append(EgressEvent(kind: .webSearch, destinationHost: "h", detail: "q"))

        try await database.eraseAllContent()

        #expect(try await conversations.fetchAll().isEmpty)
        #expect(try await documentStore.fetchAll().isEmpty)
        #expect(try await documentStore.chunks(forDocuments: [meta.id]).isEmpty)
        #expect(try await egress.recent().isEmpty)
        // Settings fall back to safe defaults — search returns to OFF (FR-18).
        #expect(try await settings.searchEnabled() == false)
    }

    @Test func clearConversationsLeavesDocumentsIntact() async throws {
        let database = try AppDatabase.inMemory()
        let conversations = ConversationStore(database: database)
        let documentStore = DocumentStore(database: database)

        try await conversations.insert(Conversation())
        try await documentStore.insert(DocumentMeta(title: "Keep", fileName: "k.pdf", pageCount: 1, byteSize: 1))

        try await conversations.deleteAll()

        #expect(try await conversations.fetchAll().isEmpty)
        #expect(try await documentStore.fetchAll().count == 1)
    }
}
