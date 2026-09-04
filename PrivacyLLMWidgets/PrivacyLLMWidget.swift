import SwiftUI
import WidgetKit

/// Home-screen widget (FR-47): a quick way back into the app.
///
/// Deliberately shows nothing about your chats. A widget renders on the home
/// and lock screen, where anyone holding the phone can read it — putting the
/// last message there would undo the point of the app. So this is a launcher,
/// and the only dynamic thing on it is the time of day.
struct QuickChatEntry: TimelineEntry {
    let date: Date
}

struct QuickChatProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickChatEntry {
        QuickChatEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickChatEntry) -> Void) {
        completion(QuickChatEntry(date: .now))
    }

    /// Nothing here changes on its own, so one entry and never reload.
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickChatEntry>) -> Void) {
        completion(Timeline(entries: [QuickChatEntry(date: .now)], policy: .never))
    }
}

struct QuickChatView: View {
    @Environment(\.widgetFamily) private var family

    private let charcoal = Color(red: 0.055, green: 0.067, blue: 0.075)
    private let emerald = Color(red: 0.204, green: 0.827, blue: 0.600)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: family == .systemSmall ? 26 : 30, weight: .medium))
                .foregroundStyle(emerald)
            Spacer(minLength: 0)
            Text("PrivacyLLM")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Private chat")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(charcoal, for: .widget)
    }
}

struct PrivacyLLMWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrivacyLLMQuickChat", provider: QuickChatProvider()) { _ in
            QuickChatView()
        }
        .configurationDisplayName("PrivacyLLM")
        .description("Open a private chat.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PrivacyLLMWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrivacyLLMWidget()
    }
}
