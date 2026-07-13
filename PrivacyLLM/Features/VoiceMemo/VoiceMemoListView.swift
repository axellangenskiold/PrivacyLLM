import PrivacyUI
import SwiftUI

/// The voice-memo hub: a library of locally generated audio with inline
/// playback that resumes where it left off. Reached from the main screen.
struct VoiceMemoListView: View {
    let environment: AppEnvironment
    @State private var viewModel: VoiceMemoViewModel
    @State private var showComposer = false
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = State(initialValue: VoiceMemoViewModel(environment: environment))
    }

    var body: some View {
        content
            .navigationTitle("Voice Memos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showComposer = true
                    } label: {
                        Label("New Voice Memo", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showComposer) {
                NewVoiceMemoView(environment: environment, onComplete: { viewModel.load() })
            }
            .task { viewModel.load() }
            .onDisappear { viewModel.persistPosition() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { viewModel.persistPosition() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.memos.isEmpty {
            VStack(spacing: 16) {
                PVEmptyState(
                    icon: "waveform",
                    title: "No voice memos",
                    message: "Turn any text — or a whole conversation — into audio you can listen to, all on this device."
                )
                Button("New Voice Memo") { showComposer = true }
                    .buttonStyle(.pvPrimary)
                    .padding(.horizontal, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pvScreen()
        } else {
            List {
                ForEach(viewModel.memos) { memo in
                    row(memo)
                        .pvListRow()
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.delete(memo)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .scrollContentBackground(.hidden)
            .pvScreen()
        }
    }

    private func row(_ memo: VoiceMemo) -> some View {
        let isCurrent = viewModel.nowPlayingID == memo.id
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    viewModel.toggle(memo)
                } label: {
                    Image(systemName: isCurrent && viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.pvAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCurrent && viewModel.isPlaying ? "Pause" : "Play")
                VStack(alignment: .leading, spacing: 3) {
                    Text(memo.title)
                        .font(PVFont.headline)
                        .foregroundStyle(Color.pvTextPrimary)
                        .lineLimit(1)
                    Text("\(memo.voiceQuality.label) · \(VoiceMemoViewModel.timeLabel(memo.durationSeconds))")
                        .font(PVFont.metaSmall)
                        .foregroundStyle(Color.pvTextSecondary)
                }
                Spacer()
                if memo.positionSeconds > 1, !isCurrent {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(Color.pvTextSecondary)
                        .accessibilityLabel("Resumes partway")
                }
            }
            if isCurrent {
                playbackControls(memo)
            }
        }
        .padding(.vertical, 4)
    }

    private func playbackControls(_ memo: VoiceMemo) -> some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(memo.durationSeconds, 0.1)
            )
            .accessibilityLabel("Playback position")
            HStack {
                Text(VoiceMemoViewModel.timeLabel(viewModel.currentTime))
                Spacer()
                Text(VoiceMemoViewModel.timeLabel(memo.durationSeconds))
            }
            .font(PVFont.metaSmall)
            .foregroundStyle(Color.pvTextSecondary)
            .monospacedDigit()
        }
    }
}

#Preview {
    NavigationStack {
        VoiceMemoListView(environment: .mock())
    }
}
