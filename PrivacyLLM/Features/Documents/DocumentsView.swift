import SwiftUI
import UniformTypeIdentifiers

/// Global document library (FR-28). Conversation-scoped attachments happen
/// through the paperclip in the chat view (OD-6).
struct DocumentsView: View {
    @State private var viewModel: DocumentsViewModel
    @State private var showImporter = false

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: DocumentsViewModel(environment: environment))
    }

    var body: some View {
        Group {
            if viewModel.documents.isEmpty, !viewModel.isImporting {
                ContentUnavailableView {
                    Label("No documents", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Import a PDF and ask questions about it. Documents are indexed and stored entirely on this device.")
                } actions: {
                    Button("Import PDF") { showImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    if viewModel.isImporting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Indexing… this stays on your device.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    ForEach(viewModel.documents) { document in
                        row(for: document)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await viewModel.delete(document) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Label("Import PDF", systemImage: "plus")
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.pdf]) { result in
            if case .success(let url) = result {
                Task { await viewModel.importPDF(at: url, scope: .global) }
            }
        }
        .task { await viewModel.refresh() }
    }

    private func row(for document: DocumentMeta) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)
                if case .conversation = document.scope {
                    Image(systemName: "bubble.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Attached to one chat")
                }
            }
            HStack(spacing: 8) {
                Text("\(document.pageCount) pages · \(ByteCountFormatter.string(fromByteCount: document.byteSize, countStyle: .file))")
                stateBadge(for: document.indexState)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func stateBadge(for state: DocumentIndexState) -> some View {
        switch state {
        case .ready:
            Label("Indexed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .indexing, .pending:
            Label("Indexing…", systemImage: "clock")
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    NavigationStack {
        DocumentsView(environment: AppEnvironment.mock())
    }
}
