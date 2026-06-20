import PrivacyUI
import SwiftUI
import UniformTypeIdentifiers

struct ModelManagerView: View {
    @State private var viewModel: ModelManagerViewModel
    @State private var ramWarningTarget: ModelSpec?
    @State private var ramInfoTarget: ModelSpec?
    @State private var isImporting = false

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: ModelManagerViewModel(environment: environment))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        List {
            Section {
                ForEach(viewModel.sortedStates) { state in
                    ModelRow(
                        state: state,
                        isActiveFast: viewModel.isActive(state, as: .fast),
                        isActiveThinking: viewModel.isActive(state, as: .thinking),
                        exceedsRAM: viewModel.exceedsDeviceRAM(state.spec),
                        onRAMInfo: { ramInfoTarget = state.spec },
                        onDownload: { requestDownload(state.spec) },
                        onPause: { viewModel.pause(state.id) },
                        onResume: { viewModel.resume(state.id) },
                        onCancel: { viewModel.cancel(state.id) },
                        onDelete: { viewModel.delete(state.id) },
                        onSetActive: { role in viewModel.setActive(state.id, role: role) }
                    )
                }
            } header: {
                Text("Models")
            } footer: {
                Text("Weights download directly from Hugging Face over Wi-Fi if possible, and never leave this device afterwards. \(storageFooter)")
            }
            .pvListRow()
        }
        .scrollContentBackground(.hidden)
        .pvScreen()
        .navigationTitle("Models")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $viewModel.sortOrder) {
                        ForEach(ModelSortOrder.allCases) { order in
                            Label(order.label, systemImage: order.systemImage).tag(order)
                        }
                    }
                    Divider()
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import Model…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Sort and import models")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            "Couldn't import model",
            isPresented: importErrorPresented,
            presenting: viewModel.importError
        ) { _ in
            Button("OK", role: .cancel) { viewModel.clearImportError() }
        } message: { message in
            Text(message)
        }
        .task { viewModel.start() }
        .onDisappear { viewModel.stopObserving() }
        .confirmationDialog(
            "This model may exceed this device's memory",
            isPresented: ramWarningPresented,
            titleVisibility: .visible
        ) {
            Button("Download Anyway", role: .destructive) {
                if let spec = ramWarningTarget { viewModel.download(spec.id) }
                ramWarningTarget = nil
            }
            Button("Cancel", role: .cancel) { ramWarningTarget = nil }
        } message: {
            if let spec = ramWarningTarget {
                Text("\(spec.displayName) wants \(spec.minRAMGB) GB of RAM. Loading it here may be unstable.")
            }
        }
        .alert(
            "May not run on this device",
            isPresented: ramInfoPresented,
            presenting: ramInfoTarget
        ) { _ in
            Button("OK", role: .cancel) { ramInfoTarget = nil }
        } message: { spec in
            Text("\(spec.displayName) needs about \(spec.minRAMGB) GB of memory to load, but this device has \(Self.deviceRAMDescription) — and iOS only lets an app use part of that. The model would likely fail to load, or the system would stop the app mid-reply. A smaller model will run reliably here.")
        }
    }

    /// What the hardware actually reports (an "8 GB" iPhone reports ~7.5 GB
    /// usable), matching the comparison behind the warning triangle.
    private static var deviceRAMDescription: String {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }

    private var storageFooter: String {
        let used = viewModel.totalDiskBytes
        guard used > 0 else { return "" }
        return "Using \(ByteCountFormatter.string(fromByteCount: used, countStyle: .file)) of storage."
    }

    private var ramWarningPresented: Binding<Bool> {
        Binding(
            get: { ramWarningTarget != nil },
            set: { if !$0 { ramWarningTarget = nil } }
        )
    }

    private var ramInfoPresented: Binding<Bool> {
        Binding(
            get: { ramInfoTarget != nil },
            set: { if !$0 { ramInfoTarget = nil } }
        )
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.clearImportError() } }
        )
    }

    private func handleImport(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, let folder = urls.first else { return }
        // A picked folder comes security-scoped; hold access while we copy it.
        let scoped = folder.startAccessingSecurityScopedResource()
        Task {
            await viewModel.importModel(displayName: folder.lastPathComponent, from: folder)
            if scoped { folder.stopAccessingSecurityScopedResource() }
        }
    }

    private func requestDownload(_ spec: ModelSpec) {
        if viewModel.exceedsDeviceRAM(spec) {
            ramWarningTarget = spec
        } else {
            viewModel.download(spec.id)
        }
    }
}

