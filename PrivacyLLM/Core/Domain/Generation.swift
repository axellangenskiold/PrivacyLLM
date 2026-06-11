import Foundation

nonisolated struct SamplingParams: Hashable, Codable, Sendable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int

    init(temperature: Double = 0.7, topP: Double = 0.9, maxTokens: Int = 1024) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
    }
}

nonisolated struct GenerationConfig: Hashable, Codable, Sendable {
    var sampling: SamplingParams
    var contextLength: Int
    /// Whether the thinking scaffold / native reasoning mode is active for this turn.
    var thinkingEnabled: Bool

    init(sampling: SamplingParams = SamplingParams(), contextLength: Int = 4096, thinkingEnabled: Bool = false) {
        self.sampling = sampling
        self.contextLength = contextLength
        self.thinkingEnabled = thinkingEnabled
    }
}

/// A single template-ready message produced by the PromptBuilder. The inference
/// engine applies the model's own chat template to the array (MR-3).
nonisolated struct PromptMessage: Hashable, Codable, Sendable {
    var role: ChatRole
    var content: String

    init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

nonisolated struct PromptInput: Hashable, Sendable {
    var messages: [PromptMessage]
    var tools: [ToolSpec]

    init(messages: [PromptMessage], tools: [ToolSpec] = []) {
        self.messages = messages
        self.tools = tools
    }
}
