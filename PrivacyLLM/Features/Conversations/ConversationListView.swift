import PrivacyUI
import SwiftUI

nonisolated enum AppRoute: Hashable {
    case chat(Conversation)
    case voiceMemos
    case models
    case documents
    case settings
    case donate
}

struct ConversationListView: View {
    private let environment: AppEnvironment
    @State private var viewModel: ConversationListViewModel
    @State private var path: [AppRoute] = []
    @State private var renameTarget: Conversation?
    @State private var renameText = ""
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var showFeedback = false
    @State private var askForFeedback = false

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = State(initialValue: ConversationListViewModel(environment: environment))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        return NavigationStack(path: $path) {
            content
                .navigationTitle("PrivacyLLM")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                path.append(.models)
                            } label: {
                                Label("Models", systemImage: "cpu")
                            }
                            Button {
                                path.append(.documents)
                            } label: {
                                Label("Documents", systemImage: "doc.text")
                            }
                            Button {
                                path.append(.settings)
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                            Button {
                                showFeedback = true
                            } label: {
                                Label("Feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                            }
                            if FeatureFlags.current.isEnabled(.donations) {
                                Button {
                                    path.append(.donate)
                                } label: {
                                    Label("Donate", systemImage: "heart")
                                }
                            }
                        } label: {
                            Label("Menu", systemImage: "line.3.horizontal")
                        }
                        .accessibilityLabel("App menu")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            path.append(.voiceMemos)
                        } label: {
                            Label("Voice Memos", systemImage: "waveform")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            createAndOpen()
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                    }
                    if !viewModel.conversations.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(isSelecting ? "Done" : "Select") { toggleSelecting() }
                        }
                    }
                    if isSelecting {
                        ToolbarItem(placement: .bottomBar) {
                            Button(role: .destructive) {
                                deleteSelected()
                            } label: {
                                Label(
                                    selection.isEmpty ? "Delete" : "Delete (\(selection.count))",
                                    systemImage: "trash"
                                )
                            }
                            .tint(.red)
                            .disabled(selection.isEmpty)
                            .accessibilityIdentifier("delete-selected-chats")
                        }
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .chat(let conversation):
                        ChatView(conversation: conversation, environment: environment)
                    case .voiceMemos:
                        VoiceMemoListView(environment: environment)
                    case .models:
                        ModelManagerView(environment: environment)
                    case .documents:
                        DocumentsView(environment: environment)
                    case .settings:
                        SettingsView(environment: environment)
                    case .donate:
                        DonateView()
                    }
                }
                .searchable(text: $viewModel.query, prompt: "Search chats")
                .task(id: viewModel.query) { await viewModel.refresh() }
                .onChange(of: path) { _, newPath in
                    // Titles change after the first message; refresh when returning.
                    if newPath.isEmpty {
                        Task { await viewModel.refresh() }
                    }
                }
                .alert("Rename Chat", isPresented: renamePresented) {
                    TextField("Name", text: $renameText)
                    Button("Save") { confirmRename() }
                    Button("Cancel", role: .cancel) {}
                }
                .alert("Anything you'd like in the app?", isPresented: $askForFeedback) {
                    Button("Tell us") { showFeedback = true }
                    Button("Not now", role: .cancel) {}
                } message: {
                    Text("It goes straight to the developer.")
                }
                .sheet(isPresented: $showFeedback) {
                    FeedbackView(environment: environment)
                }
                .task {
                    askForFeedback = await FeedbackPrompt(
                        settingsStore: environment.settingsStore
                    ).registerLaunchAndShouldAsk()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.conversations.isEmpty, !viewModel.query.isEmpty {
            PVEmptyState(
                icon: "magnifyingglass",
                title: "No matches",
                message: "Nothing in your chats mentions that."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pvScreen()
        } else if viewModel.conversations.isEmpty {
            VStack(spacing: 0) {
                PVEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "No chats yet",
                    message: "Start a private conversation that never leaves your device."
                )
                Button("New Chat") { createAndOpen() }
                    .buttonStyle(.pvPrimary)
                    .padding(.horizontal, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pvScreen()
        } else {
            List(selection: $selection) {
                ForEach(viewModel.conversations) { conversation in
                    NavigationLink(value: AppRoute.chat(conversation)) {
                        row(for: conversation)
                    }
                    .pvListRow()
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(conversation) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        // The app tint is emerald; destructive swipe actions
                        // inherit it, so say red explicitly.
                        .tint(.red)
                    }
                    .contextMenu {
                        Button {
                            renameTarget = conversation
                            renameText = conversation.title
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task { await viewModel.delete(conversation) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .pvScreen()
        }
    }

    private func row(for conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(PVFont.headline)
                .foregroundStyle(Color.pvTextPrimary)
                .lineLimit(1)
            Text(conversation.updatedAt, format: .relative(presentation: .named))
                .font(PVFont.metaSmall)
                .foregroundStyle(Color.pvTextSecondary)
        }
        .padding(.vertical, 3)
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func confirmRename() {
        guard let target = renameTarget else { return }
        renameTarget = nil
        Task { await viewModel.rename(target, to: renameText) }
    }

    private var isSelecting: Bool { editMode == .active }

    private func toggleSelecting() {
        editMode = isSelecting ? .inactive : .active
        selection.removeAll()
    }

    private func deleteSelected() {
        let ids = selection
        guard !ids.isEmpty else { return }
        editMode = .inactive
        selection.removeAll()
        Task { await viewModel.delete(ids: ids) }
    }

    private func createAndOpen() {
        Task {
            if let conversation = await viewModel.create() {
                path.append(.chat(conversation))
            }
        }
    }
}

#Preview {
    ConversationListView(environment: AppEnvironment.mock())
}
