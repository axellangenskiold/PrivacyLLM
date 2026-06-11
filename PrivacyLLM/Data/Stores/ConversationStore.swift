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
