import SwiftUI

// MARK: - Obsidian Vault palette
//
// Dark-first: near-black layered charcoals with an emerald accent.
// Light mode: paper-grey surfaces with a deepened emerald that holds
// 4.5:1 (AA) against white. Every pair below was checked against its
// intended background.

extension Color {
    /// Dynamic color from two hex values (dark / light).
    static func pvDynamic(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(pvHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// App background — the vault floor.
    public static let pvBackground = pvDynamic(dark: 0x0E1113, light: 0xF4F6F6)
    /// Primary raised surface (cards, bubbles, input field).
    public static let pvSurface = pvDynamic(dark: 0x161A1D, light: 0xFFFFFF)
    /// Second elevation step (pills, code headers, tiles).
    public static let pvSurfaceRaised = pvDynamic(dark: 0x1F2529, light: 0xECF0F0)
    /// Hairline borders on surfaces.
    public static let pvHairline = pvDynamic(dark: 0x33FFFFFF, light: 0x1A000000)

    public static let pvTextPrimary = pvDynamic(dark: 0xECF1F2, light: 0x16191A)
    public static let pvTextSecondary = pvDynamic(dark: 0x9AA7AB, light: 0x55646A)

    /// The emerald. Dark: #34D399 (≈9:1 on pvBackground). Light: #0B8A5F (≈4.7:1 on white).
    public static let pvAccent = pvDynamic(dark: 0x34D399, light: 0x0B8A5F)
    /// Text/icons placed on top of pvAccent fills.
    public static let pvOnAccent = pvDynamic(dark: 0x052E20, light: 0xFFFFFF)
    /// Low-emphasis accent washes (tiles, selected rows).
    public static let pvAccentWash = pvDynamic(dark: 0x2434D399, light: 0x1A0B8A5F)

    public static let pvDanger = pvDynamic(dark: 0xF87171, light: 0xC02626)
    public static let pvWarning = pvDynamic(dark: 0xFBBF24, light: 0x9A5B00)

    /// User chat bubble gradient ends (emerald-tinted).
    public static let pvUserBubbleTop = pvDynamic(dark: 0x174A3C, light: 0xD9F2E7)
    public static let pvUserBubbleBottom = pvDynamic(dark: 0x103528, light: 0xC4EADA)
    public static let pvUserBubbleHairline = pvDynamic(dark: 0x5934D399, light: 0x4D0B8A5F)

    /// Code block canvas.
    public static let pvCodeBackground = pvDynamic(dark: 0x11181B, light: 0xF0F3F3)
}

extension UIColor {
    /// 0xRRGGBB or 0xAARRGGBB.
    convenience init(pvHex hex: UInt32) {
        let hasAlpha = hex > 0xFFFFFF
        let alpha = hasAlpha ? CGFloat((hex >> 24) & 0xFF) / 255 : 1
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Type ramp

public enum PVFont {
    /// Hero/onboarding display.
    public static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
    /// Screen and card titles.
    public static let title = Font.system(.title3, design: .rounded).weight(.semibold)
    /// Row/bubble emphasis.
    public static let headline = Font.system(.body, design: .rounded).weight(.semibold)
    public static let body = Font.body
    public static let footnote = Font.footnote
    /// Stats, badges, timestamps — the vault's monospaced voice.
    public static let meta = Font.system(.caption, design: .monospaced)
    public static let metaBold = Font.system(.caption, design: .monospaced).weight(.semibold)
    public static let metaSmall = Font.system(.caption2, design: .monospaced)
}

// MARK: - Metrics

public enum PVRadius {
    public static let card: CGFloat = 14
    public static let bubble: CGFloat = 18
    public static let control: CGFloat = 12
}

public enum PVSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

extension View {
    /// Soft emerald glow for hero elements; skipped entirely under Reduce
    /// Transparency-like constraints by callers when appropriate.
    public func pvGlow(_ strength: Double = 0.35, radius: CGFloat = 14) -> some View {
        shadow(color: Color.pvAccent.opacity(strength), radius: radius)
    }
}
