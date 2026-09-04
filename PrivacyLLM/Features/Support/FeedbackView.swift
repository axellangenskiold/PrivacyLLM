import PrivacyUI
import SwiftUI

/// In-app feedback (FR-45). The text never goes through us: "Send" opens a
/// prefilled GitHub issue in the browser and the user posts it themselves,
/// under their own account.
///
/// ponytail: no backend and no token. Posting the issue from the app would mean
/// shipping a GitHub token inside the binary, where anyone can pull it out. If
/// this ever needs to work without a GitHub account, the next rung is a mailto:
/// — still no server.
struct FeedbackView: View {
    static let repository = "axellangenskiold/PrivacyLLM"

    private let environment: AppEnvironment
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What would you like?", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .accessibilityIdentifier("feedback-text")
                } footer: {
                    Text("Opens GitHub so you can post it. Nothing is sent from the app.")
                }
                .pvListRow()
            }
            .scrollContentBackground(.hidden)
            .pvScreen()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("feedback-send")
                }
            }
        }
    }

    private func send() {
        guard let url = Self.issueURL(body: text) else { return }
        let store = environment.egressEventStore
        Task {
            // Leaving for the browser is still data leaving; log it like the rest (PR-14).
            try? await store.append(EgressEvent(
                kind: .feedback,
                destinationHost: "github.com",
                detail: String(localized: "Feedback opened in browser")
            ))
        }
        UIApplication.shared.open(url)
        dismiss()
    }

    static func issueURL(body: String, repository: String = FeedbackView.repository) -> URL? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: String(trimmed.prefix(60))),
            URLQueryItem(name: "body", value: trimmed),
            URLQueryItem(name: "labels", value: "feedback"),
        ]
        return components?.url
    }
}

/// Decides when to ask "anything you'd like?" — every 5th launch, four times
/// ever, and never again once the user has actually sent something.
nonisolated struct FeedbackPrompt: Sendable {
    static let launchInterval = 5
    static let maxPrompts = 4

    let settingsStore: SettingsStore

    /// Call once per launch. Returns true when this launch should ask.
    func registerLaunchAndShouldAsk() async -> Bool {
        let launches = ((try? await settingsStore.value(for: .launchCount, default: 0)) ?? 0) + 1
        try? await settingsStore.set(launches, for: .launchCount)

        let shown = (try? await settingsStore.value(for: .feedbackPromptCount, default: 0)) ?? 0
        guard shown < Self.maxPrompts, launches % Self.launchInterval == 0 else { return false }
        try? await settingsStore.set(shown + 1, for: .feedbackPromptCount)
        return true
    }

    /// Stops the prompt for good — they've told us something already.
    func silence() async {
        try? await settingsStore.set(Self.maxPrompts, for: .feedbackPromptCount)
    }
}
