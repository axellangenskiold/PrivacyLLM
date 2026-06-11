import Foundation

/// Dispatches parsed tool calls to registered tools (§3.3). Egress-causing
/// tools are re-validated against the user's toggle at call time, not just at
/// prompt-build time (TL-4).
nonisolated struct ToolRouter: Sendable {
    private let toolsByName: [String: any LocalTool]
    private let settingsStore: SettingsStore

    init(tools: [any LocalTool], settingsStore: SettingsStore) {
        toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.spec.name, $0) })
        self.settingsStore = settingsStore
    }

    /// Specs advertised to the model. Egress tools are omitted entirely while
    /// search is off, so the model never tries to call them (FR-18).
    func specs(includeEgressTools: Bool) -> [ToolSpec] {
        toolsByName.values
            .map(\.spec)
            .filter { includeEgressTools || !$0.causesEgress }
            .sorted { $0.name < $1.name }
    }

    func execute(_ parsed: ParsedToolCall) async -> ToolResult {
        guard let call = parsed.call else {
            return ToolResult(
                callID: UUID(),
                toolName: "invalid",
                content: "Invalid tool call (\(parsed.parseError ?? "unparseable")). Emit exactly one JSON object like {\"name\": \"tool_name\", \"arguments\": {…}} inside the tool_call block.",
                isError: true
            )
        }
        guard let tool = toolsByName[call.name] else {
            return ToolResult(
                callID: call.id,
                toolName: call.name,
                content: "Unknown tool \"\(call.name)\". Available tools: \(toolsByName.keys.sorted().joined(separator: ", ")).",
                isError: true
            )
        }
        if tool.spec.causesEgress {
            let searchEnabled = (try? await settingsStore.searchEnabled()) ?? false
            guard searchEnabled else {
                return ToolResult(
                    callID: call.id,
                    toolName: call.name,
                    content: "Web access is disabled by the user. Answer from your own knowledge and say that live results were unavailable.",
                    isError: true
                )
            }
        }
        let output = await tool.execute(argumentsJSON: call.argumentsJSON)
        return ToolResult(
            callID: call.id,
            toolName: call.name,
            content: output.content,
            isError: output.isError,
            sources: output.sources
        )
    }
}
