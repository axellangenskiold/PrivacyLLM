import Foundation

/// Long-term facts about the user, injected into every chat's system prompt
/// (FR-43). The model writes them itself through `remember`; the user can see,
/// delete, or switch the whole feature off in Settings.
///
/// Hard-capped on purpose: memory rides in front of *every* turn, so it has to
/// cost a sliver of the context window, not a slice of it.
nonisolated struct UserMemory: Sendable {
    static let maxFacts = 12
    static let maxFactCharacters = 140

    let settingsStore: SettingsStore

    func isEnabled() async -> Bool {
        (try? await settingsStore.value(for: .memoryEnabled, default: true)) ?? true
    }

    func facts() async -> [String] {
        (try? await settingsStore.value(for: .userMemory, default: [String]())) ?? []
    }

    /// Adds a fact, oldest-out at the cap. Near-duplicates replace the old line
    /// rather than stacking up — a small model will happily re-remember the
    /// same thing every turn.
    func remember(_ raw: String) async -> String {
        let fact = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxFactCharacters))
        guard fact.count >= 3 else { return "" }
        var stored = await facts()
        stored.removeAll { Self.isNearDuplicate($0, fact) }
        stored.append(fact)
        if stored.count > Self.maxFacts {
            stored.removeFirst(stored.count - Self.maxFacts)
        }
        try? await settingsStore.set(stored, for: .userMemory)
        return fact
    }

    func remove(atOffsets offsets: IndexSet) async {
        var stored = await facts()
        // Array.remove(atOffsets:) lives in SwiftUI; this stays UI-free.
        for index in offsets.sorted(by: >) where stored.indices.contains(index) {
            stored.remove(at: index)
        }
        try? await settingsStore.set(stored, for: .userMemory)
    }

    func clear() async {
        try? await settingsStore.set([String](), for: .userMemory)
    }

    /// The system-prompt block, or nil when memory is off or empty.
    func promptBlock() async -> String? {
        guard await isEnabled() else { return nil }
        let stored = await facts()
        guard !stored.isEmpty else { return nil }
        return "What you already know about this user:\n" + stored.map { "- \($0)" }.joined(separator: "\n")
    }

    // ponytail: Jaccard over words, not embeddings. Catches "likes espresso" vs
    // "the user likes espresso" while leaving facts that differ by one detail
    // ("meeting at 9" vs "meeting at 3") as two separate facts — measuring
    // against the smaller set instead of the union collapsed exactly those.
    // Swap in NLContextualEmbedding if it still misses too much.
    private static func isNearDuplicate(_ lhs: String, _ rhs: String) -> Bool {
        let words: (String) -> Set<String> = { text in
            Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                .subtracting(["the", "user", "a", "an", "is", "are", "of", "to", "in", "and", "their", "they"])
        }
        let left = words(lhs), right = words(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return Double(left.intersection(right).count) / Double(left.union(right).count) >= 0.8
    }
}

/// Lets the model write to its own long-term memory (FR-43).
nonisolated struct RememberTool: LocalTool {
    private struct Arguments: Decodable {
        var fact: String
    }

    let memory: UserMemory

    var spec: ToolSpec {
        ToolSpec(
            name: "remember",
            summary: "Saves one short, lasting fact about the user (name, job, preferences, ongoing projects) so future chats know it. Use only for things that stay true; never for one-off questions or anything the user asked you to keep private.",
            parametersJSONSchema: #"{"type":"object","properties":{"fact":{"type":"string","description":"One short sentence, under 140 characters, e.g. \"Lives in Stockholm and prefers metric units.\""}},"required":["fact"]}"#,
            causesEgress: false
        )
    }

    func execute(argumentsJSON: String) async -> ToolOutput {
        guard await memory.isEnabled() else {
            return ToolOutput(content: "Memory is switched off in Settings. Continue without saving.", isError: true)
        }
        guard let arguments = decodeArguments(Arguments.self, from: argumentsJSON) else {
            return ToolOutput(content: "Expected a \"fact\" string.", isError: true)
        }
        let saved = await memory.remember(arguments.fact)
        guard !saved.isEmpty else {
            return ToolOutput(content: "That fact was too short to store.", isError: true)
        }
        return ToolOutput(content: "Saved: \(saved)")
    }
}
