import MarkdownUI
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
            VStack(alignment: .leading, spacing: 8) {
                if message.role == .assistant, let reasoning = message.reasoning, !reasoning.isEmpty {
                    ReasoningDisclosure(text: reasoning, initiallyExpanded: false)
                }
                if message.role == .assistant {
                    // Assistant replies render markdown + highlighted code (FR-5).
                    Markdown(message.content)
                        .markdownTheme(.chat)
                        .markdownCodeSyntaxHighlighter(HighlightrSyntaxHighlighter(colorScheme: colorScheme))
                } else {
                    Text(message.content)
                }
            }
            .chatBubbleStyle(isUser: message.role == .user)
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
            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "You said" : "Assistant said")
        .accessibilityValue(message.content)
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
                    ReasoningDisclosure(text: reasoning, initiallyExpanded: true)
                }
                if !text.isEmpty {
                    Markdown(text)
                        .markdownTheme(.chat)
                        .markdownCodeSyntaxHighlighter(HighlightrSyntaxHighlighter(colorScheme: colorScheme))
                }
            }
            .chatBubbleStyle(isUser: false)
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Assistant is replying")
        .accessibilityValue(text.isEmpty ? reasoning : text)
    }
}

struct ReasoningDisclosure: View {
    let text: String
    let initiallyExpanded: Bool
    @State private var isExpanded: Bool

    init(text: String, initiallyExpanded: Bool) {
        self.text = text
        self.initiallyExpanded = initiallyExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Reasoning", systemImage: "brain")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func chatBubbleStyle(isUser: Bool) -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isUser ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .textSelection(.enabled)
    }
}

#Preview {
    VStack(spacing: 12) {
        MessageBubble(message: Message(conversationID: UUID(), role: .user, content: "What's on my calendar?"))
        MessageBubble(message: Message(conversationID: UUID(), role: .assistant, content: "I can't see your calendar — but everything you ask me stays on this device."))
        StreamingBubble(text: "Streaming a longer reply right")
    }
    .padding()
}
