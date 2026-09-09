import PrivacyUI
import SwiftUI

/// Where feedback goes. GitHub is the default because it's public, threaded,
/// and needs nothing from us; email is for the many people who have no GitHub
/// account.
nonisolated enum FeedbackDestination: String, CaseIterable, Identifiable, Sendable {
    case github
    case email

    var id: String { rawValue }

    var label: String {
        switch self {
        case .github: String(localized: "GitHub")
        case .email: String(localized: "Email")
        }
    }
}

/// In-app feedback (FR-45). The text never goes through us: "Send" hands it to
/// GitHub or to Mail, prefilled, and the user sends it themselves.
///
/// ponytail: no backend and no token. Posting the issue from the app would mean
/// shipping a GitHub token inside the binary, where anyone can pull it out.
struct FeedbackView: View {
    static let repository = "axellangenskiold/PrivacyLLM"
    /// Same address as the support page (support/index.html).
    static let supportEmail = "axel@langenskiold.se"

    private let environment: AppEnvironment
    @State private var text = ""
    @State private var destination = FeedbackDestination.github
    @State private var openFailed = false
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
                }
                .pvListRow()

                Section {
                    Picker("Send with", selection: $destination) {
                        ForEach(FeedbackDestination.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("feedback-destination")
                } footer: {
                    Text(destination == .github
                        ? "Recommended. Opens GitHub so you can post it — you'll see replies there. Needs a GitHub account."
                        : "Opens Mail with the message ready to send to \(Self.supportEmail).")
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
            .alert("Couldn't open Mail", isPresented: $openFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No mail account is set up. You can write to \(Self.supportEmail).")
            }
        }
    }

    private func send() {
        let destination = destination
        guard let url = Self.url(for: destination, body: text) else { return }
        let store = environment.egressEventStore
        Task {
            // Handing the text to another app is still data leaving; log it (PR-14).
            try? await store.append(EgressEvent(
                kind: .feedback,
                destinationHost: destination == .github ? "github.com" : Self.emailHost,
                detail: destination == .github
                    ? String(localized: "Feedback opened in browser")
                    : String(localized: "Feedback opened in Mail")
            ))
        }
        UIApplication.shared.open(url) { opened in
            // A device with no mail account silently refuses; say so rather than
            // looking like the message was sent.
            if opened {
                dismiss()
            } else {
                openFailed = true
            }
        }
    }

    static var emailHost: String {
        supportEmail.split(separator: "@").last.map(String.init) ?? supportEmail
    }

    static func url(for destination: FeedbackDestination, body: String) -> URL? {
        switch destination {
        case .github: issueURL(body: body)
        case .email: mailURL(body: body)
        }
    }

    static func issueURL(body: String, repository: String = FeedbackView.repository) -> URL? {
        guard let trimmed = trimmed(body) else { return nil }
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: subject(from: trimmed)),
            URLQueryItem(name: "body", value: trimmed + Self.signature),
            URLQueryItem(name: "labels", value: "feedback"),
        ]
        return components?.url
    }

    static func mailURL(body: String, address: String = FeedbackView.supportEmail) -> URL? {
        guard let trimmed = trimmed(body) else { return nil }
        var components = URLComponents(string: "mailto:\(address)")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: "PrivacyLLM: " + subject(from: trimmed)),
            URLQueryItem(name: "body", value: trimmed + Self.signature),
        ]
        return components?.url
    }

    private static func trimmed(_ body: String) -> String? {
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// First line, clipped — enough to scan an inbox or issue list by.
    private static func subject(from trimmed: String) -> String {
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return String(firstLine.prefix(60))
    }

    /// Version only. Enough to triage, and nothing that identifies anyone.
    private static var signature: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "\n\n—\nPrivacyLLM \(version)"
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
