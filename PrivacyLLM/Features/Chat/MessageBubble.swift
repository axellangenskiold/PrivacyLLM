import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }
            Text(message.content)
                .chatBubbleStyle(isUser: message.role == .user)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
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

    var body: some View {
        HStack(alignment: .bottom) {
            Text(text)
                .chatBubbleStyle(isUser: false)
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Assistant is replying")
        .accessibilityValue(text)
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
