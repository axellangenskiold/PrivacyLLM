import Foundation

/// Assembles the structured prompt for a turn: system prompt, then as much
/// recent history as fits the context budget (MR-7). Counts tokens with the
/// loaded model's tokenizer when available, falling back to a chars-per-token
/// approximation (mock engine, tests).
nonisolated struct PromptBuilder: Sendable {
    var charsPerToken: Int = 4

    func build(
        systemPrompt: String?,
        history: [Message],
        config: GenerationConfig,
        tools: [ToolSpec] = [],
        countTokens: (@Sendable (String) async -> Int?)? = nil
    ) async -> PromptInput {
        func tokens(_ text: String) async -> Int {
            if let countTokens, let exact = await countTokens(text) {
                return exact
            }
            return estimatedTokens(text)
        }

        // Reserve room for the model's response (MR-7).
        var budget = max(256, config.contextLength - config.sampling.maxTokens)
        if let systemPrompt, !systemPrompt.isEmpty {
            budget -= await tokens(systemPrompt)
        }

        var includedNewestFirst: [PromptMessage] = []
        for message in history.reversed() where message.role == .user || message.role == .assistant {
            let cost = await tokens(message.content)
            if cost > budget {
                if includedNewestFirst.isEmpty {
                    // The newest message must always survive, trimmed to fit.
                    let allowedChars = max(64, budget * charsPerToken)
                    includedNewestFirst.append(
                        PromptMessage(role: message.role, content: String(message.content.suffix(allowedChars)))
                    )
                }
                break
            }
            includedNewestFirst.append(PromptMessage(role: message.role, content: message.content))
            budget -= cost
        }

        var messages: [PromptMessage] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(PromptMessage(role: .system, content: systemPrompt))
        }
        messages.append(contentsOf: includedNewestFirst.reversed())
        return PromptInput(messages: messages, tools: tools)
    }

    func estimatedTokens(_ text: String) -> Int {
        max(1, text.count / charsPerToken)
    }
}
