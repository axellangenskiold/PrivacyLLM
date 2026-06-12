import PrivacyUI
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
        .pvScreen()
        .task { modelsViewModel.start() }
        .onDisappear { modelsViewModel.stopObserving() }
    }

    /// The vault hero: a glowing icon tile shared by all three pages.
    private func heroTile(_ systemImage: String, size: CGFloat = 34) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Color.pvAccent)
            .frame(width: 84, height: 84)
            .background(Color.pvAccentWash, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .pvGlow()
    }

    // MARK: Page 1 — privacy promise

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()
            heroTile("lock.shield.fill")
            Text("Private by design")
                .font(PVFont.display)
                .foregroundStyle(Color.pvTextPrimary)
            VStack(alignment: .leading, spacing: 16) {
                promiseRow(icon: "iphone", title: "Runs on this iPhone", detail: "The AI model lives and thinks on your device. Your chats are never sent to a server.")
                promiseRow(icon: "lock.fill", title: "Encrypted on device", detail: "Conversations and documents are stored encrypted, readable only here.")
                promiseRow(icon: "eye.slash.fill", title: "Nothing leaves silently", detail: "Only two things ever use the network: downloading a model, and web search — which is off until you turn it on, and always visible when it runs.")
            }
            .padding(PVSpacing.l)
            .pvCard()
            .padding(.horizontal, 28)
            Spacer()
            Button {
                withAnimation { page = 1 }
            } label: {
                Text("Continue")
            }
            .buttonStyle(.pvPrimary)
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }

    private func promiseRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.pvAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PVFont.headline)
                    .foregroundStyle(Color.pvTextPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.pvTextSecondary)
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
            heroTile("square.and.arrow.down", size: 30)
            Text("Pick your model")
                .font(PVFont.display)
                .foregroundStyle(Color.pvTextPrimary)
            Text("Models download once, directly from Hugging Face, then work fully offline. Wi-Fi is recommended.")
                .font(.subheadline)
                .foregroundStyle(Color.pvTextSecondary)
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
                    .pvListRow()
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            Button {
                withAnimation { page = 2 }
            } label: {
                Text(hasDownloadedModel ? "Continue" : "Waiting for a model…")
            }
            .buttonStyle(.pvPrimary)
            .disabled(!hasDownloadedModel)
            .opacity(hasDownloadedModel ? 1 : 0.5)
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }

    // MARK: Page 3 — voice priming

    private var voicePage: some View {
        VStack(spacing: 24) {
            Spacer()
            heroTile("mic.fill")
            Text("Speak, privately")
                .font(PVFont.display)
                .foregroundStyle(Color.pvTextPrimary)
            Text("Tap the mic to dictate messages. Speech is transcribed by iOS on this device — audio never leaves your iPhone. You'll be asked for microphone permission the first time you use it.")
                .font(.subheadline)
                .foregroundStyle(Color.pvTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                onComplete()
            } label: {
                Text("Start chatting")
            }
            .buttonStyle(.pvPrimary)
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
                    .font(PVFont.headline)
                    .foregroundStyle(Color.pvTextPrimary)
                if isRecommended {
                    Text("RECOMMENDED")
                        .font(PVFont.metaSmall.weight(.heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.pvAccentWash, in: Capsule())
                        .foregroundStyle(Color.pvAccent)
                }
                Spacer()
                control
            }
            Text("\(state.spec.parameterCount) · \(ByteCountFormatter.string(fromByteCount: state.spec.sizeBytes, countStyle: .file)) · \(state.spec.licenseName)")
                .font(PVFont.metaSmall)
                .foregroundStyle(Color.pvTextSecondary)
            if case .downloading(let progress) = state.phase {
                ProgressView(value: progress)
            } else if case .paused(let progress) = state.phase {
                ProgressView(value: progress).tint(.secondary)
            } else if case .failed(let reason) = state.phase {
                Text(reason).font(PVFont.metaSmall).foregroundStyle(Color.pvWarning)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var control: some View {
        switch state.phase {
        case .notDownloaded:
            Button("Get", action: onDownload)
                .buttonStyle(.pvCompact)
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
                .foregroundStyle(Color.pvAccent)
        case .failed:
            Button("Retry", action: onDownload)
                .buttonStyle(.pvCompact)
        }
    }
}

#Preview {
    OnboardingView(environment: AppEnvironment.mock(), onComplete: {})
}
