import PrivacyUI
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showPDFImporter = false

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                qualitySection
            }
            .scrollContentBackground(.hidden)
            .pvScreen()
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [UTType.pdf]) { result in
                importPDF(result)
            }
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
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .disabled(isGenerating)
                TextField("Title (optional)", text: $title)
                    .disabled(isGenerating)
                Button {
                    showPDFImporter = true
                } label: {
                    Label("Import from PDF…", systemImage: "doc.text")
                }
                .disabled(isGenerating)
            } header: {
                Text("Text")
            } footer: {
                Text("Paste text, or import a PDF to read it aloud.")
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

    /// Extracts a PDF's text into the editor. ponytail: synchronous PDFKit read
    /// on the main actor — fine for typical docs; move off-main if big PDFs stall.
    private func importPDF(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let pages = try PDFExtractor.extract(from: url, maxPages: 30)
            text = pages.map(\.text).joined(separator: "\n\n")
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
            errorMessage = nil
        } catch {
            errorMessage = DocumentsViewModel.message(for: error)
        }
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
