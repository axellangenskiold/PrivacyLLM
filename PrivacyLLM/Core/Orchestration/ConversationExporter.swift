import Foundation

/// Renders a conversation for the share sheet (FR-10).
nonisolated enum ConversationExporter {
    static func markdown(conversation: Conversation, messages: [Message]) -> String {
        var output = "# \(conversation.title)\n\n*Exported from PrivacyLLM — generated and stored on-device.*\n"
        for message in messages where message.role == .user || message.role == .assistant {
            output += "\n## \(message.role == .user ? "You" : "Assistant")\n\n\(message.content)\n"
            if !message.sources.isEmpty {
                let links = message.sources.map { source in
                    if let url = source.urlString {
                        "[\(source.title)](\(url))"
                    } else {
                        source.title
                    }
                }
                output += "\n**Sources:** \(links.joined(separator: " · "))\n"
            }
        }
        return output
    }

    static func plainText(conversation: Conversation, messages: [Message]) -> String {
        var output = "\(conversation.title)\n"
        for message in messages where message.role == .user || message.role == .assistant {
            output += "\n\(message.role == .user ? "You" : "Assistant"):\n\(message.content)\n"
        }
        return output
    }
}
