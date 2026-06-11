import Foundation

/// PDF import, on-device indexing, and retrieval (FR-25...FR-31).
nonisolated protocol DocumentServicing: Sendable {
    /// Imports, extracts, chunks, embeds, and indexes a PDF. Throws DocumentError
    /// for non-PDFs, scanned PDFs, and size-cap violations.
    func importPDF(at url: URL, scope: DocumentScope) async throws -> DocumentMeta

    func documents() async throws -> [DocumentMeta]

    /// Removes the document and purges its index (FR-28).
    func deleteDocument(_ id: UUID) async throws

    /// Top-k chunks by cosine similarity, restricted to globally-available
    /// documents plus those attached to `conversationID` (OD-6).
    func retrieve(query: String, conversationID: UUID?, topK: Int) async throws -> [RetrievedChunk]

    /// Full text when the document is short enough to inject whole (§3.4); nil otherwise.
    func fullTextIfShort(documentID: UUID, maxCharacters: Int) async throws -> String?
}

/// In-memory document service for simulator, previews, and tests.
actor MockDocumentService: DocumentServicing {
    private var docs: [DocumentMeta]
    private var chunksByDoc: [UUID: [Chunk]] = [:]

    init(documents: [DocumentMeta] = []) {
        self.docs = documents
    }

    func importPDF(at url: URL, scope: DocumentScope) async throws -> DocumentMeta {
        guard url.pathExtension.lowercased() == "pdf" else { throw DocumentError.notAPDF }
        try? await Task.sleep(for: .milliseconds(300))
        var meta = DocumentMeta(
            title: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent,
            pageCount: 3,
            byteSize: 120_000,
            scope: scope,
            chunkCount: 3,
            indexState: .ready
        )
        meta.chunkCount = 3
        docs.append(meta)
        chunksByDoc[meta.id] = (0..<3).map { ordinal in
            Chunk(
                documentID: meta.id,
                ordinal: ordinal,
                pageNumber: ordinal + 1,
                text: "Mock chunk \(ordinal) of \(meta.title).",
                embedding: [Float(ordinal), 1, 0]
            )
        }
        return meta
    }

    func documents() -> [DocumentMeta] {
        docs
    }

    func deleteDocument(_ id: UUID) throws {
        guard docs.contains(where: { $0.id == id }) else { throw DocumentError.notFound }
        docs.removeAll { $0.id == id }
        chunksByDoc[id] = nil
    }

    func retrieve(query: String, conversationID: UUID?, topK: Int) -> [RetrievedChunk] {
        let visible = docs.filter { doc in
            switch doc.scope {
            case .global: true
            case .conversation(let id): id == conversationID
            }
        }
        return visible.flatMap { doc in
            (chunksByDoc[doc.id] ?? []).map {
                RetrievedChunk(chunk: $0, documentTitle: doc.title, similarity: 0.9)
            }
        }
        .prefix(topK)
        .map { $0 }
    }

    func fullTextIfShort(documentID: UUID, maxCharacters: Int) -> String? {
        guard let chunks = chunksByDoc[documentID] else { return nil }
        let text = chunks.map(\.text).joined(separator: "\n")
        return text.count <= maxCharacters ? text : nil
    }
}
