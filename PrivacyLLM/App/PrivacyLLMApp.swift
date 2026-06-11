import SwiftUI

@main
struct PrivacyLLMApp: App {
    @State private var appEnvironment = AppEnvironment.bootstrap()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appEnvironment)
        }
    }
}
