import Foundation

/// A record of data intentionally leaving the device. Stored locally only,
/// surfaced in the Privacy Activity view (PR-14) and the live egress indicator (FR-21).
nonisolated struct EgressEvent: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case webSearch
        case modelDownload
    }

    var id: UUID
    var kind: Kind
    var destinationHost: String
    /// What was sent (search keywords) or fetched (model name). Never conversation content.
    var detail: String
    var occurredAt: Date

    init(id: UUID = UUID(), kind: Kind, destinationHost: String, detail: String, occurredAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.destinationHost = destinationHost
        self.detail = detail
        self.occurredAt = occurredAt
    }
}