private struct ModelRow: View {
    let state: ModelState
    let isActiveFast: Bool
    let isActiveThinking: Bool
    let exceedsRAM: Bool
    let onRAMInfo: () -> Void
    let onDownload: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onSetActive: (ModelRole) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(state.spec.displayName)
                    .font(PVFont.headline)
                    .foregroundStyle(Color.pvTextPrimary)
                if isActiveFast { roleBadge("FAST") }
                if isActiveThinking { roleBadge("THINKING") }
                Spacer()
                trailingControl
            }
            Text("\(state.spec.parameterCount) · \(state.spec.quantization) · \(ByteCountFormatter.string(fromByteCount: state.spec.sizeBytes, countStyle: .file))")
                .font(PVFont.metaSmall)
                .foregroundStyle(Color.pvTextSecondary)
            HStack(spacing: 8) {
                if exceedsRAM {
                    // The triangle is a question waiting to be asked — answer it.
                    Button(action: onRAMInfo) {
                        Label("\(state.spec.minRAMGB) GB RAM", systemImage: "exclamationmark.triangle.fill")
                            .font(PVFont.metaSmall)
                            .foregroundStyle(Color.pvWarning)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Needs \(state.spec.minRAMGB) gigabytes of memory, more than this device has")
                    .accessibilityHint("Shows why this model may not run on this device")
                } else {
                    Label("\(state.spec.minRAMGB) GB RAM", systemImage: "memorychip")
                        .font(PVFont.metaSmall)
                        .foregroundStyle(Color.pvTextSecondary)
                }
                if let url = URL(string: state.spec.licenseURLString) {
                    Link(destination: url) {
                        Label(state.spec.licenseName, systemImage: "doc.text")
                            .font(PVFont.metaSmall)
                    }
                }
            }
            phaseDetail
        }
        .padding(.vertical, 4)
    }

    private func roleBadge(_ text: String) -> some View {
        Text(text)
            .font(PVFont.metaSmall.weight(.heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.pvAccentWash, in: Capsule())
            .foregroundStyle(Color.pvAccent)
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch state.phase {
        case .notDownloaded:
            Button("Get", action: onDownload)
                .buttonStyle(.pvCompact)
        case .downloading:
            Button(action: onPause) {
                Image(systemName: "pause.circle.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Pause download")
        case .paused:
            HStack(spacing: 4) {
                Button(action: onResume) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Resume download")
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                        .font(.title2)
                }
                .accessibilityLabel("Cancel download")
            }
        case .verifying:
            ProgressView()
        case .downloaded:
            Menu {
                Button {
                    onSetActive(.fast)
                } label: {
                    Label("Use for Fast", systemImage: "hare")
                }
                Button {
                    onSetActive(.thinking)
                } label: {
                    Label("Use for Thinking", systemImage: "brain")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.pvAccent)
            }
            .accessibilityLabel("Downloaded. Model options")
        case .failed:
            Button("Retry", action: onDownload)
                .buttonStyle(.pvCompact)
        }
    }

    @ViewBuilder
    private var phaseDetail: some View {
        switch state.phase {
        case .downloading(let progress):
            ProgressView(value: progress) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int(progress * 100))% downloaded")
                    .font(PVFont.metaSmall)
            }
        case .paused(let progress):
            ProgressView(value: progress) {
                EmptyView()
            } currentValueLabel: {
                Text("Paused at \(Int(progress * 100))%")
                    .font(PVFont.metaSmall)
            }
            .tint(.secondary)
        case .verifying:
            Text("Verifying integrity…")
                .font(PVFont.metaSmall)
                .foregroundStyle(Color.pvTextSecondary)
        case .failed(let reason):
            Text(reason)
                .font(PVFont.metaSmall)
                .foregroundStyle(Color.pvWarning)
        default:
            EmptyView()
        }
    }
}

#Preview {
    NavigationStack {
        ModelManagerView(environment: AppEnvironment.mock())
    }
}
