import SwiftUI

/// App shell: routes first launches into onboarding, then the conversation
/// list. Stays interactive immediately — nothing heavy loads at launch (NFR-4).
struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var systemEvents: SystemEventCoordinator?
    @State private var needsOnboarding: Bool?

    var body: some View {
        Group {
            switch needsOnboarding {
            case .none:
                Color.clear
            case .some(true):
                OnboardingView(environment: environment) {
                    completeOnboarding()
                }
            case .some(false):
                ConversationListView(environment: environment)
            }
        }
        .task {
            if needsOnboarding == nil {
                if ProcessInfo.processInfo.arguments.contains("--skip-onboarding") {
                    needsOnboarding = false
                } else {
                    let completed = (try? await environment.settingsStore.value(
                        for: .hasCompletedOnboarding,
                        default: false
                    )) ?? false
                    needsOnboarding = !completed
                }
                environment.appearance = (try? await environment.settingsStore.value(
                    for: .appearance,
                    default: AppearanceSetting.system
                )) ?? .system
            }
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

    private func completeOnboarding() {
        needsOnboarding = false
        let settings = environment.settingsStore
        Task { try? await settings.set(true, for: .hasCompletedOnboarding) }
    }
}

#Preview {
    AppRootView()
        .environment(AppEnvironment.mock())
}
