import Foundation
import PDFKit
import Testing
import UIKit
@testable import PrivacyLLM

/// Renders throwaway PDFs so extraction tests don't need binary fixtures.
@MainActor
private enum PDFFixture {
    static func make(pages: [String]) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                (page as NSString).draw(
                    in: bounds.insetBy(dx: 40, dy: 40),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
                )
            }
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString).pdf")
        try data.write(to: url)
        return url
    }
}

struct PDFExtractionTests {
    @Test func extractsTextPerPage(/* TR-1 */) async throws {
        let url = try await PDFFixture.make(pages: [
            "Alpha page about apples.",
            "Beta page about bicycles.",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try PDFExtractor.extract(from: url, maxPages: 10)
        #expect(pages.count == 2)
        #expect(pages[0].pageNumber == 1)
        #expect(pages[0].text.contains("apples"))
        #expect(pages[1].text.contains("bicycles"))
    }

    @Test func imageOnlyPDFIsRejected(/* FR-31 */) async throws {
        let url = try await PDFFixture.make(pages: ["", ""])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: DocumentError.noExtractableText) {
            _ = try PDFExtractor.extract(from: url, maxPages: 10)
        }
    }

    @Test func nonPDFIsRejected(/* FR-31 */) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "not-a-pdf-\(UUID().uuidString).pdf")
        try Data("plain text pretending".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: DocumentError.notAPDF) {
            _ = try PDFExtractor.extract(from: url, maxPages: 10)
        }
    }

    @Test func pageCapIsEnforced(/* FR-29 */) async throws {
        let url = try await PDFFixture.make(pages: ["one", "two", "three"])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: DocumentError.documentTooLarge(maxPages: 2)) {
            _ = try PDFExtractor.extract(from: url, maxPages: 2)
        }
    }
}

struct ChunkerTests {
    @Test func shortTextIsOneChunk(/* TR-1 */) {
        let chunker = Chunker()
        #expect(chunker.split("A short paragraph.") == ["A short paragraph."])
        #expect(chunker.split("   ").isEmpty)
    }

    @Test func paragraphsGroupNearTargetWithOverlap() {
        let chunker = Chunker(targetSize: 100, overlap: 20)
        let paragraphs = (1...8).map { index in
            "Paragraph number \(index) with some filler words to give it weight."
        }
        let chunks = chunker.split(paragraphs.joined(separator: "\n\n"))
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 160 })
        // Overlap: later chunks carry a tail of their predecessor.
        #expect(chunks[1].hasPrefix(String(chunks[0].suffix(20))))
    }

    @Test func giantParagraphIsWindowed() {
        let chunker = Chunker(targetSize: 100, overlap: 20)
        let giant = String(repeating: "x", count: 450)
        let chunks = chunker.split(giant)
        #expect(chunks.count >= 5)
        #expect(chunks.allSatisfy { $0.count <= 100 })
        let reassembledLength = chunks.reduce(0) { $0 + $1.count }
        #expect(reassembledLength >= 450)
    }

    @Test func pagesCarryTheirNumbers() {
        let chunker = Chunker()
        let chunks = chunker.chunk(pages: [
            ExtractedPage(pageNumber: 1, text: "First page text."),
            ExtractedPage(pageNumber: 7, text: "Seventh page text."),
        ])
        #expect(chunks.map(\.pageNumber) == [1, 7])
    }
}

struct RetrievalTests {
    @Test func cosineRanksExpectedTopK(/* TR-2 */) {
        let a: [Float] = [1, 0, 0]
        let closeToA: [Float] = [0.9, 0.1, 0]
        let farFromA: [Float] = [0, 0, 1]
        #expect(VectorMath.cosineSimilarity(a, closeToA) > VectorMath.cosineSimilarity(a, farFromA))
        #expect(abs(VectorMath.cosineSimilarity(a, a) - 1) < 1e-6)
        #expect(VectorMath.cosineSimilarity(a, []) == 0)
    }

