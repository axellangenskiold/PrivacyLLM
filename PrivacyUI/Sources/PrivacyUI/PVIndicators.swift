import SwiftUI

/// Tiny mono status capsule overlaid on icons (e.g. the search globe).
public struct PVStatusBadge: View {
    public enum Kind {
        case on
        case off
    }

    private let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var body: some View {
        Text(kind == .on ? "ON" : "OFF")
            .font(.system(size: 8, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1.5)
            .background(kind == .on ? Color(pvFixed: 0x16A34A) : Color(pvFixed: 0xDC2626), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.pvBackground, lineWidth: 1.5))
            .accessibilityHidden(true) // hosts carry the state in their label
    }
}

extension Color {
    /// Scheme-independent color (badges keep their semantics in both modes).
    init(pvFixed hex: UInt32) {
        self.init(uiColor: UIColor(pvHex: hex))
    }
}

/// Static activity glyph: three emerald dots fading in emphasis.
///
/// Deliberately not animated and not a `ProgressView`. The chat transcript
/// is a lazy stack, and anything that updates continuously inside it makes
/// the container re-place its subviews every frame; under CPU contention
/// that becomes an unrecoverable main-thread loop (reproduced twice on the
/// iOS 26.2 simulator: first via the UIKit-bridged spinner re-resolving its
/// dynamic tint in `updateUIView`, then via a repeatForever SwiftUI opacity
/// animation flushing transactions through LazySubviewPlacements). Liveness
/// is carried by the streaming text itself; this glyph just marks the wait.
public struct PVActivityDots: View {
    private let dotSize: CGFloat

    public init(dotSize: CGFloat = 5) {
        self.dotSize = dotSize
    }

    public var body: some View {
        HStack(spacing: dotSize * 0.8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.pvAccent)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(1 - Double(index) * 0.35)
            }
        }
        .accessibilityHidden(true) // hosts label the activity
    }
}

/// Determinate progress capsule (pure SwiftUI; no UIKit bridge — see
/// PVActivityDots for why).
public struct PVProgressBar: View {
    private let value: Double

    public init(value: Double) {
        self.value = value.isFinite ? min(max(value, 0), 1) : 0
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.pvSurfaceRaised)
                Capsule()
                    .fill(Color.pvAccent)
                    .frame(width: max(proxy.size.width * value, 6))
            }
        }
        .frame(height: 6)
        .overlay(Capsule().strokeBorder(Color.pvHairline, lineWidth: 1))
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100))%")
    }
}

/// Citation / metadata chip.
public struct PVChip: View {
    private let icon: String
    private let text: String
    private let detail: String?

    public init(icon: String, text: String, detail: String? = nil) {
        self.icon = icon
        self.text = text
        self.detail = detail
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .foregroundStyle(Color.pvTextSecondary.opacity(0.7))
            }
        }
        .font(PVFont.metaSmall)
        .foregroundStyle(Color.pvTextSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.pvSurfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.pvHairline, lineWidth: 1))
    }
}

/// Full-width alert strip: egress (data leaving the device) or warnings.
public struct PVBanner: View {
    public enum Style {
        case egress
        case warning
    }

    private let style: Style
    private let icon: String
    private let text: String
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ style: Style, icon: String, text: String) {
        self.style = style
        self.icon = icon
        self.text = text
    }

    private var tint: Color {
        style == .egress ? Color(pvFixed: 0xFB923C) : .pvWarning
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .opacity(pulsing && !reduceMotion ? 0.25 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                    value: pulsing
                )
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
            Text(text)
                .font(PVFont.footnote.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.pvTextPrimary)
        .padding(.horizontal, PVSpacing.l)
        .padding(.vertical, 7)
        .background(tint.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle().fill(tint.opacity(0.5)).frame(height: 1)
        }
        .onAppear { pulsing = true }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Indicators") {
    VStack(spacing: 16) {
        PVBanner(.egress, icon: "arrow.up.forward.app.fill", text: "Searching the web — your query left this device")
        PVBanner(.warning, icon: "thermometer.high", text: "Device is warm — Fast mode is recommended")
        PVActivityDots()
        PVProgressBar(value: 0.62)
            .frame(maxWidth: 160)
        HStack {
            Image(systemName: "globe")
                .font(.system(size: 22))
                .overlay(alignment: .topTrailing) {
                    PVStatusBadge(.on).offset(x: 8, y: -5)
                }
            Image(systemName: "globe")
                .font(.system(size: 22))
                .overlay(alignment: .topTrailing) {
                    PVStatusBadge(.off).offset(x: 8, y: -5)
                }
        }
        .foregroundStyle(Color.pvTextSecondary)
        PVChip(icon: "globe", text: "Travel guide")
        PVChip(icon: "doc.text", text: "lease.pdf", detail: "p.3")
    }
    .padding()
    .pvScreen()
}
