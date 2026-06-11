import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    private let environment: AppEnvironment
    @State private var viewModel: ChatViewModel
    @State private var thermalState = ProcessInfo.processInfo.thermalState
    @State private var editTarget: Message?
    @State private var editText = ""
    @State private var showSystemPrompt = false
    @State private var systemPromptText = ""
    @State private var showAttachImporter = false
    @FocusState private var inputFocused: Bool

    init(conversation: Conversation, environment: AppEnvironment) {
        self.environment = environment
        _viewModel = State(initialValue: ChatViewModel(conversation: conversation, environment: environment))
    }

    var body: some View {
        VStack(spacing: 0) {
            if environment.egressMonitor.isSearchInFlight {
                EgressBadge()
            }
            if thermalState == .serious || thermalState == .critical {
                thermalBanner
            }
            messageList
            inputBar
        }
        .navigationTitle(viewModel.conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: roleBinding) {
                    Text("Fast").tag(ModelRole.fast)
                    Text("Thinking").tag(ModelRole.thinking)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .accessibilityLabel("Model mode")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        systemPromptText = viewModel.conversation.systemPrompt ?? ""
                        showSystemPrompt = true
                    } label: {
                        Label("System Prompt", systemImage: "person.text.rectangle")
                    }
                    ShareLink(
                        item: viewModel.exportMarkdown(),
                        preview: SharePreview(viewModel.conversation.title)
                    ) {
                        Label("Share as Markdown", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = viewModel.exportPlainText()
                    } label: {
                        Label("Copy as Text", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Conversation options")
            }
        }
        .sheet(item: $editTarget) { message in
            editSheet(for: message)
        }
        .fileImporter(isPresented: $showAttachImporter, allowedContentTypes: [UTType.pdf]) { result in
            if case .success(let url) = result {
                viewModel.attachDocument(at: url)
            }
        }
        .sheet(isPresented: $showSystemPrompt) {
            systemPromptSheet
        }
        .task { await viewModel.loadMessages() }
        .onReceive(
            NotificationCenter.default
                .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    private var roleBinding: Binding<ModelRole> {
        Binding(
            get: { viewModel.activeRole },
            set: { viewModel.setActiveRole($0) }
        )
    }

    private var thermalBanner: some View {
        Label("Device is warm — Fast mode is recommended", systemImage: "thermometer.high")
            .font(.footnote)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.15))
    }

    private func editSheet(for message: Message) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Everything after this message will be replaced by a new reply.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $editText)
                    .padding(8)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .navigationTitle("Edit Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Re-run") {
                        viewModel.editAndRerun(message, newText: editText)
                        editTarget = nil
                    }
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var systemPromptSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $systemPromptText)
                        .frame(minHeight: 140)
                } header: {
                    Text("Persona for this conversation")
                } footer: {
                    Text("Tells the model how to behave in this chat. Leave empty to use the global default from Settings.")
                }
            }
            .navigationTitle("System Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSystemPrompt = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.updateSystemPrompt(systemPromptText)
                        showSystemPrompt = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty, !viewModel.isBusy {
                        emptyHint
                            .padding(.top, 48)
                    }
                    if viewModel.isIndexingAttachment {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Indexing document on this device…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let notice = viewModel.attachmentNotice {
                        HStack(spacing: 8) {
                            Image(systemName: "paperclip")
                                .foregroundStyle(.secondary)
                            Text(notice)
                                .font(.footnote)
                            Spacer()
                            Button("OK") { viewModel.dismissAttachmentNotice() }
                                .font(.footnote.bold())
                        }
                        .padding(10)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(viewModel.messages) { message in
                        MessageBubble(
                            message: message,
                            isLastAssistant: message.role == .assistant && message.id == viewModel.messages.last?.id,
                            onRegenerate: { viewModel.regenerate() },
                            onEdit: message.role == .user ? {
                                editText = message.content
                                editTarget = message
                            } : nil
                        )
                    }
                    streamingRow
                    if let error = viewModel.errorMessage {
                        errorRow(error)
                    }
                    if viewModel.voicePermissionDenied {
                        voicePermissionRow
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.streamingText) {
                proxy.scrollTo("bottom")
            }
            .onChange(of: viewModel.streamingReasoning) {
                proxy.scrollTo("bottom")
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    @ViewBuilder
    private var streamingRow: some View {
        ForEach(viewModel.toolActivity) { activity in
            toolActivityRow(activity)
        }
        if !viewModel.streamingText.isEmpty || !viewModel.streamingReasoning.isEmpty {
            StreamingBubble(text: viewModel.streamingText, reasoning: viewModel.streamingReasoning)
        } else if case .loadingModel(let progress) = viewModel.phase {
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .frame(maxWidth: 160)
                Text("Loading model…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else if viewModel.phase == .generating {
            HStack(spacing: 8) {
                ProgressView()
                Text("Thinking…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func toolActivityRow(_ activity: ChatViewModel.ToolActivity) -> some View {
        HStack(spacing: 8) {
            if activity.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: activity.isError ? "xmark.circle" : "checkmark.circle")
                    .foregroundStyle(activity.isError ? .orange : .green)
                    .font(.footnote)
            }
            Text(Self.toolDisplayName(activity.name))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private static func toolDisplayName(_ name: String) -> String {
        switch name {
        case "current_datetime": String(localized: "Checking the clock")
        case "calculate": String(localized: "Calculating")
        case "convert_units": String(localized: "Converting units")
        case "web_search": String(localized: "Searching the web")
        default: String(localized: "Running \(name)")
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Private chat")
                .font(.headline)
            Text("Everything here is generated and stored on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    /// Clear guidance when mic/speech permission is denied (FR-35).
    private var voicePermissionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Microphone access is off", systemImage: "mic.slash.fill")
                .font(.footnote.bold())
            Text("To dictate messages, allow microphone and speech recognition in Settings. Everything is transcribed on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote.bold())
                Button("Dismiss") { viewModel.dismissVoicePermissionHelp() }
                    .font(.footnote)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
            Spacer()
            Button("Dismiss") { viewModel.dismissError() }
                .font(.footnote.bold())
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var inputBar: some View {
        @Bindable var viewModel = viewModel
        return HStack(alignment: .bottom, spacing: 8) {
            Button {
                showAttachImporter = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 21))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 5)
            .accessibilityLabel("Attach a PDF to this chat")
            Button {
                viewModel.setSearchEnabled(!viewModel.searchEnabled)
            } label: {
                Image(systemName: viewModel.searchEnabled ? "globe" : "globe.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(viewModel.searchEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .padding(.bottom, 4)
            .accessibilityLabel(viewModel.searchEnabled ? "Web search on" : "Web search off")
            .accessibilityHint("Toggles whether the assistant may search the web")
            TextField("Message", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                .focused($inputFocused)
                .accessibilityLabel("Message input")
            if viewModel.isBusy {
                Button {
                    viewModel.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                }
                .accessibilityLabel("Stop generating")
            } else if viewModel.isRecording {
                Button {
                    viewModel.toggleRecording()
                } label: {
                    Image(systemName: "mic.badge.xmark")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, options: .repeating)
                }
                .accessibilityLabel("Stop dictation")
            } else if viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    viewModel.toggleRecording()
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 30))
                }
                .accessibilityLabel("Dictate message")
            } else {
                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Unmistakable signal that a query is leaving the device right now
/// (FR-21, PR-13, UX-5).
struct EgressBadge: View {
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label("Searching the web — your query left this device", systemImage: "arrow.up.forward.app.fill")
            .font(.footnote.bold())
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.orange)
            .opacity(pulsing && !reduceMotion ? 0.7 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
            .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: .preview, environment: AppEnvironment.mock())
    }
}
