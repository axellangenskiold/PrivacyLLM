import Foundation
import GRDB

nonisolated struct ConversationStore: Sendable {
    let database: AppDatabase

    func insert(_ conversation: Conversation) async throws {
        let record = try ConversationRecord(conversation, encryption: database.encryption)
        try await database.writer.write { db in
            try record.insert(db)
        }
    }

    func update(_ conversation: Conversation) async throws {
        let record = try ConversationRecord(conversation, encryption: database.encryption)
        try await database.writer.write { db in
            try record.update(db)
        }
    }

    func delete(_ id: UUID) async throws {
        _ = try await database.writer.write { db in
            try ConversationRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func fetch(_ id: UUID) async throws -> Conversation? {
        let encryption = database.encryption
        return try await database.writer.read { db in
            try ConversationRecord.fetchOne(db, key: id.uuidString)
        }
        .map { try $0.domainValue(encryption: encryption) }
    }

    /// Most recently active first.
    func fetchAll() async throws -> [Conversation] {
        let encryption = database.encryption
        let records = try await database.writer.read { db in
            try ConversationRecord
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
        return try records.map { try $0.domainValue(encryption: encryption) }
    }

    /// Conversations whose title or any message matches `query`.
    ///
    /// Titles and message bodies are encrypted at rest, so there is no SQL to
    /// push this into — everything has to be decrypted to be compared.
    /// ponytail: O(all messages) per search, which is nothing at personal-chat
    /// scale. If it ever drags, the fix is a blind index (store a keyed hash of
    /// each token alongside the ciphertext), not plaintext in the database.
    func search(_ query: String) async throws -> [Conversation] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return try await fetchAll() }
        let all = try await fetchAll()
        let titleMatches = all.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        let matchedIDs = Set(titleMatches.map(\.id))

        let encryption = database.encryption
        let bodyMatchIDs = try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT conversationID, contentEnc FROM messages")
                .compactMap { row -> String? in
                    guard let content = try? encryption.decryptString(row["contentEnc"] as Data),
                          content.localizedCaseInsensitiveContains(needle)
                    else { return nil }
                    return row["conversationID"] as String
                }
        }
        let bodyMatches = Set(bodyMatchIDs.compactMap(UUID.init(uuidString:)))
        return all.filter { matchedIDs.contains($0.id) || bodyMatches.contains($0.id) }
    }

    func deleteAll() async throws {
        _ = try await database.writer.write { db in
            try ConversationRecord.deleteAll(db)
        }
    }
}

private nonisolated struct ConversationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversations"

    var id: String
    var titleEnc: Data
    var systemPromptEnc: Data?
    var createdAt: Double
    var updatedAt: Double

    init(_ conversation: Conversation, encryption: EncryptionManager) throws {
        id = conversation.id.uuidString
        titleEnc = try encryption.encrypt(conversation.title)
        systemPromptEnc = try conversation.systemPrompt.map { try encryption.encrypt($0) }
        // Reference-date intervals are Date's native storage and round-trip exactly.
        createdAt = conversation.createdAt.timeIntervalSinceReferenceDate
        updatedAt = conversation.updatedAt.timeIntervalSinceReferenceDate
    }

    func domainValue(encryption: EncryptionManager) throws -> Conversation {
        Conversation(
            id: UUID(uuidString: id) ?? UUID(),
            title: try encryption.decryptString(titleEnc),
            systemPrompt: try systemPromptEnc.map { try encryption.decryptString($0) },
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt)
        )
    }
}
