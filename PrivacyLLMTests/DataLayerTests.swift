import Foundation
import GRDB
import Testing
@testable import PrivacyLLM

struct EncryptionManagerTests {
    @Test func roundTripAndCiphertextIsOpaque() throws {
        let manager = EncryptionManager.ephemeral()
        let plaintext = "Sensitive conversation content åäö 🎉"
        let ciphertext = try manager.encrypt(plaintext)
        #expect(try manager.decryptString(ciphertext) == plaintext)
        #expect(ciphertext.range(of: Data(plaintext.utf8)) == nil)
    }

    @Test func wrongKeyFailsToDecrypt() throws {
        let ciphertext = try EncryptionManager.ephemeral().encrypt("secret")
        #expect(throws: (any Error).self) {
            try EncryptionManager.ephemeral().decrypt(ciphertext)
        }
    }

    @Test func jsonRoundTrip() throws {
        let manager = EncryptionManager.ephemeral()
        let sources = [SourceAttribution(kind: .web, title: "Example", urlString: "https://example.com")]
        let ciphertext = try manager.encryptJSON(sources)
        #expect(try manager.decryptJSON([SourceAttribution].self, from: ciphertext) == sources)
    }
}

struct DataLayerTests {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase.inMemory()
    }

    @Test func conversationCRUDRoundTrip() async throws {
        let database = try makeDatabase()
        let store = ConversationStore(database: database)

        var conversation = Conversation(title: "Trip planning", systemPrompt: "Be terse.")
        try await store.insert(conversation)

        var fetched = try await store.fetch(conversation.id)
        #expect(fetched == conversation)

        conversation.title = "Renamed"
        try await store.update(conversation)
        fetched = try await store.fetch(conversation.id)
        #expect(fetched?.title == "Renamed")

        try await store.delete(conversation.id)
        fetched = try await store.fetch(conversation.id)
        #expect(fetched == nil)
    }

    @Test func messageRoundTripAndOrdering() async throws {
        let database = try makeDatabase()
        let conversations = ConversationStore(database: database)
        let messages = MessageStore(database: database)

        let conversation = Conversation()
        try await conversations.insert(conversation)

        let first = Message(
            conversationID: conversation.id,
            role: .user,
            content: "What is MLX?",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        let second = Message(
            conversationID: conversation.id,
            role: .assistant,
            content: "An array framework.",
            reasoning: "<think>recall docs</think>",
            createdAt: Date(timeIntervalSince1970: 1001),
            modelID: "mock-fast-1b",
            stats: GenerationStats(promptTokens: 10, completionTokens: 5, tokensPerSecond: 20, firstTokenSeconds: 0.3),
            sources: [SourceAttribution(kind: .document, title: "MLX paper", pageNumber: 2)]
        )
        try await messages.append(second)
        try await messages.append(first)

        let fetched = try await messages.fetchAll(conversationID: conversation.id)
        #expect(fetched == [first, second])
    }

    @Test func deletingConversationCascadesToMessages() async throws {
        let database = try makeDatabase()
        let conversations = ConversationStore(database: database)
        let messages = MessageStore(database: database)

        let conversation = Conversation()
        try await conversations.insert(conversation)
        try await messages.append(Message(conversationID: conversation.id, role: .user, content: "hi"))
        try await conversations.delete(conversation.id)

        let remaining = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages") ?? -1
        }
        #expect(remaining == 0)
    }

    @Test func deleteFromRemovesMessageAndSuccessors() async throws {
        let database = try makeDatabase()
        let conversations = ConversationStore(database: database)
        let messages = MessageStore(database: database)

        let conversation = Conversation()
        try await conversations.insert(conversation)
        let timeline = (0..<4).map { index in
            Message(
                conversationID: conversation.id,
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: "m\(index)",
                createdAt: Date(timeIntervalSince1970: Double(2000 + index))
            )
        }
        for message in timeline {
            try await messages.append(message)
        }

        try await messages.deleteFrom(timeline[1])
        let remaining = try await messages.fetchAll(conversationID: conversation.id)
        #expect(remaining == [timeline[0]])
    }

    @Test func documentAndChunkRoundTripWithVectors() async throws {
        let database = try makeDatabase()
        let store = DocumentStore(database: database)

        let meta = DocumentMeta(
            title: "Lease agreement",
            fileName: "lease.pdf",
            pageCount: 12,
            byteSize: 240_000,
            scope: .conversation(UUID()),
            chunkCount: 2,
            indexState: .ready
        )
        try await store.insert(meta)
        let fetched = try await store.fetch(meta.id)
        #expect(fetched == meta)

        let chunks = [
            Chunk(documentID: meta.id, ordinal: 0, pageNumber: 1, text: "Clause one.", embedding: [0.25, -1.5, 3.0]),
            Chunk(documentID: meta.id, ordinal: 1, pageNumber: 2, text: "Clause two.", embedding: [9.75, 0.001, -42]),
        ]
        try await store.insertChunks(chunks)
        let fetchedChunks = try await store.chunks(forDocuments: [meta.id])
        #expect(fetchedChunks == chunks)

        try await store.delete(meta.id)
        let orphans = try await store.chunks(forDocuments: [meta.id])
        #expect(orphans.isEmpty)
    }

    @Test func settingsDefaultsAndRoundTrip() async throws {
        let database = try makeDatabase()
        let settings = SettingsStore(database: database)

        // Search must default to OFF (FR-18).
        #expect(try await settings.searchEnabled() == false)

        try await settings.set(true, for: .searchEnabled)
        #expect(try await settings.searchEnabled() == true)

        var sampling = SamplingParams()
        sampling.temperature = 0.2
        try await settings.set(sampling, for: .sampling)
        #expect(try await settings.sampling() == sampling)
    }

    @Test func egressEventRoundTrip() async throws {
        let database = try makeDatabase()
        let store = EgressEventStore(database: database)
        let event = EgressEvent(kind: .webSearch, destinationHost: "html.duckduckgo.com", detail: "weather stockholm")
        try await store.append(event)
        let recent = try await store.recent()
        #expect(recent == [event])
    }

    @Test func userContentIsNotReadableInDatabaseFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "test.sqlite")

        let marker = "TOP-SECRET-MARKER-9000"
        do {
            let database = try AppDatabase(
                writer: DatabaseQueue(path: databaseURL.path),
                encryption: .ephemeral()
            )
            let conversations = ConversationStore(database: database)
            let messages = MessageStore(database: database)
            let conversation = Conversation(title: marker, systemPrompt: marker)
            try await conversations.insert(conversation)
            try await messages.append(Message(conversationID: conversation.id, role: .user, content: marker))
            try await DocumentStore(database: database).insert(
                DocumentMeta(title: marker, fileName: "\(marker).pdf", pageCount: 1, byteSize: 1)
            )
            try await EgressEventStore(database: database).append(
                EgressEvent(kind: .webSearch, destinationHost: "example.com", detail: marker)
            )
        }

        let raw = try Data(contentsOf: databaseURL)
        #expect(!raw.isEmpty)
        #expect(raw.range(of: Data(marker.utf8)) == nil)
    }
}
