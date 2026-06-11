import Foundation

nonisolated struct ToolOutput: Sendable {
    var content: String
    var sources: [SourceAttribution] = []
    var isError = false
}

/// A capability the model can invoke through a tool call (TL-1). Tools that
/// send anything off-device must set `causesEgress` so the router re-checks
/// the user's toggle at call time (TL-4).
nonisolated protocol LocalTool: Sendable {
    var spec: ToolSpec { get }
    func execute(argumentsJSON: String) async -> ToolOutput
}

nonisolated extension LocalTool {
    /// Decodes the model-supplied arguments leniently.
    func decodeArguments<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
