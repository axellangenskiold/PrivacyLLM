import SwiftUI

/// Collapsible section with a monospaced label — reasoning, advanced options.
public struct PVDisclosure<Content: View>: View {
    private let label: String
    private let icon: String
    private let content: Content
    @State private var isExpanded: Bool

    public init(
        _ label: String,
        icon: String = "brain",
        initiallyExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.icon = icon
        _isExpanded = State(initialValue: initiallyExpanded)
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                    Text(label)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(PVFont.metaBold)
                .foregroundStyle(Color.pvAccent)
            }
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
            if isExpanded {
                content
                    .font(PVFont.footnote)
                    .foregroundStyle(Color.pvTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A document attached to the conversation, shown inline in the transcript.
public struct PVAttachmentCard: View {
    public enum State {
        case ready
        case indexing
        case failed
    }

    private let title: String
    private let subtitle: String
    private let state: State

    public init(title: String, subtitle: String, state: State = .ready) {
        self.title = title
        self.subtitle = subtitle
        self.state = state
    }

    public var body: some View {
        HStack(spacing: PVSpacing.m) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.pvAccent)
                .frame(width: 40, height: 40)
                .background(Color.pvAccentWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PVFont.headline)
                    .foregroundStyle(Color.pvTextPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(PVFont.metaSmall)
                    .foregroundStyle(Color.pvTextSecondary)
            }
            Spacer(minLength: 0)
            stateView
        }
        .padding(PVSpacing.m)
        .pvCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stateView: some View {
        switch state {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.pvAccent)
        case .indexing:
            // PVActivityDots, not ProgressView: this card lives in the lazy
            // chat transcript where the bridged spinner can loop (see PVActivityDots).
            PVActivityDots(dotSize: 4)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.pvWarning)
        }
    }
}

/// Icon-led empty state with the vault glow.
public struct PVEmptyState: View {
    private let icon: String
    private let title: String
    private let message: String

    public init(icon: String, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: PVSpacing.l) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.pvAccent)
                .frame(width: 72, height: 72)
                .background(Color.pvAccentWash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .pvGlow(0.25)
            VStack(spacing: PVSpacing.xs) {
                Text(title)
                    .font(PVFont.title)
                    .foregroundStyle(Color.pvTextPrimary)
                Text(message)
                    .font(PVFont.footnote)
                    .foregroundStyle(Color.pvTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(PVSpacing.xl)
        // Title and message stay separate accessibility elements so they can
        // be queried by label (UI tests) and read in order by VoiceOver.
    }
}

#Preview("Containers") {
    VStack(spacing: 20) {
        PVDisclosure("reasoning · 1.2s", initiallyExpanded: true) {
            Text("The user asked about rent; the lease excerpt on page 3 has the amount.")
        }
        .padding()
        .pvCard()
        PVAttachmentCard(title: "lease.pdf", subtitle: "12 pages · 240 KB", state: .ready)
        PVEmptyState(
            icon: "bubble.left.and.bubble.right",
            title: "No chats yet",
            message: "Start a private conversation that never leaves your device."
        )
    }
    .padding()
    .pvScreen()
}
