import Foundation
import GRDB

nonisolated struct DocumentStore: Sendable {
    let database: AppDatabase

    func insert(_ meta: DocumentMeta) async throws {
        let record = try DocumentRecord(meta, encryption: database.encryption)
        try await database.writer.write { db in
            try record.insert(db)
        }
    }

    func update(_ meta: DocumentMeta) async throws {
        let record = try DocumentRecord(meta, encryption: database.encryption)
        try await database.writer.write { db in
            try record.update(db)
        }
    }

    /// Deleting a document cascades to its chunks (FR-28).
    func delete(_ id: UUID) async throws {
        _ = try await database.writer.write { db in
            try DocumentRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func fetch(_ id: UUID) async throws -> DocumentMeta? {
        let encryption = database.encryption
        return try await database.writer.read { db in
            try DocumentRecord.fetchOne(db, key: id.uuidString)
        }
        .map { try $0.domainValue(encryption: encryption) }
    }

    func fetchAll() async throws -> [DocumentMeta] {
        let encryption = database.encryption
        let records = try await database.writer.read { db in
            try DocumentRecord.order(Column("importedAt").desc).fetchAll(db)
        }
        return try records.map { try $0.domainValue(encryption: encryption) }
    }

    /// Documents visible from a conversation: global ones plus those attached to it (OD-6).
    func fetchVisible(conversationID: UUID?) async throws -> [DocumentMeta] {
        try await fetchAll().filter { doc in
            switch doc.scope {
            case .global: true
            case .conversation(let id): id == conversationID
            }
        }
    }

    func totalCorpusBytes() async throws -> Int64 {
        try await database.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(byteSize), 0) FROM documents") ?? 0
        }
    }

    func deleteAll() async throws {
        _ = try await database.writer.write { db in
            try DocumentRecord.deleteAll(db)
        }
    }

    // MARK: Chunks

    func insertChunks(_ chunks: [Chunk]) async throws {
        let records = try chunks.map { try ChunkRecord($0, encryption: database.encryption) }
        try await database.writer.write { db in
            for record in records {
                try record.insert(db)
            }
        }
    }

    func chunks(forDocuments documentIDs: [UUID]) async throws -> [Chunk] {
        guard !documentIDs.isEmpty else { return [] }
        let encryption = database.encryption
        let keys = documentIDs.map(\.uuidString)
        let records = try await database.writer.read { db in
            try ChunkRecord
                .filter(keys.contains(Column("documentID")))
                .order(Column("ordinal").asc)
                .fetchAll(db)
        }
        return try records.map { try $0.domainValue(encryption: encryption) }
    }
}

private nonisolated struct DocumentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "documents"

    var id: String
    var titleEnc: Data
    var fileNameEnc: Data
    var pageCount: Int
    var byteSize: Int64
    var importedAt: Double
    var scopeKind: String
    var scopeConversationID: String?
    var chunkCount: Int
    var indexState: String

    init(_ meta: DocumentMeta, encryption: EncryptionManager) throws {
        id = meta.id.uuidString
        titleEnc = try encryption.encrypt(meta.title)
        fileNameEnc = try encryption.encrypt(meta.fileName)
        pageCount = meta.pageCount
        byteSize = meta.byteSize
        importedAt = meta.importedAt.timeIntervalSinceReferenceDate
        switch meta.scope {
        case .global:
            scopeKind = "global"
            scopeConversationID = nil
        case .conversation(let conversationID):
            scopeKind = "conversation"
            scopeConversationID = conversationID.uuidString
        }
        chunkCount = meta.chunkCount
        indexState = meta.indexState.rawValue
    }

    func domainValue(encryption: EncryptionManager) throws -> DocumentMeta {
        let scope: DocumentScope = if scopeKind == "conversation", let raw = scopeConversationID, let uuid = UUID(uuidString: raw) {
            .conversation(uuid)
        } else {
            .global
        }
        return DocumentMeta(
            id: UUID(uuidString: id) ?? UUID(),
            title: try encryption.decryptString(titleEnc),
            fileName: try encryption.decryptString(fileNameEnc),
            pageCount: pageCount,
            byteSize: byteSize,
            importedAt: Date(timeIntervalSinceReferenceDate: importedAt),
            scope: scope,
            chunkCount: chunkCount,
            indexState: DocumentIndexState(rawValue: indexState) ?? .failed
        )
    }
}

private nonisolated struct ChunkRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chunks"

    var id: String
    var documentID: String
    var ordinal: Int
    var pageNumber: Int?
    var textEnc: Data
    var embedding: Data

    init(_ chunk: Chunk, encryption: EncryptionManager) throws {
        id = chunk.id.uuidString
        documentID = chunk.documentID.uuidString
        ordinal = chunk.ordinal
        pageNumber = chunk.pageNumber
        textEnc = try encryption.encrypt(chunk.text)
        embedding = FloatVectorCodec.encode(chunk.embedding)
    }

    func domainValue(encryption: EncryptionManager) throws -> Chunk {
        Chunk(
            id: UUID(uuidString: id) ?? UUID(),
            documentID: UUID(uuidString: documentID) ?? UUID(),
            ordinal: ordinal,
            pageNumber: pageNumber,
            text: try encryption.decryptString(textEnc),
            embedding: FloatVectorCodec.decode(embedding)
        )
    }
}
