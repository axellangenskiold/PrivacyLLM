import Foundation

/// Production document pipeline (FR-25...FR-31): import → extract → chunk →
/// embed → store, all on-device; retrieval is brute-force cosine over the
/// encrypted chunk store (DR-2).
actor RAGDocumentService: DocumentServicing {
    struct Caps {
        var maxPages = 300
        var maxDocumentBytes: Int64 = 25 * 1024 * 1024
        var maxCorpusBytes: Int64 = 200 * 1024 * 1024
    }

    private let store: DocumentStore
    private let embedder: any EmbeddingServicing
    private let chunker = Chunker()
    private let caps: Caps

    init(store: DocumentStore, embedder: any EmbeddingServicing, caps: Caps = Caps()) {
        self.store = store
        self.embedder = embedder
        self.caps = caps
    }

    func importPDF(at url: URL, scope: DocumentScope) async throws -> DocumentMeta {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let byteSize = Int64((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64).flatMap { $0 } ?? 0)
        guard byteSize <= caps.maxDocumentBytes else {
            throw DocumentError.documentTooLarge(maxPages: caps.maxPages)
        }
        let corpusBytes = (try? await store.totalCorpusBytes()) ?? 0
        guard corpusBytes + byteSize <= caps.maxCorpusBytes else {
            throw DocumentError.corpusFull(maxBytes: caps.maxCorpusBytes)
        }

        // Throws before anything is persisted (FR-31).
        let pages = try PDFExtractor.extract(from: url, maxPages: caps.maxPages)
        let textChunks = chunker.chunk(pages: pages)
        try await embedder.prepare()

        var meta = DocumentMeta(
            title: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent,
            pageCount: pages.last?.pageNumber ?? pages.count,
            byteSize: byteSize,
            scope: scope,
            chunkCount: textChunks.count,
            indexState: .indexing
        )
        try await store.insert(meta)

        do {
            var chunks: [Chunk] = []
            chunks.reserveCapacity(textChunks.count)
            for (ordinal, textChunk) in textChunks.enumerated() {
                let vector = try await embedder.embed(textChunk.text)
                chunks.append(Chunk(
                    documentID: meta.id,
                    ordinal: ordinal,
                    pageNumber: textChunk.pageNumber,
                    text: textChunk.text,
                    embedding: vector
                ))
            }
            try await store.insertChunks(chunks)
            meta.indexState = .ready
            meta.chunkCount = chunks.count
            try await store.update(meta)
            return meta
        } catch {
            // Leave nothing half-indexed behind.
            try? await store.delete(meta.id)
            throw error
        }
    }

    func documents() async throws -> [DocumentMeta] {
        try await store.fetchAll()
    }

    func deleteDocument(_ id: UUID) async throws {
        guard try await store.fetch(id) != nil else { throw DocumentError.notFound }
        try await store.delete(id)
    }

    func retrieve(query: String, conversationID: UUID?, topK: Int) async throws -> [RetrievedChunk] {
        let visible = try await store.fetchVisible(conversationID: conversationID)
            .filter { $0.indexState == .ready }
        guard !visible.isEmpty else { return [] }
        try await embedder.prepare()
        let queryVector = try await embedder.embed(query)

        let titlesByID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0.title) })
        let chunks = try await store.chunks(forDocuments: visible.map(\.id))
        return chunks
            .map { chunk in
                RetrievedChunk(
                    chunk: chunk,
                    documentTitle: titlesByID[chunk.documentID] ?? "Document",
                    similarity: VectorMath.cosineSimilarity(queryVector, chunk.embedding)
                )
            }
            .sorted { $0.similarity > $1.similarity }
            .prefix(topK)
            .map { $0 }
    }

    func fullTextIfShort(documentID: UUID, maxCharacters: Int) async throws -> String? {
        let chunks = try await store.chunks(forDocuments: [documentID])
        guard !chunks.isEmpty else { return nil }
        let text = chunks.sorted { $0.ordinal < $1.ordinal }.map(\.text).joined(separator: "\n\n")
        return text.count <= maxCharacters ? text : nil
    }
}
