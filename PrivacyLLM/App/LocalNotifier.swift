import UIKit
import UserNotifications

/// Local notification when a reply finishes while the user is elsewhere
/// (FR-46). Local only — nothing is registered with APNs, so no token, no
/// server, and no network.
///
/// The hard ceiling is iOS, not this code: a backgrounded app cannot submit GPU
/// work, so MLX generation does not really continue once the app is suspended.
/// What the grace window buys is finishing a reply that was nearly done. When
/// it isn't enough, the partial reply is kept and the notification says the
/// turn needs another tap.
/// ponytail: no deep link — tapping opens the app and the chat is where they
/// left it. Add UNUserNotificationCenterDelegate routing if chats multiply.
nonisolated enum LocalNotifier {
    /// Asked for in context: the first time a reply is still running as the user
    /// leaves, never at launch.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    static func notify(title: String, body: String) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // nil trigger fires immediately, which is the point.
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    @MainActor
    static var appIsForeground: Bool {
        UIApplication.shared.applicationState == .active
    }
}
