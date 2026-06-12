import MarkdownUI
import PrivacyUI
import SwiftUI

struct MessageBubble: View {
    let message: Message
    var isLastAssistant = false
    var onRegenerate: (() -> Void)?
    var onEdit: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    if message.role == .assistant, let reasoning = message.reasoning, !reasoning.isEmpty {
                        PVDisclosure("reasoning") {
                            Text(reasoning)
                        }
                    }
                    if message.role == .assistant {
                        // Assistant replies render markdown + highlighted code (FR-5).
                        Markdown(message.content)
                            .markdownTheme(.chat)
                            .markdownCodeSyntaxHighlighter(HighlightrSyntaxHighlighter(colorScheme: colorScheme))
                        if !message.sources.isEmpty {
                            SourceChips(sources: message.sources)
                        }
                    } else {
                        Text(message.content)
                    }
                }
                .textSelection(.enabled)
                .pvChatBubble(message.role == .user ? .user : .assistant)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    if message.role == .user, let onEdit {
                        Button(action: onEdit) {
                            Label("Edit & Re-run", systemImage: "pencil")
                        }
                    }
                    if isLastAssistant, let onRegenerate {
                        Button(action: onRegenerate) {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                    }
                }
                if let statLine {
                    PVStatLine(statLine)
                        .padding(.leading, 4)
                }
            }
            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "You said" : "Assistant said")
        .accessibilityValue(message.content)
    }

    /// "18.4 tok/s · qwen3-1.7b" under completed assistant replies.
    private var statLine: String? {
        guard message.role == .assistant else { return nil }
        var parts: [String] = []
        if let tps = message.stats?.tokensPerSecond {
            parts.append(String(format: "%.1f tok/s", tps))
        }
        if let modelID = message.modelID {
            parts.append(modelID)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The in-flight assistant reply; becomes a MessageBubble once persisted.
struct StreamingBubble: View {
    let text: String
    var reasoning: String = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if !reasoning.isEmpty {
                    // Expanded while the model is thinking; collapses in the
                    // persisted bubble (UX-6).
                    PVDisclosure("reasoning", initiallyExpanded: true) {
                        Text(reasoning)
                    }
                }
                if !text.isEmpty {
                    Markdown(text)
                        .markdownTheme(.chat)
                        .markdownCodeSyntaxHighlighter(HighlightrSyntaxHighlighter(colorScheme: colorScheme))
                }
            }
            .pvChatBubble(.assistant)
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Assistant is replying")
        .accessibilityValue(text.isEmpty ? reasoning : text)
    }
}

/// Attribution for search- or document-derived answers (FR-20, FR-27).
struct SourceChips: View {
    let sources: [SourceAttribution]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    chip(for: source)
                }
            }
        }
        .accessibilityLabel("Sources")
    }

    @ViewBuilder
    private func chip(for source: SourceAttribution) -> some View {
        if source.kind == .web, let urlString = source.urlString, let url = URL(string: urlString) {
            Link(destination: url) {
                chipLabel(source, icon: "globe")
            }
        } else {
            chipLabel(source, icon: "doc.text")
        }
    }

    private func chipLabel(_ source: SourceAttribution, icon: String) -> some View {
        PVChip(
            icon: icon,
            text: source.title,
            detail: source.pageNumber.map { "p.\($0)" }
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        MessageBubble(message: Message(conversationID: UUID(), role: .user, content: "What's on my calendar?"))
        MessageBubble(message: Message(
            conversationID: UUID(),
            role: .assistant,
            content: "I can't see your calendar — but everything you ask me stays on this device.",
            modelID: "qwen3-1.7b",
            stats: GenerationStats(tokensPerSecond: 18.4)
        ))
        StreamingBubble(text: "Streaming a longer reply right")
    }
    .padding()
    .pvScreen()
}
