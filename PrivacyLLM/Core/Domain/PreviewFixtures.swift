import Foundation

// Fixtures shared by mocks, SwiftUI previews, and tests. The real model catalog
// ships as Config/ModelCatalog.json and is verified against Hugging Face.
extension ModelSpec {
    nonisolated static let previewFast = ModelSpec(
        id: "mock-fast-1b",
        displayName: "Mock Fast 1B",
        family: "mock",
        hfRepo: "mock/fast-1b",
        roles: [.fast],
        sizeBytes: 700_000_000,
        parameterCount: "1B",
        quantization: "4-bit",
        minRAMGB: 4,
        contextLength: 8192,
        licenseName: "Apache-2.0",
        licenseURLString: "https://www.apache.org/licenses/LICENSE-2.0",
        capabilities: ModelCapabilities(nativeThinking: false, toolCalling: true)
    )

    nonisolated static let previewThinking = ModelSpec(
        id: "mock-thinking-4b",
        displayName: "Mock Thinking 4B",
        family: "mock",
        hfRepo: "mock/thinking-4b",
        roles: [.thinking],
        sizeBytes: 2_300_000_000,
        parameterCount: "4B",
        quantization: "4-bit",
        minRAMGB: 6,
        contextLength: 16384,
        licenseName: "Apache-2.0",
        licenseURLString: "https://www.apache.org/licenses/LICENSE-2.0",
        capabilities: ModelCapabilities(nativeThinking: true, toolCalling: true)
    )

    nonisolated static let previewCatalog: [ModelSpec] = [previewFast, previewThinking]
}

extension Conversation {
    nonisolated static let preview = Conversation(title: "Preview Chat")
}
