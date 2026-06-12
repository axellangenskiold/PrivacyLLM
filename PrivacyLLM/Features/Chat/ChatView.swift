import Combine
import PrivacyUI
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
    /// Follows the live tail only while the user is at the bottom; scrolling
    /// up during generation stops the auto-scroll so earlier text is readable.
    @State private var isPinnedToBottom = true
    @State private var userIsScrolling = false
    @State private var scrollToBottomTrigger = 0
    @FocusState private var inputFocused: Bool

    init(conversation: Conversation, environment: AppEnvironment) {
        self.environment = environment
        _viewModel = State(initialValue: ChatViewModel(conversation: conversation, environment: environment))
    }

    var body: some View {
        VStack(spacing: 0) {
            if environment.egressMonitor.isSearchInFlight {
                PVBanner(.egress, icon: "arrow.up.forward.app.fill", text: "Searching the web — your query left this device")
            }
            if thermalState == .serious || thermalState == .critical {
                PVBanner(.warning, icon: "thermometer.high", text: "Device is warm — Fast mode is recommended")
            }
            messageList
            inputBar
        }
        .pvScreen()
        .navigationTitle(viewModel.conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                PVSegmentedPill(
                    selection: roleBinding,
                    accessibilityLabel: "Model mode",
                    options: [
                        .init(ModelRole.fast, label: "Fast"),
                        .init(ModelRole.thinking, label: "Thinking"),
                    ]
                )
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
                    ForEach(viewModel.messages) { message in
                        if message.role == .attachment {
                            PVAttachmentCard(
                                title: message.content,
                                subtitle: "PDF · indexed on this device",
                                state: .ready
                            )
                            .accessibilityLabel("Attached document: \(message.content)")
                        } else {
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
                    }
                    if viewModel.isIndexingAttachment {
                        PVAttachmentCard(
                            title: "Indexing document…",
                            subtitle: "everything stays on this device",
                            state: .indexing
                        )
                        .accessibilityLabel("Indexing document on this device…")
                    }
                    if let notice = viewModel.attachmentNotice {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.pvWarning)
                            Text(notice)
                                .font(.footnote)
                                .foregroundStyle(Color.pvTextPrimary)
                            Spacer()
                            Button("OK") { viewModel.dismissAttachmentNotice() }
                                .font(.footnote.bold())
                                .foregroundStyle(Color.pvAccent)
                        }
                        .padding(PVSpacing.m)
                        .pvCard()
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
            // Only user-driven scrolling away from the bottom unpins;
            // returning to the bottom re-pins. Content growth alone must
            // never unpin, or following would die on the first streamed token.
            .onScrollPhaseChange { _, newPhase in
                userIsScrolling = newPhase == .tracking || newPhase == .interacting
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 60
            } action: { _, isNearBottom in
                if isNearBottom {
                    isPinnedToBottom = true
                } else if userIsScrolling {
                    isPinnedToBottom = false
                }
            }
            .onChange(of: viewModel.streamingText) {
                if isPinnedToBottom { proxy.scrollTo("bottom") }
            }
            .onChange(of: viewModel.streamingReasoning) {
                if isPinnedToBottom { proxy.scrollTo("bottom") }
            }
            .onChange(of: viewModel.messages.count) {
                if isPinnedToBottom {
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
            .onChange(of: scrollToBottomTrigger) {
                withAnimation { proxy.scrollTo("bottom") }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom {
                    jumpToBottomButton
                }
            }
        }
    }

    private var jumpToBottomButton: some View {
        PVIconButton("arrow.down", style: .surface, size: 15) {
            isPinnedToBottom = true
            scrollToBottomTrigger &+= 1
        }
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .accessibilityLabel("Scroll to latest")
        .transition(.opacity.combined(with: .scale))
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
                    .tint(Color.pvAccent)
                Text("loading model…")
                    .font(PVFont.meta)
                    .foregroundStyle(Color.pvTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading model…")
        } else if viewModel.phase == .generating {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Color.pvAccent)
                Text("thinking…")
                    .font(PVFont.meta)
                    .foregroundStyle(Color.pvTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Thinking…")
        }
    }

    private func toolActivityRow(_ activity: ChatViewModel.ToolActivity) -> some View {
        HStack(spacing: 8) {
            if activity.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: activity.isError ? "xmark.circle" : "checkmark.circle")
                    .foregroundStyle(activity.isError ? Color.pvWarning : Color.pvAccent)
                    .font(.footnote)
            }
            Text(Self.toolDisplayName(activity.name))
                .font(PVFont.meta)
                .foregroundStyle(Color.pvTextSecondary)
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
        PVEmptyState(
            icon: "lock.shield",
            title: "Private chat",
            message: "Everything here is generated and stored on this device."
        )
    }

    /// Clear guidance when mic/speech permission is denied (FR-35).
    private var voicePermissionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Microphone access is off", systemImage: "mic.slash.fill")
                .font(PVFont.headline)
                .foregroundStyle(Color.pvTextPrimary)
            Text("To dictate messages, allow microphone and speech recognition in Settings. Everything is transcribed on this device.")
                .font(.footnote)
                .foregroundStyle(Color.pvTextSecondary)
            HStack {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.pvCompact)
                Button("Dismiss") { viewModel.dismissVoicePermissionHelp() }
                    .font(.footnote)
                    .foregroundStyle(Color.pvTextSecondary)
            }
        }
        .padding(PVSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pvCard()
    }

    private func errorRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.pvWarning)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.pvTextPrimary)
            Spacer()
            Button("Dismiss") { viewModel.dismissError() }
                .font(.footnote.bold())
                .foregroundStyle(Color.pvAccent)
        }
        .padding(PVSpacing.m)
        .pvCard()
    }

    private var inputBar: some View {
        @Bindable var viewModel = viewModel
        return HStack(alignment: .bottom, spacing: 6) {
            PVIconButton("paperclip", size: 18) {
                showAttachImporter = true
            }
            .accessibilityLabel("Attach a PDF to this chat")
            searchToggleButton
            TextField("Message", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.pvSurface, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .strokeBorder(Color.pvHairline, lineWidth: 1)
                )
                .focused($inputFocused)
                .accessibilityLabel("Message input")
            if viewModel.isBusy {
                PVIconButton("stop.fill", style: .alert, size: 16) {
                    viewModel.stop()
                }
                .accessibilityLabel("Stop generating")
            } else if viewModel.isRecording {
                Button {
                    viewModel.toggleRecording()
                } label: {
                    Image(systemName: "mic.badge.xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.pvDanger)
                        .symbolEffect(.pulse, options: .repeating)
                        .frame(width: 34, height: 34)
                        .background(Color.pvDanger.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("Stop dictation")
            } else if viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PVIconButton("mic.fill", style: .surface, size: 16) {
                    viewModel.toggleRecording()
                }
                .accessibilityLabel("Dictate message")
            } else {
                PVIconButton("arrow.up", style: .filled, size: 16) {
                    // Sending is an explicit "follow the reply" intent.
                    isPinnedToBottom = true
                    scrollToBottomTrigger &+= 1
                    viewModel.send()
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.pvBackground
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.pvHairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// The globe keeps its tap-to-toggle behavior; the corner badge makes the
    /// state unmistakable (green ON / red OFF).
    private var searchToggleButton: some View {
        Button {
            viewModel.setSearchEnabled(!viewModel.searchEnabled)
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(viewModel.searchEnabled ? Color.pvAccent : Color.pvTextSecondary)
                .frame(width: 34, height: 34)
                .overlay(alignment: .topTrailing) {
                    PVStatusBadge(viewModel.searchEnabled ? .on : .off)
                        .offset(x: 7, y: -2)
                }
        }
        .accessibilityLabel(viewModel.searchEnabled ? "Web search on" : "Web search off")
        .accessibilityHint("Toggles whether the assistant may search the web")
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: .preview, environment: AppEnvironment.mock())
    }
}