    @Test func retrieveFindsTheRightChunkAcrossDocuments(/* TR-2/TR-9 */) async throws {
        let database = try AppDatabase.inMemory()
        let service = RAGDocumentService(
            store: DocumentStore(database: database),
            embedder: StubEmbeddingService()
        )

        let lease = try await PDFFixture.make(pages: [
            "The lease agreement states the monthly rent is 9500 kronor, due on the first.",
        ])
        let recipes = try await PDFFixture.make(pages: [
            "Pancake recipe: flour, milk, eggs. Whisk and fry in butter.",
        ])
        defer {
            try? FileManager.default.removeItem(at: lease)
            try? FileManager.default.removeItem(at: recipes)
        }

        _ = try await service.importPDF(at: lease, scope: .global)
        _ = try await service.importPDF(at: recipes, scope: .global)

        let hits = try await service.retrieve(query: "how much is the monthly rent", conversationID: nil, topK: 1)
        #expect(hits.count == 1)
        #expect(hits[0].chunk.text.contains("9500"))
        #expect(hits[0].documentTitle.contains("fixture"))
    }

    @Test func conversationScopedDocsAreInvisibleElsewhere(/* OD-6 */) async throws {
        let database = try AppDatabase.inMemory()
        let service = RAGDocumentService(
            store: DocumentStore(database: database),
            embedder: StubEmbeddingService()
        )
        let conversationID = UUID()
        let url = try await PDFFixture.make(pages: ["Secret project timeline: ship in March."])
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await service.importPDF(at: url, scope: .conversation(conversationID))

        let visibleHere = try await service.retrieve(query: "project timeline ship", conversationID: conversationID, topK: 3)
        #expect(!visibleHere.isEmpty)
        let visibleElsewhere = try await service.retrieve(query: "project timeline ship", conversationID: UUID(), topK: 3)
        #expect(visibleElsewhere.isEmpty)
    }

    @Test func deleteAlsoPurgesIndex(/* FR-28 */) async throws {
        let database = try AppDatabase.inMemory()
        let store = DocumentStore(database: database)
        let service = RAGDocumentService(store: store, embedder: StubEmbeddingService())
        let url = try await PDFFixture.make(pages: ["Disposable content."])
        defer { try? FileManager.default.removeItem(at: url) }
        let meta = try await service.importPDF(at: url, scope: .global)
        try await service.deleteDocument(meta.id)
        let chunks = try await store.chunks(forDocuments: [meta.id])
        #expect(chunks.isEmpty)
        let hits = try await service.retrieve(query: "disposable", conversationID: nil, topK: 3)
        #expect(hits.isEmpty)
    }
}

struct RAGPipelineTests {
    /// TR-9 end to end: import → index → query → chunk lands in the prompt →
    /// answer carries a document citation.
    @Test func documentContextReachesPromptAndCitations() async throws {
        let database = try AppDatabase.inMemory()
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)

        let service = RAGDocumentService(
            store: DocumentStore(database: database),
            embedder: StubEmbeddingService()
        )
        let url = try await PDFFixture.make(pages: [
            "Quarterly report: revenue grew 12 percent year over year, driven by exports.",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await service.importPDF(at: url, scope: .global)

        let inference = MockInferenceService(
            tokenDelay: .milliseconds(1),
            scriptedReply: "Revenue grew 12 percent, according to the quarterly report."
        )
        let orchestrator = ChatOrchestrator(
            inference: inference,
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            messageStore: MessageStore(database: database),
            conversationStore: ConversationStore(database: database),
            settingsStore: SettingsStore(database: database),
            documents: service
        )

        var completed: Message?
        let stream = await orchestrator.send(text: "How much did revenue grow?", conversation: conversation, history: [])
        for await event in stream {
            if case .assistantCompleted(let message) = event { completed = message }
            if case .turnFailed(let reason, _) = event { Issue.record("failed: \(reason)") }
        }

        // The document text reached the model's system prompt (§3.4).
        let sentInput = await inference.lastInput
        let systemContent = sentInput?.messages.first { $0.role == .system }?.content ?? ""
        #expect(systemContent.contains("revenue grew 12 percent"))

        // And the reply carries a document citation (FR-27).
        #expect(completed?.sources.contains { $0.kind == .document } == true)
    }
}
