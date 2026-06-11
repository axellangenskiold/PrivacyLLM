import Foundation
import NaturalLanguage

nonisolated enum EmbeddingError: Error {
    case assetsUnavailable
    case embeddingFailed
}

nonisolated protocol EmbeddingServicing: Sendable {
    /// Ensures the embedding model is ready. May trigger an Apple-managed,
    /// OS-level asset download on first use — disclosed in the privacy
    /// explainer; no user content is involved.
    func prepare() async throws
    func embed(_ text: String) async throws -> [Float]
}

/// Apple's built-in contextual embeddings (OD-3): zero bundled megabytes,
/// fully on-device inference. Mean-pools token vectors into one document/query
/// vector, L2-normalized for cosine similarity.
actor ContextualEmbeddingService: EmbeddingServicing {
    private var embedding: NLContextualEmbedding?

    func prepare() async throws {
        guard embedding == nil else { return }
        guard let contextual = NLContextualEmbedding(script: .latin) else {
            throw EmbeddingError.assetsUnavailable
        }
        if !contextual.hasAvailableAssets {
            _ = try await contextual.requestAssets()
            guard contextual.hasAvailableAssets else {
                throw EmbeddingError.assetsUnavailable
            }
        }
        try contextual.load()
        embedding = contextual
    }

    func embed(_ text: String) async throws -> [Float] {
        try await prepare()
        guard let embedding else { throw EmbeddingError.assetsUnavailable }
        let result = try embedding.embeddingResult(for: text, language: nil)
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var tokenCount = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for (index, value) in vector.enumerated() where index < sum.count {
                sum[index] += value
            }
            tokenCount += 1
            return true
        }
        guard tokenCount > 0 else { throw EmbeddingError.embeddingFailed }
        let mean = sum.map { $0 / Double(tokenCount) }
        let norm = mean.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { throw EmbeddingError.embeddingFailed }
        return mean.map { Float($0 / norm) }
    }
}

/// Deterministic bag-of-words embedder for tests, previews, and as a
/// functional fallback if the OS assets are unavailable. Stable across runs
/// (djb2, not Swift's randomized hashing).
nonisolated struct StubEmbeddingService: EmbeddingServicing {
    var dimension = 64

    func prepare() async throws {}

    func embed(_ text: String) async throws -> [Float] {
        var vector = [Float](repeating: 0, count: dimension)
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        for word in words {
            vector[Int(Self.djb2(word) % UInt64(dimension))] += 1
        }
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    private static func djb2(_ text: Substring) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return hash
    }
}
