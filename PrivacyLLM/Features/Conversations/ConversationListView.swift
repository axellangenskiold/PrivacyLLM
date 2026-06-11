import SwiftUI

nonisolated enum AppRoute: Hashable {
    case chat(Conversation)
    case models
    case documents
}

struct ConversationListView: View {
    private let environment: AppEnvironment
    @State private var viewModel: ConversationListViewModel
    @State private var path: [AppRoute] = []
    @State private var renameTarget: Conversation?
    @State private var renameText = ""

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = State(initialValue: ConversationListViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Local LLM")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            path.append(.models)
                        } label: {
                            Label("Models", systemImage: "cpu")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            path.append(.documents)
                        } label: {
                            Label("Documents", systemImage: "doc.text")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            createAndOpen()
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .chat(let conversation):
                        ChatView(conversation: conversation, environment: environment)
                    case .models:
                        ModelManagerView(environment: environment)
                    case .documents:
                        DocumentsView(environment: environment)
                    }
                }
                .task { await viewModel.refresh() }
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
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.conversations.isEmpty {
            ContentUnavailableView {
                Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Start a private conversation that never leaves your device.")
            } actions: {
                Button("New Chat") { createAndOpen() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                ForEach(viewModel.conversations) { conversation in
                    NavigationLink(value: AppRoute.chat(conversation)) {
                        row(for: conversation)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(conversation) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
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
        }
    }

    private func row(for conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conversation.title)
                .lineLimit(1)
            Text(conversation.updatedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
