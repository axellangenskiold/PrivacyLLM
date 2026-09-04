import LocalAuthentication

/// Face ID / Touch ID gate for the whole app (OD-8). Opt-in; the passcode is
/// always allowed as the fallback so losing biometrics never locks someone out
/// of their own chats.
nonisolated enum AppLock {
    /// True when this device can actually ask for anything — biometrics or passcode.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static func authenticate(reason: String = String(localized: "Unlock your chats")) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No biometrics and no passcode: there is nothing to check against,
            // so refusing entry would just brick the app.
            return true
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
