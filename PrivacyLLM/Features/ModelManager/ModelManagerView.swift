import PrivacyUI
import SwiftUI

struct ModelManagerView: View {
    @State private var viewModel: ModelManagerViewModel
    @State private var ramWarningTarget: ModelSpec?

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: ModelManagerViewModel(environment: environment))
    }

    var body: some View {
        List {
            Section {
                ForEach(viewModel.states) { state in
                    ModelRow(
                        state: state,
                        isActiveFast: viewModel.isActive(state, as: .fast),
                        isActiveThinking: viewModel.isActive(state, as: .thinking),
                        exceedsRAM: viewModel.exceedsDeviceRAM(state.spec),
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
                Label("\(state.spec.minRAMGB) GB RAM", systemImage: exceedsRAM ? "exclamationmark.triangle.fill" : "memorychip")
                    .font(PVFont.metaSmall)
                    .foregroundStyle(exceedsRAM ? Color.pvWarning : Color.pvTextSecondary)
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
