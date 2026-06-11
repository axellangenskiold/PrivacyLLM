import Foundation

nonisolated enum ModelRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case fast
    case thinking

    var id: String { rawValue }
}

nonisolated struct ModelCapabilities: Hashable, Codable, Sendable {
    /// The model emits structured reasoning (e.g. Qwen3 `<think>` blocks) that can be toggled.
    var nativeThinking: Bool
    var toolCalling: Bool

    init(nativeThinking: Bool = false, toolCalling: Bool = false) {
        self.nativeThinking = nativeThinking
        self.toolCalling = toolCalling
    }
}

nonisolated struct ModelSpec: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var displayName: String
    /// Model family, used to pick prompt scaffolds and parsing rules (e.g. "qwen3", "llama3").
    var family: String
    /// Hugging Face repo the weights are downloaded from (e.g. "mlx-community/...").
    var hfRepo: String
    var roles: [ModelRole]
    /// Approximate total download size, shown before downloading.
    var sizeBytes: Int64
    var parameterCount: String
    var quantization: String
    var minRAMGB: Int
    var contextLength: Int
    var licenseName: String
    var licenseURLString: String
    var capabilities: ModelCapabilities
}
