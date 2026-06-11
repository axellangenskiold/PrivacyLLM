import SwiftUI

/// Temporary shell. The chat experience replaces this in the Chat MVP module;
/// onboarding routing arrives with the onboarding module.
struct AppRootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Local LLM")
                .font(.largeTitle.bold())
            Text("A private assistant that never leaves your device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    AppRootView()
        .environment(AppEnvironment.mock())
}
