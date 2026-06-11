import Foundation

/// Splits a token stream into reasoning (a leading `<think>…</think>` block,
/// as emitted by Qwen3-style models) and visible content (UX-6). Tags may be
/// split across arbitrary chunk boundaries; leading whitespace around the
/// block and before the answer is swallowed.
nonisolated struct ThinkStreamParser: Sendable {
    private enum Phase {
        case detecting
        case reasoning
        case content
    }

    private static let openTag = "<think>"
    private static let closeTag = "</think>"

    private var phase: Phase = .detecting
    private var pending = ""
    private var contentStarted = false

    mutating func feed(_ delta: String) -> (reasoning: String, content: String) {
        var reasoning = ""
        var content = ""
        pending += delta

        var progressed = true
        while progressed {
            progressed = false
            switch phase {
            case .detecting:
                let stripped = pending.drop(while: \.isWhitespace)
                if stripped.isEmpty {
                    break
                }
                if stripped.hasPrefix(Self.openTag) {
                    pending = String(stripped.dropFirst(Self.openTag.count))
                    phase = .reasoning
                    progressed = true
                } else if Self.openTag.hasPrefix(String(stripped)) {
                    // Could still turn into the tag — wait for more.
                    break
                } else {
                    phase = .content
                    progressed = true
                }
            case .reasoning:
                if let range = pending.range(of: Self.closeTag) {
                    reasoning += String(pending[..<range.lowerBound])
                    pending = String(pending[range.upperBound...])
                    phase = .content
                    progressed = true
                } else {
                    // Hold back enough characters to recognize a tag that
                    // straddles the next chunk boundary.
                    let emitCount = pending.count - (Self.closeTag.count - 1)
                    if emitCount > 0 {
                        reasoning += String(pending.prefix(emitCount))
                        pending = String(pending.suffix(Self.closeTag.count - 1))
                    }
                }
            case .content:
                if !contentStarted {
                    let stripped = pending.drop(while: \.isWhitespace)
                    pending = ""
                    if !stripped.isEmpty {
                        contentStarted = true
                        content += String(stripped)
                    }
                } else {
                    content += pending
                    pending = ""
                }
            }
        }
        return (reasoning, content)
    }

    /// Flushes whatever is still buffered when the stream ends (e.g. an
    /// unterminated think block after a cancellation).
    mutating func finish() -> (reasoning: String, content: String) {
        defer {
            pending = ""
            phase = .content
        }
        switch phase {
        case .detecting:
            let stripped = String(pending.drop(while: \.isWhitespace))
            return ("", stripped)
        case .reasoning:
            return (pending, "")
        case .content:
            return ("", pending)
        }
    }
}
