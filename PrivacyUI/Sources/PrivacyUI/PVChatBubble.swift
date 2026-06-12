import SwiftUI

public enum PVBubbleRole: Sendable {
    case user
    case assistant
}

extension View {
    /// Chat bubble chrome. User: emerald-tinted gradient with accent hairline.
    /// Assistant: raised surface with neutral hairline.
    public func pvChatBubble(_ role: PVBubbleRole) -> some View {
        modifier(PVChatBubbleModifier(role: role))
    }
}

private struct PVChatBubbleModifier: ViewModifier {
    let role: PVBubbleRole

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: PVRadius.bubble, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PVRadius.bubble, style: .continuous)
                    .strokeBorder(role == .user ? Color.pvUserBubbleHairline : Color.pvHairline, lineWidth: 1)
            )
            .foregroundStyle(Color.pvTextPrimary)
    }

    private var fill: AnyShapeStyle {
        switch role {
        case .user:
            AnyShapeStyle(LinearGradient(
                colors: [.pvUserBubbleTop, .pvUserBubbleBottom],
                startPoint: .top,
                endPoint: .bottom
            ))
        case .assistant:
            AnyShapeStyle(Color.pvSurface)
        }
    }
}

/// Monospaced metadata line ("18.4 tok/s · qwen3-1.7b").
public struct PVStatLine: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(PVFont.metaSmall)
            .foregroundStyle(Color.pvTextSecondary)
    }
}

#Preview("Bubbles") {
    VStack(spacing: 12) {
        Text("What's the rent clause again?")
            .pvChatBubble(.user)
        Text("The lease (p.3) sets rent at **9 500 kr** per month.")
            .pvChatBubble(.assistant)
        PVStatLine("18.4 tok/s · qwen3-1.7b")
    }
    .padding()
    .pvScreen()
}
