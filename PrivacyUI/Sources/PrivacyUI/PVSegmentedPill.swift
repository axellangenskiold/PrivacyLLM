import SwiftUI

/// Two-or-more-way pill selector with a sliding emerald thumb. Replaces the
/// native segmented picker in the vault identity. Children expose selection
/// traits so assistive tech and UI tests can read the state.
public struct PVSegmentedPill<Value: Hashable>: View {
    public struct Option {
        let value: Value
        let label: String

        public init(_ value: Value, label: String) {
            self.value = value
            self.label = label
        }
    }

    private let options: [Option]
    private let accessibilityLabel: String
    @Binding private var selection: Value
    @Namespace private var thumbNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<Value>, accessibilityLabel: String, options: [Option]) {
        _selection = selection
        self.accessibilityLabel = accessibilityLabel
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                segment(for: option)
            }
        }
        .padding(3)
        .background(Color.pvSurfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.pvHairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func segment(for option: Option) -> some View {
        let isSelected = option.value == selection
        return Button {
            if reduceMotion {
                selection = option.value
            } else {
                withAnimation(.snappy(duration: 0.2)) {
                    selection = option.value
                }
            }
        } label: {
            Text(option.label)
                .font(PVFont.metaBold)
                .foregroundStyle(isSelected ? Color.pvOnAccent : Color.pvTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.pvAccent)
                            .matchedGeometryEffect(id: "pv-thumb", in: thumbNamespace)
                    }
                }
        }
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Segmented") {
    struct Demo: View {
        @State private var mode = "fast"

        var body: some View {
            PVSegmentedPill(
                selection: $mode,
                accessibilityLabel: "Model mode",
                options: [.init("fast", label: "Fast"), .init("thinking", label: "Thinking")]
            )
            .padding()
            .pvScreen()
        }
    }
    return Demo()
}
