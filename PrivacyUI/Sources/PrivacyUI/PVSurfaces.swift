import SwiftUI

/// The vault backdrop: charcoal floor with a faint emerald aura at the top.
/// Static (no animation) so it's Reduce Motion-neutral.
public struct PVScreenBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            Color.pvBackground
            RadialGradient(
                colors: [Color.pvAccent.opacity(0.08), .clear],
                center: .init(x: 0.5, y: -0.15),
                startRadius: 0,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Applies the vault backdrop behind any screen.
    public func pvScreen() -> some View {
        background(PVScreenBackground())
    }

    /// Raised card chrome: surface fill, continuous corners, hairline border.
    public func pvCard(radius: CGFloat = PVRadius.card) -> some View {
        background(Color.pvSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.pvHairline, lineWidth: 1)
            )
    }

    /// Row chrome for use inside `List`/`Form` rows.
    public func pvListRow() -> some View {
        listRowBackground(Color.pvSurface)
            .listRowSeparatorTint(Color.pvHairline)
    }
}

#Preview("Background") {
    VStack {
        Text("PrivacyLLM").font(PVFont.display).foregroundStyle(Color.pvTextPrimary)
        Text("vault floor").font(PVFont.meta).foregroundStyle(Color.pvTextSecondary)
        Text("Card").font(PVFont.body).foregroundStyle(Color.pvTextPrimary)
            .padding(20)
            .pvCard()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .pvScreen()
}
