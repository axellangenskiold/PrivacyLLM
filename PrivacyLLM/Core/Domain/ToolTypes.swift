import Foundation

nonisolated struct ToolSpec: Hashable, Codable, Sendable {
    var name: String
    var summary: String
    /// JSON Schema describing the arguments object, passed to the model verbatim.
    var parametersJSONSchema: String
    /// Tools that send data off-device must re-check their gating toggle at call time (TL-4).
    var causesEgress: Bool
}

nonisolated struct ToolCall: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var argumentsJSON: String

    init(id: UUID = UUID(), name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

nonisolated struct ToolResult: Hashable, Codable, Sendable {
    var callID: UUID
    var toolName: String
    var content: String
    var isError: Bool
    var sources: [SourceAttribution]

    init(callID: UUID, toolName: String, content: String, isError: Bool = false, sources: [SourceAttribution] = []) {
        self.callID = callID
        self.toolName = toolName
        self.content = content
        self.isError = isError
        self.sources = sources
    }
}
