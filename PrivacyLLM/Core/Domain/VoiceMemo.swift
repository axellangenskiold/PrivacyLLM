import Foundation

/// A locally generated audio memo/podcast. Only the audio + metadata are kept;
/// the source text is not stored (privacy, and audio is the artifact).
nonisolated struct VoiceMemo: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    /// File name inside the store's audio directory (not an absolute path, so
    /// memos survive app-container path changes between launches).
    var audioFileName: String
    var durationSeconds: Double
    /// Resume point, persisted so playback continues where it stopped.
    var positionSeconds: Double
    var createdAt: Date
    var voiceQuality: TTSQuality

    init(
        id: UUID = UUID(),
        title: String,
        audioFileName: String,
        durationSeconds: Double,
        positionSeconds: Double = 0,
        createdAt: Date = .now,
        voiceQuality: TTSQuality
    ) {
        self.id = id
        self.title = title
        self.audioFileName = audioFileName
        self.durationSeconds = durationSeconds
        self.positionSeconds = positionSeconds
        self.createdAt = createdAt
        self.voiceQuality = voiceQuality
    }
}

/// What the composer starts from: a title and the lines to speak. Built blank
/// for pasted text, or from a conversation when forwarding a chat to audio.
nonisolated struct VoiceMemoDraft: Hashable, Sendable {
    var title: String
    var lines: [SpokenLine]

    /// Plain pasted text: one speaker.
    init(text: String = "", title: String = "") {
        self.title = title
        lines = text.isEmpty ? [] : [SpokenLine(text)]
    }

    init(title: String, lines: [SpokenLine]) {
        self.title = title
        self.lines = lines
    }

    /// Builds a two-voice script from a conversation: the person's turns read in
    /// one voice, the assistant's in another. System/tool/attachment rows and
    /// empty turns are skipped.
    static func fromConversation(_ conversation: Conversation, messages: [Message]) -> VoiceMemoDraft {
        let lines: [SpokenLine] = messages.compactMap { message in
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            switch message.role {
            case .user: return SpokenLine(text, role: .secondary)
            case .assistant: return SpokenLine(text, role: .primary)
            case .system, .tool, .attachment: return nil
            }
        }
        return VoiceMemoDraft(title: conversation.title, lines: lines)
    }

    var isEmpty: Bool {
        lines.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
