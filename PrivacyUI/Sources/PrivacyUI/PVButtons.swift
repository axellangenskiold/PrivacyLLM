import SwiftUI

/// Filled-emerald call to action with a soft glow.
public struct PVPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PVFont.headline)
            .foregroundStyle(Color.pvOnAccent)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                Color.pvAccent.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: PVRadius.card, style: .continuous)
            )
            .pvGlow(configuration.isPressed ? 0.15 : 0.3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PVPrimaryButtonStyle {
    public static var pvPrimary: PVPrimaryButtonStyle { PVPrimaryButtonStyle() }
}

/// Compact bordered action ("Get", "Retry").
public struct PVCompactButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PVFont.headline)
            .foregroundStyle(Color.pvAccent)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(Color.pvAccentWash, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.pvAccent.opacity(0.4), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PVCompactButtonStyle {
    public static var pvCompact: PVCompactButtonStyle { PVCompactButtonStyle() }
}

/// Circular icon button used across toolbars and the chat input bar.
public struct PVIconButton: View {
    public enum Style {
        /// Quiet glyph on the surface (paperclip, secondary actions).
        case plain
        /// Emerald-filled circle (send).
        case filled
        /// Surface circle with hairline (jump-to-bottom, overlays).
        case surface
        /// Red-tinted destructive/recording state.
        case alert
    }

    private let systemName: String
    private let style: Style
    private let size: CGFloat
    private let action: () -> Void

    public init(_ systemName: String, style: Style = .plain, size: CGFloat = 20, action: @escaping () -> Void) {
        self.systemName = systemName
        self.style = style
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size + 16, height: size + 16)
                .background(background, in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        style == .surface ? Color.pvHairline : .clear,
                        lineWidth: 1
                    )
                )
        }
    }

    private var foreground: Color {
        switch style {
        case .plain: .pvTextSecondary
        case .filled: .pvOnAccent
        case .surface: .pvTextPrimary
        case .alert: .pvDanger
        }
    }

    private var background: Color {
        switch style {
        case .plain: .clear
        case .filled: .pvAccent
        case .surface: .pvSurfaceRaised
        case .alert: .pvDanger.opacity(0.15)
        }
    }
}

#Preview("Buttons") {
    VStack(spacing: 16) {
        Button("Start chatting") {}
            .buttonStyle(.pvPrimary)
        Button("Get") {}
            .buttonStyle(.pvCompact)
        HStack(spacing: 12) {
            PVIconButton("paperclip") {}
            PVIconButton("arrow.up", style: .filled) {}
            PVIconButton("arrow.down", style: .surface, size: 15) {}
            PVIconButton("mic.badge.xmark", style: .alert) {}
        }
    }
    .padding()
    .pvScreen()
}
