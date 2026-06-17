import Foundation

/// Build-time feature toggles, read once from `FeatureFlags.json` in the app
/// bundle. There is no server by design, so flipping a feature means editing
/// `FeatureFlags.json` and rebuilding.
///
/// For a single run (UI tests, manual QA) a flag can be overridden with a
/// launch argument — `--feature-<key>` forces it on, `--no-feature-<key>`
/// forces it off — matching the app's existing `--mock-services` style.
///
/// Missing keys fall back to each flag's `defaultValue`, so deleting a key from
/// the JSON safely disables whatever it gated.
nonisolated struct FeatureFlags: Sendable {
    /// Flags resolved for this build: `FeatureFlags.json`, then launch-argument
    /// overrides layered on top.
    static let current = FeatureFlags()

    private let values: [String: Bool]

    init(values: [String: Bool]) {
        self.values = values
    }

    init(
        bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        var resolved = Self.loadJSON(from: bundle)
        for argument in arguments {
            if argument.hasPrefix(Self.disablePrefix) {
                resolved[String(argument.dropFirst(Self.disablePrefix.count))] = false
            } else if argument.hasPrefix(Self.enablePrefix) {
                resolved[String(argument.dropFirst(Self.enablePrefix.count))] = true
            }
        }
        self.values = resolved
    }

    func isEnabled(_ flag: Flag) -> Bool {
        values[flag.rawValue] ?? flag.defaultValue
    }

    /// Every known feature flag. Add a case here and a matching key in
    /// `FeatureFlags.json` to introduce a new toggle.
    enum Flag: String {
        /// The voluntary donations / tip-jar page (main menu → Donate). Ships
        /// off for the first App Store release so the app has no in-app
        /// purchases — and therefore needs no Paid Applications agreement or
        /// tax forms. Flip to `true` in `FeatureFlags.json` once the tip
        /// consumables are approved.
        case donations

        /// Value used when the key is absent from `FeatureFlags.json`.
        var defaultValue: Bool {
            switch self {
            case .donations:
                return false
            }
        }
    }

    private static let enablePrefix = "--feature-"
    private static let disablePrefix = "--no-feature-"

    private static func loadJSON(from bundle: Bundle) -> [String: Bool] {
        guard let url = bundle.url(forResource: "FeatureFlags", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data)
        else { return [:] }
        return decoded
    }
}
