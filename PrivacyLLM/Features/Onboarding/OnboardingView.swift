import SwiftUI

/// First-run flow (UX-2): privacy promise → first model download with size and
/// Wi-Fi guidance (OD-9) → mic priming. The system mic permission is only
/// requested later, at first actual mic use (FR-35).
struct OnboardingView: View {
    private let environment: AppEnvironment
    private let onComplete: () -> Void
    @State private var modelsViewModel: ModelManagerViewModel
    @State private var page = 0

    init(environment: AppEnvironment, onComplete: @escaping () -> Void) {
        self.environment = environment
        self.onComplete = onComplete
        _modelsViewModel = State(initialValue: ModelManagerViewModel(environment: environment))
    }

    var body: some View {
        TabView(selection: $page) {
            privacyPage.tag(0)
            modelPage.tag(1)
            voicePage.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .task { modelsViewModel.start() }
        .onDisappear { modelsViewModel.stopObserving() }
    }

    // MARK: Page 1 — privacy promise

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Private by design")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 16) {
                promiseRow(icon: "iphone", title: "Runs on this iPhone", detail: "The AI model lives and thinks on your device. Your chats are never sent to a server.")
                promiseRow(icon: "lock.fill", title: "Encrypted on device", detail: "Conversations and documents are stored encrypted, readable only here.")
                promiseRow(icon: "eye.slash.fill", title: "Nothing leaves silently", detail: "Only two things ever use the network: downloading a model, and web search — which is off until you turn it on, and always visible when it runs.")
            }
            .padding(.horizontal, 28)
            Spacer()
            Button {
                withAnimation { page = 1 }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }

    private func promiseRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Page 2 — first model download

    private var hasDownloadedModel: Bool {
        modelsViewModel.states.contains { $0.phase == .downloaded }
    }

    private var modelPage: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Pick your model")
                .font(.largeTitle.bold())
            Text("Models download once, directly from Hugging Face, then work fully offline. Wi-Fi is recommended.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            List {
                ForEach(modelsViewModel.states.filter { $0.spec.roles.contains(.fast) }) { state in
                    OnboardingModelRow(
                        state: state,
                        isRecommended: state.spec.id == "qwen3-1.7b-4bit",
                        onDownload: { modelsViewModel.download(state.id) },
                        onPause: { modelsViewModel.pause(state.id) },
                        onResume: { modelsViewModel.resume(state.id) }
                    )
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            Button {
                withAnimation { page = 2 }
            } label: {
                Text(hasDownloadedModel ? "Continue" : "Waiting for a model…")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasDownloadedModel)
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }

    // MARK: Page 3 — voice priming

    private var voicePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Speak, privately")
                .font(.largeTitle.bold())
            Text("Tap the mic to dictate messages. Speech is transcribed by iOS on this device — audio never leaves your iPhone. You'll be asked for microphone permission the first time you use it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                onComplete()
            } label: {
                Text("Start chatting")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }
}

private struct OnboardingModelRow: View {
    let state: ModelState
    let isRecommended: Bool
    let onDownload: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.spec.displayName)
                    .font(.headline)
                if isRecommended {
                    Text("RECOMMENDED")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
                Spacer()
                control
            }
            Text("\(state.spec.parameterCount) · \(ByteCountFormatter.string(fromByteCount: state.spec.sizeBytes, countStyle: .file)) · \(state.spec.licenseName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if case .downloading(let progress) = state.phase {
                ProgressView(value: progress)
            } else if case .paused(let progress) = state.phase {
                ProgressView(value: progress).tint(.secondary)
            } else if case .failed(let reason) = state.phase {
                Text(reason).font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var control: some View {
        switch state.phase {
        case .notDownloaded:
            Button("Get", action: onDownload)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        case .downloading:
            Button(action: onPause) {
                Image(systemName: "pause.circle.fill").font(.title3)
            }
        case .paused:
            Button(action: onResume) {
                Image(systemName: "arrow.down.circle.fill").font(.title3)
            }
        case .verifying:
            ProgressView()
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        case .failed:
            Button("Retry", action: onDownload)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
}

#Preview {
    OnboardingView(environment: AppEnvironment.mock(), onComplete: {})
}
