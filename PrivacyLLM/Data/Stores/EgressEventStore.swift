import Foundation
import GRDB

/// Local-only log of everything that intentionally left the device (PR-14).
nonisolated struct EgressEventStore: Sendable {
    let database: AppDatabase

    func append(_ event: EgressEvent) async throws {
        let record = try EgressEventRecord(event, encryption: database.encryption)
        try await database.writer.write { db in
            try record.insert(db)
        }
    }

    func recent(limit: Int = 100) async throws -> [EgressEvent] {
        let encryption = database.encryption
        let records = try await database.writer.read { db in
            try EgressEventRecord
                .order(Column("occurredAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
        return try records.map { try $0.domainValue(encryption: encryption) }
    }

    func deleteAll() async throws {
        _ = try await database.writer.write { db in
            try EgressEventRecord.deleteAll(db)
        }
    }
}

private nonisolated struct EgressEventRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "egressEvents"

    var id: String
    var kind: String
    var destinationHost: String
    var detailEnc: Data
    var occurredAt: Double

    init(_ event: EgressEvent, encryption: EncryptionManager) throws {
        id = event.id.uuidString
        kind = event.kind.rawValue
        destinationHost = event.destinationHost
        detailEnc = try encryption.encrypt(event.detail)
        occurredAt = event.occurredAt.timeIntervalSinceReferenceDate
    }

    func domainValue(encryption: EncryptionManager) throws -> EgressEvent {
        EgressEvent(
            id: UUID(uuidString: id) ?? UUID(),
            kind: EgressEvent.Kind(rawValue: kind) ?? .webSearch,
            destinationHost: destinationHost,
            detail: try encryption.decryptString(detailEnc),
            occurredAt: Date(timeIntervalSinceReferenceDate: occurredAt)
        )
    }
}
