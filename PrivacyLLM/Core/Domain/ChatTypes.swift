import Foundation

nonisolated enum ChatRole: String, Codable, Sendable, CaseIterable {
    case system
    case user
    case assistant
    case tool
    /// A document attached to this conversation, shown as a card in the
    /// transcript. Never sent to the model — retrieval injects the content.
    case attachment
}

nonisolated struct Conversation: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    /// Per-conversation persona override; falls back to the global system prompt when nil.
    var systemPrompt: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = String(localized: "New Chat"),
        systemPrompt: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct SourceAttribution: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case web
        case document
    }

    var kind: Kind
    var title: String
    var urlString: String?
    var documentID: UUID?
    var pageNumber: Int?

    init(kind: Kind, title: String, urlString: String? = nil, documentID: UUID? = nil, pageNumber: Int? = nil) {
        self.kind = kind
        self.title = title
        self.urlString = urlString
        self.documentID = documentID
        self.pageNumber = pageNumber
    }
}

nonisolated struct GenerationStats: Hashable, Codable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    var tokensPerSecond: Double?
    var firstTokenSeconds: Double?

    init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        tokensPerSecond: Double? = nil,
        firstTokenSeconds: Double? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.tokensPerSecond = tokensPerSecond
        self.firstTokenSeconds = firstTokenSeconds
    }
}

nonisolated struct Message: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var conversationID: UUID
    var role: ChatRole
    var content: String
    /// Raw "thinking" output for reasoning models, rendered collapsed in the UI.
    var reasoning: String?
    var createdAt: Date
    var modelID: String?
    var stats: GenerationStats?
    var sources: [SourceAttribution]

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        role: ChatRole,
        content: String,
        reasoning: String? = nil,
        createdAt: Date = .now,
        modelID: String? = nil,
        stats: GenerationStats? = nil,
        sources: [SourceAttribution] = []
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.createdAt = createdAt
        self.modelID = modelID
        self.stats = stats
        self.sources = sources
    }
}
