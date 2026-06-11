import UIKit

/// Haptics for key chat events (UX-9). UIFeedbackGenerator already respects
/// the system haptics setting.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
