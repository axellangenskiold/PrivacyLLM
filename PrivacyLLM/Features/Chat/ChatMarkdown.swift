import Highlightr
import MarkdownUI
import SwiftUI

/// Markdown theme for assistant bubbles (FR-5): tightened spacing, fenced code
/// blocks with a language header and copy button.
extension MarkdownUI.Theme {
    static let chat = MarkdownUI.Theme()
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            BackgroundColor(Color(.secondarySystemFill))
        }
        .codeBlock { configuration in
            ChatCodeBlock(configuration: configuration)
        }
}

struct ChatCodeBlock: View {
    let configuration: CodeBlockConfiguration
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.language ?? "code")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = configuration.content
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill))

            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .padding(12)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .markdownMargin(top: .em(0.6), bottom: .em(0.6))
    }
}

/// Syntax highlighting through Highlightr's bundled highlight.js — runs fully
/// offline, no script is ever fetched (PR-16). Instances are cached because
/// creating a JS context is expensive; only ever touched from view rendering
/// on the main thread.
nonisolated struct HighlightrSyntaxHighlighter: CodeSyntaxHighlighter {
    private let themeName: String

    nonisolated(unsafe) private static var cache: [String: Highlightr] = [:]

    init(colorScheme: ColorScheme) {
        themeName = colorScheme == .dark ? "atom-one-dark" : "xcode"
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        guard let language, !language.isEmpty,
              let highlightr = Self.highlighter(theme: themeName),
              let highlighted = highlightr.highlight(content, as: language, fastRender: true)
        else {
            return Text(content)
        }
        return Text(AttributedString(highlighted))
    }

    private static func highlighter(theme: String) -> Highlightr? {
        if let cached = cache[theme] { return cached }
        guard let highlightr = Highlightr() else { return nil }
        highlightr.setTheme(to: theme)
        highlightr.theme.setCodeFont(UIFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        cache[theme] = highlightr
        return highlightr
    }
}
