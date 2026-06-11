import Foundation
import GRDB

/// The app's single SQLite database. Files carry iOS Data Protection (PR-5);
/// user content columns are additionally AES-GCM encrypted via EncryptionManager,
/// so the raw file never contains readable conversation or document text (TR-21).
nonisolated struct AppDatabase: Sendable {
    let writer: any DatabaseWriter
    let encryption: EncryptionManager

    init(writer: any DatabaseWriter, encryption: EncryptionManager) throws {
        self.writer = writer
        self.encryption = encryption
        try Self.migrator.migrate(writer)
    }

    /// On-disk database in Application Support (DR-3 puts model weights elsewhere).
    static func live() throws -> AppDatabase {
        let fileManager = FileManager.default
        let directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Database", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Files created inside inherit the directory's protection class.
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: directory.path
        )
        let databaseURL = directory.appending(path: "app.sqlite")
        let encryption = try EncryptionManager.keychainBacked()
        do {
            return try AppDatabase(writer: DatabasePool(path: databaseURL.path), encryption: encryption)
        } catch {
            // A corrupt database must not crash-loop the app (NFR-11): start fresh.
            try? fileManager.removeItem(at: databaseURL)
            return try AppDatabase(writer: DatabasePool(path: databaseURL.path), encryption: encryption)
        }
    }

    /// In-memory database for tests, previews, and the mock environment.
    static func inMemory(encryption: EncryptionManager = .ephemeral()) throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue(), encryption: encryption)
    }

    /// Removes every row of user data (FR-40 "reset app" keeps the schema).
    func eraseAllContent() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM messages")
            try db.execute(sql: "DELETE FROM conversations")
            try db.execute(sql: "DELETE FROM chunks")
            try db.execute(sql: "DELETE FROM documents")
            try db.execute(sql: "DELETE FROM egressEvents")
            try db.execute(sql: "DELETE FROM settings")
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "conversations") { t in
                t.primaryKey("id", .text)
                t.column("titleEnc", .blob).notNull()
                t.column("systemPromptEnc", .blob)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(table: "messages") { t in
                t.primaryKey("id", .text)
                t.column("conversationID", .text).notNull().indexed()
                    .references("conversations", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("contentEnc", .blob).notNull()
                t.column("reasoningEnc", .blob)
                t.column("createdAt", .double).notNull()
                t.column("modelID", .text)
                t.column("statsJSON", .text)
                t.column("sourcesEnc", .blob)
            }
            try db.create(table: "documents") { t in
                t.primaryKey("id", .text)
                t.column("titleEnc", .blob).notNull()
                t.column("fileNameEnc", .blob).notNull()
                t.column("pageCount", .integer).notNull()
                t.column("byteSize", .integer).notNull()
                t.column("importedAt", .double).notNull()
                t.column("scopeKind", .text).notNull()
                t.column("scopeConversationID", .text)
                t.column("chunkCount", .integer).notNull()
                t.column("indexState", .text).notNull()
            }
            try db.create(table: "chunks") { t in
                t.primaryKey("id", .text)
                t.column("documentID", .text).notNull().indexed()
                    .references("documents", onDelete: .cascade)
                t.column("ordinal", .integer).notNull()
                t.column("pageNumber", .integer)
                t.column("textEnc", .blob).notNull()
                t.column("embedding", .blob).notNull()
            }
            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("valueJSON", .text).notNull()
            }
            try db.create(table: "egressEvents") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("destinationHost", .text).notNull()
                t.column("detailEnc", .blob).notNull()
                t.column("occurredAt", .double).notNull()
            }
        }
        return migrator
    }
}
