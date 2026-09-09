import SwiftUI

/// iOS relaunches the app when a background download finishes; this hands the
/// session its completion handler so the OS knows when we're done reacting.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundTransfers.shared.backgroundEventsCompletion = completionHandler
    }
}

@main
struct PrivacyLLMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appEnvironment = AppEnvironment.bootstrap()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appEnvironment)
                .preferredColorScheme(appEnvironment.appearance.colorScheme)
        }
    }
}
