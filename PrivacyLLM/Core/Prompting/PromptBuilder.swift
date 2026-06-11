import Foundation

/// Assembles the structured prompt for a turn: system prompt, then as much
/// recent history as fits the context budget (MR-7). Uses a chars-per-token
/// approximation until the engine's tokenizer takes over in the MLX module.
nonisolated struct PromptBuilder: Sendable {
    var charsPerToken: Int = 4

    func build(
        systemPrompt: String?,
        history: [Message],
        config: GenerationConfig,
        tools: [ToolSpec] = []
    ) -> PromptInput {
        // Reserve room for the model's response (MR-7).
        var budget = max(256, config.contextLength - config.sampling.maxTokens)
        if let systemPrompt, !systemPrompt.isEmpty {
            budget -= estimatedTokens(systemPrompt)
        }

        var includedNewestFirst: [PromptMessage] = []
        for message in history.reversed() where message.role == .user || message.role == .assistant {
            let cost = estimatedTokens(message.content)
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
