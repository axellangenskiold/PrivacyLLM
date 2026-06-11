import Combine
import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var thermalState = ProcessInfo.processInfo.thermalState
    @State private var editTarget: Message?
    @State private var editText = ""
    @State private var showSystemPrompt = false
    @State private var systemPromptText = ""
    @FocusState private var inputFocused: Bool

    init(conversation: Conversation, environment: AppEnvironment) {
        _viewModel = State(initialValue: ChatViewModel(conversation: conversation, environment: environment))
    }

    var body: some View {
        VStack(spacing: 0) {
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

#Preview {
    NavigationStack {
        ChatView(conversation: .preview, environment: AppEnvironment.mock())
    }
}
