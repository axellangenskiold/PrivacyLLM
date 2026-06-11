import Foundation

/// Splits extracted pages into overlapping retrieval chunks (FR-26),
/// preferring paragraph boundaries so chunks stay coherent.
nonisolated struct Chunker: Sendable {
    var targetSize = 1000
    var overlap = 200

    struct TextChunk: Hashable, Sendable {
        var text: String
        var pageNumber: Int
    }

    func chunk(pages: [ExtractedPage]) -> [TextChunk] {
        var chunks: [TextChunk] = []
        for page in pages {
            for piece in split(page.text) {
                chunks.append(TextChunk(text: piece, pageNumber: page.pageNumber))
            }
        }
        return chunks
    }

    func split(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > targetSize else {
            return trimmed.isEmpty ? [] : [trimmed]
        }

        // Build up paragraphs into chunks near the target size.
        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""
        func flush() {
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { chunks.append(piece) }
            current = ""
        }
        for paragraph in paragraphs {
            if paragraph.count > targetSize {
                flush()
                chunks.append(contentsOf: hardSplit(paragraph))
                continue
            }
            if current.count + paragraph.count + 2 > targetSize {
                flush()
                // Overlap: carry the tail of the previous chunk forward for context.
                if let last = chunks.last, overlap > 0 {
                    current = String(last.suffix(overlap)) + "\n"
                }
            }
            current += (current.isEmpty ? "" : "\n\n") + paragraph
        }
        flush()
        return chunks
    }

    /// Oversized single paragraphs fall back to plain windowing with overlap.
    private func hardSplit(_ text: String) -> [String] {
        var result: [String] = []
        let characters = Array(text)
        var start = 0
        while start < characters.count {
            let end = min(start + targetSize, characters.count)
            result.append(String(characters[start..<end]))
            if end == characters.count { break }
            start = max(0, end - overlap)
        }
        return result
    }
}

nonisolated enum VectorMath {
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        for index in 0..<a.count {
            let x = Double(a[index])
            let y = Double(b[index])
            dot += x * y
            normA += x * x
            normB += y * y
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
