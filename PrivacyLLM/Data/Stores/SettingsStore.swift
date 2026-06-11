import Foundation
import GRDB

nonisolated enum SettingsKey: String, Sendable {
    case searchEnabled
    case searchProviderID
    case globalSystemPrompt
    case sampling
    case contextLength
    case thinkingEnabled
    case activeFastModelID
    case activeThinkingModelID
    case activeRole
    case appearance
    case hasCompletedOnboarding
}

nonisolated struct SettingsStore: Sendable {
    let database: AppDatabase

    func value<T: Codable & Sendable>(for key: SettingsKey, default defaultValue: T) async throws -> T {
        let raw = try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT valueJSON FROM settings WHERE key = ?", arguments: [key.rawValue])
        }
        guard let raw else { return defaultValue }
        return (try? JSONDecoder().decode(T.self, from: Data(raw.utf8))) ?? defaultValue
    }

    func set(_ value: some Codable & Sendable, for key: SettingsKey) async throws {
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO settings (key, valueJSON) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET valueJSON = excluded.valueJSON",
                arguments: [key.rawValue, json]
            )
        }
    }

    func remove(_ key: SettingsKey) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [key.rawValue])
        }
    }

    // MARK: Typed conveniences

    /// Search is opt-in: the default must stay false (FR-18).
    func searchEnabled() async throws -> Bool {
        try await value(for: .searchEnabled, default: false)
    }

    func sampling() async throws -> SamplingParams {
        try await value(for: .sampling, default: SamplingParams())
    }

    func contextLength() async throws -> Int {
        try await value(for: .contextLength, default: 4096)
    }

    func globalSystemPrompt() async throws -> String? {
        let stored: String = try await value(for: .globalSystemPrompt, default: "")
        return stored.isEmpty ? nil : stored
    }
}
