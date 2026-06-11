import Foundation

nonisolated enum DocumentScope: Hashable, Codable, Sendable {
    case global
    case conversation(UUID)
}

nonisolated enum DocumentIndexState: String, Codable, Sendable {
    case pending
    case indexing
    case ready
    case failed
}

nonisolated struct DocumentMeta: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    var fileName: String
    var pageCount: Int
    var byteSize: Int64
    var importedAt: Date
    var scope: DocumentScope
    var chunkCount: Int
    var indexState: DocumentIndexState

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        pageCount: Int,
        byteSize: Int64,
        importedAt: Date = .now,
        scope: DocumentScope = .global,
        chunkCount: Int = 0,
        indexState: DocumentIndexState = .pending
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.pageCount = pageCount
        self.byteSize = byteSize
        self.importedAt = importedAt
        self.scope = scope
        self.chunkCount = chunkCount
        self.indexState = indexState
    }
}

nonisolated struct Chunk: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var documentID: UUID
    var ordinal: Int
    var pageNumber: Int?
    var text: String
    var embedding: [Float]

    init(
        id: UUID = UUID(),
        documentID: UUID,
        ordinal: Int,
        pageNumber: Int? = nil,
        text: String,
        embedding: [Float] = []
    ) {
        self.id = id
        self.documentID = documentID
        self.ordinal = ordinal
        self.pageNumber = pageNumber
        self.text = text
        self.embedding = embedding
    }
}

nonisolated struct RetrievedChunk: Hashable, Sendable {
    var chunk: Chunk
    var documentTitle: String
    var similarity: Double
}

nonisolated enum DocumentError: Error, Sendable, Equatable {
    case notAPDF
    case passwordProtected
    /// PDF contains no extractable text (likely scanned images; OCR is out of scope for v1).
    case noExtractableText
    case documentTooLarge(maxPages: Int)
    case corpusFull(maxBytes: Int64)
    case notFound
}
