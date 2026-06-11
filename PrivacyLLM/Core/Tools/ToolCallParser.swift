import Foundation

nonisolated struct ParsedToolCall: Hashable, Sendable {
    /// nil when the block was syntactically present but the JSON was invalid.
    var call: ToolCall?
    /// The exact text the model emitted, kept for transcript reconstruction.
    var rawBlock: String
    var parseError: String?
}

/// Extracts `<tool_call>{json}</tool_call>` blocks (Hermes/Qwen format) from a
/// token stream, tolerating tags split across chunk boundaries and malformed
/// JSON (TL-1). Everything outside blocks passes through as visible content.
nonisolated struct ToolCallParser: Sendable {
    private static let openTag = "<tool_call>"
    private static let closeTag = "</tool_call>"
    /// A block that never closes can't be allowed to buffer forever.
    private static let maxBlockSize = 32_768

    private var pending = ""
    private var insideBlock = false

    mutating func feed(_ delta: String) -> (visible: String, calls: [ParsedToolCall]) {
        var visible = ""
        var calls: [ParsedToolCall] = []
        pending += delta

        var progressed = true
        while progressed {
            progressed = false
            if insideBlock {
                if let range = pending.range(of: Self.closeTag) {
                    let body = String(pending[..<range.lowerBound])
                    calls.append(Self.parse(body: body))
                    pending = String(pending[range.upperBound...])
                    insideBlock = false
                    progressed = true
                } else if pending.count > Self.maxBlockSize {
                    // Runaway block: give the text back rather than buffering forever.
                    visible += Self.openTag + pending
                    pending = ""
                    insideBlock = false
                }
            } else {
                if let range = pending.range(of: Self.openTag) {
                    visible += String(pending[..<range.lowerBound])
                    pending = String(pending[range.upperBound...])
                    insideBlock = true
                    progressed = true
                } else {
                    let holdback = Self.holdbackLength(of: pending, for: Self.openTag)
                    let emitCount = pending.count - holdback
                    if emitCount > 0 {
                        visible += String(pending.prefix(emitCount))
                        pending = String(pending.suffix(holdback))
                    }
                }
            }
        }
        return (visible, calls)
    }

    mutating func finish() -> (visible: String, calls: [ParsedToolCall]) {
        defer {
            pending = ""
            insideBlock = false
        }
        if insideBlock {
            // Generation ended mid-call (cancelled or token limit): report it
            // as a malformed call so the model gets actionable feedback.
            return ("", [ParsedToolCall(
                call: nil,
                rawBlock: Self.openTag + pending,
                parseError: "tool call was never closed"
            )])
        }
        return (pending, [])
    }

    private static func parse(body: String) -> ParsedToolCall {
        let raw = openTag + body + closeTag
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
            return ParsedToolCall(call: nil, rawBlock: raw, parseError: "arguments were not valid JSON")
        }
        guard let name = object["name"] as? String, !name.isEmpty else {
            return ParsedToolCall(call: nil, rawBlock: raw, parseError: "missing tool name")
        }
        let argumentsJSON: String
        if let arguments = object["arguments"],
           JSONSerialization.isValidJSONObject(arguments),
           let data = try? JSONSerialization.data(withJSONObject: arguments) {
            argumentsJSON = String(decoding: data, as: UTF8.self)
        } else {
            argumentsJSON = "{}"
        }
        return ParsedToolCall(call: ToolCall(name: name, argumentsJSON: argumentsJSON), rawBlock: raw)
    }

    /// Longest suffix of `text` that could still grow into `tag`.
    private static func holdbackLength(of text: String, for tag: String) -> Int {
        let maxLength = min(text.count, tag.count - 1)
        guard maxLength > 0 else { return 0 }
        for length in stride(from: maxLength, through: 1, by: -1) {
            if text.hasSuffix(String(tag.prefix(length))) {
                return length
            }
        }
        return 0
    }
}
