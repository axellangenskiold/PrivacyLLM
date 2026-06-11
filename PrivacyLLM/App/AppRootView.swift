import SwiftUI

/// App shell. Onboarding routing (no model → onboarding) lands in the
/// onboarding module; until then the conversation list is the root.
struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var systemEvents: SystemEventCoordinator?

    var body: some View {
        ConversationListView(environment: environment)
            .task {
                if systemEvents == nil {
                    let coordinator = SystemEventCoordinator(inference: environment.inference)
                    coordinator.start()
                    systemEvents = coordinator
                }
            }
            .onChange(of: scenePhase) { _, phase in
                systemEvents?.scenePhaseChanged(toBackground: phase == .background)
            }
    }
}

#Preview {
    AppRootView()
        .environment(AppEnvironment.mock())
}
