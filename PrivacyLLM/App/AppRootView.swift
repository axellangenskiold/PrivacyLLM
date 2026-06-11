import SwiftUI

/// App shell. Onboarding routing (no model → onboarding) lands in the
/// onboarding module; until then the conversation list is the root.
struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ConversationListView(environment: environment)
    }
}

#Preview {
    AppRootView()
        .environment(AppEnvironment.mock())
}
