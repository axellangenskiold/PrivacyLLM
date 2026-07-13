import PrivacyUI
import SwiftUI

/// Composer for a new voice memo: paste text (or arrive prefilled from a
/// forwarded conversation), pick a voice-quality tier, and generate the audio
/// locally. Dismisses itself when generation succeeds.
struct NewVoiceMemoView: View {
    let environment: AppEnvironment
    /// Prefilled when forwarding a conversation; blank otherwise.
    var draft = VoiceMemoDraft()
    var fromConversation = false
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var title = ""
    @State private var quality: TTSQuality = .standard
    @State private var qualities: [TTSQuality] = [.standard]
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                qualitySection
            }
            .scrollContentBackground(.hidden)
            .pvScreen()
            .navigationTitle(fromConversation ? "Conversation to Audio" : "New Voice Memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isGenerating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Button("Generate") { Task { await generate() } }
                            .disabled(!canGenerate)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isGenerating)
        .task {
            title = draft.title
            qualities = await environment.tts.availableQualities()
            if !qualities.contains(quality) { quality = qualities.first ?? .standard }
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        if fromConversation {
            Section("Source") {
                Label("\(draft.lines.count) turns from \"\(draft.title)\"", systemImage: "bubble.left.and.bubble.right")
                Text("Read back as a two-voice conversation.")
                    .font(.footnote)
                    .foregroundStyle(Color.pvTextSecondary)
            }
            .pvListRow()
        } else {
            Section("Text") {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .disabled(isGenerating)
                TextField("Title (optional)", text: $title)
                    .disabled(isGenerating)
            }
            .pvListRow()
        }
    }

    private var qualitySection: some View {
        Section {
            Picker("Voice quality", selection: $quality) {
                ForEach(qualities) { tier in
                    Text(tier.label).tag(tier)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isGenerating)
            Text(quality.detail)
                .font(.footnote)
                .foregroundStyle(Color.pvTextSecondary)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.pvWarning)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Generated on this device. Enhanced and Premium sound more natural but take longer and need a one-time voice download in iOS Settings › Accessibility › Spoken Content › Voices.")
        }
        .pvListRow()
    }

    private var canGenerate: Bool {
        if fromConversation { return !draft.isEmpty }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func generate() async {
        let lines: [SpokenLine]
        let resolvedTitle: String
        if fromConversation {
            lines = draft.lines
            resolvedTitle = draft.title.isEmpty ? String(localized: "Conversation") : draft.title
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            lines = [SpokenLine(trimmed)]
            let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedTitle = typed.isEmpty ? String(trimmed.prefix(40)) : typed
        }

        isGenerating = true
        errorMessage = nil
        let store = environment.voiceMemoStore
        let (fileName, url) = store.newAudioFile()
        do {
            let duration = try await environment.tts.synthesize(lines: lines, quality: quality, to: url)
            store.upsert(VoiceMemo(
                title: resolvedTitle,
                audioFileName: fileName,
                durationSeconds: duration,
                voiceQuality: quality
            ))
            onComplete?()
            dismiss()
        } catch {
            try? FileManager.default.removeItem(at: url)
            errorMessage = Self.message(for: error)
        }
        isGenerating = false
    }

    private static func message(for error: Error) -> String {
        switch error {
        case TTSError.nothingToSpeak:
            String(localized: "There's no text to read.")
        default:
            String(localized: "Couldn't generate audio. Try Standard quality, or a shorter text.")
        }
    }
}

#Preview {
    NewVoiceMemoView(environment: .mock())
}
