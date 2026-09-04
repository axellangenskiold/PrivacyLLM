import PrivacyUI
import SwiftUI

/// App shell: routes first launches into onboarding, then the conversation
/// list. Stays interactive immediately — nothing heavy loads at launch (NFR-4).
struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedSystemEvents = false
    @State private var needsOnboarding: Bool?
    @State private var isLocked = false

    var body: some View {
        Group {
            if isLocked {
                lockScreen
            } else {
                switch needsOnboarding {
                case .none:
                    PVScreenBackground()
                case .some(true):
                    OnboardingView(environment: environment) {
                        completeOnboarding()
                    }
                case .some(false):
                    ConversationListView(environment: environment)
                }
            }
        }
        .tint(Color.pvAccent)
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
                if (try? await environment.settingsStore.appLockEnabled()) == true {
                    isLocked = true
                    await unlock()
                }
            }
            if !startedSystemEvents {
                startedSystemEvents = true
                environment.systemEvents.start()
                MetricsCollector.shared.start()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            environment.systemEvents.scenePhaseChanged(toBackground: phase == .background)
            // Re-lock on the way out, so the app switcher snapshot is the lock
            // screen rather than someone's chats.
            if phase == .background {
                Task {
                    if (try? await environment.settingsStore.appLockEnabled()) == true {
                        isLocked = true
                    }
                }
            }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: PVSpacing.l) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.pvAccent)
            Button("Unlock") { Task { await unlock() } }
                .buttonStyle(.pvPrimary)
                .padding(.horizontal, 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pvScreen()
    }

    private func unlock() async {
        if await AppLock.authenticate() {
            isLocked = false
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
