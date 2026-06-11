import Foundation
import GRDB

nonisolated struct MessageStore: Sendable {
    let database: AppDatabase

    /// Inserts the message and bumps the conversation's `updatedAt` in one transaction.
    func append(_ message: Message) async throws {
        let record = try MessageRecord(message, encryption: database.encryption)
        let conversationID = message.conversationID.uuidString
        let timestamp = message.createdAt.timeIntervalSinceReferenceDate
        try await database.writer.write { db in
            try record.insert(db)
            try db.execute(
                sql: "UPDATE conversations SET updatedAt = ? WHERE id = ?",
                arguments: [timestamp, conversationID]
            )
        }
    }

    func update(_ message: Message) async throws {
        let record = try MessageRecord(message, encryption: database.encryption)
        try await database.writer.write { db in
            try record.update(db)
        }
    }

    func delete(_ ids: [UUID]) async throws {
        let keys = ids.map(\.uuidString)
        _ = try await database.writer.write { db in
            try MessageRecord.deleteAll(db, keys: keys)
        }
    }

    /// Removes `message` and everything after it in the conversation (FR-4 edit-and-rerun).
    func deleteFrom(_ message: Message) async throws {
        let conversationID = message.conversationID.uuidString
        let cutoff = message.createdAt.timeIntervalSinceReferenceDate
        let id = message.id.uuidString
        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM messages WHERE conversationID = ? AND (createdAt > ? OR id = ?)",
                arguments: [conversationID, cutoff, id]
            )
        }
    }

    func fetchAll(conversationID: UUID) async throws -> [Message] {
        let encryption = database.encryption
        let key = conversationID.uuidString
        let records = try await database.writer.read { db in
            try MessageRecord
                .filter(Column("conversationID") == key)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
        return try records.map { try $0.domainValue(encryption: encryption) }
    }
}

private nonisolated struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    var id: String
    var conversationID: String
    var role: String
    var contentEnc: Data
    var reasoningEnc: Data?
    var createdAt: Double
    var modelID: String?
    var statsJSON: String?
    var sourcesEnc: Data?

    init(_ message: Message, encryption: EncryptionManager) throws {
        id = message.id.uuidString
        conversationID = message.conversationID.uuidString
        role = message.role.rawValue
        contentEnc = try encryption.encrypt(message.content)
        reasoningEnc = try message.reasoning.map { try encryption.encrypt($0) }
        createdAt = message.createdAt.timeIntervalSinceReferenceDate
        modelID = message.modelID
        statsJSON = try message.stats.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        sourcesEnc = message.sources.isEmpty ? nil : try encryption.encryptJSON(message.sources)
    }

    func domainValue(encryption: EncryptionManager) throws -> Message {
        Message(
            id: UUID(uuidString: id) ?? UUID(),
            conversationID: UUID(uuidString: conversationID) ?? UUID(),
            role: ChatRole(rawValue: role) ?? .assistant,
            content: try encryption.decryptString(contentEnc),
            reasoning: try reasoningEnc.map { try encryption.decryptString($0) },
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            modelID: modelID,
            stats: try statsJSON.map { try JSONDecoder().decode(GenerationStats.self, from: Data($0.utf8)) },
            sources: try sourcesEnc.map { try encryption.decryptJSON([SourceAttribution].self, from: $0) } ?? []
        )
    }
}
