import Foundation

nonisolated enum ModelRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case fast
    case thinking

    var id: String { rawValue }
}

nonisolated struct ModelCapabilities: Hashable, Codable, Sendable {
    /// The model emits structured reasoning (e.g. Qwen3 `<think>` blocks) that can be toggled.
    var nativeThinking: Bool
    var toolCalling: Bool

    init(nativeThinking: Bool = false, toolCalling: Bool = false) {
        self.nativeThinking = nativeThinking
        self.toolCalling = toolCalling
    }
}

nonisolated struct ModelSpec: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var displayName: String
    /// Model family, used to pick prompt scaffolds and parsing rules (e.g. "qwen3", "llama3").
    var family: String
    /// Hugging Face repo the weights are downloaded from (e.g. "mlx-community/...").
    var hfRepo: String
    var roles: [ModelRole]
    /// Approximate total download size, shown before downloading.
    var sizeBytes: Int64
    var parameterCount: String
    var quantization: String
    var minRAMGB: Int
    var contextLength: Int
    var licenseName: String
    var licenseURLString: String
    var capabilities: ModelCapabilities
    /// ISO `yyyy-MM-dd` the weights were released, used for sorting. Optional so
    /// older catalog files (and imported models) decode without it.
    var releaseDate: String?

    /// True for user-imported models: they carry no Hugging Face repo.
    var isImported: Bool { hfRepo.isEmpty }

    /// Numeric parameter count in billions, parsed from `parameterCount`
    /// (e.g. "1.7B" → 1.7, "E2B" → 2). Used to sort by model size.
    var parameterCountValue: Double {
        let digits = parameterCount.filter { $0.isNumber || $0 == "." }
        return Double(digits) ?? 0
    }

    /// `releaseDate` parsed for sorting; undated models sort oldest.
    var releaseDateValue: Date {
        guard let releaseDate else { return .distantPast }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: releaseDate) ?? .distantPast
    }
}

nonisolated enum ModelSortOrder: String, CaseIterable, Identifiable, Sendable {
    case parameterSize
    case releaseDate
    case ram

    var id: String { rawValue }

    var label: String {
        switch self {
        case .parameterSize: String(localized: "Parameter size")
        case .releaseDate: String(localized: "Newest")
        case .ram: String(localized: "RAM required")
        }
    }

    var systemImage: String {
        switch self {
        case .parameterSize: "number"
        case .releaseDate: "calendar"
        case .ram: "memorychip"
        }
    }

    /// Orders models by the chosen criterion, largest/newest/most-RAM first,
    /// with display name as a stable tie-breaker.
    func sorted(_ specs: [ModelSpec]) -> [ModelSpec] {
        specs.sorted { lhs, rhs in
            switch self {
            case .parameterSize where lhs.parameterCountValue != rhs.parameterCountValue:
                return lhs.parameterCountValue > rhs.parameterCountValue
            case .releaseDate where lhs.releaseDateValue != rhs.releaseDateValue:
                return lhs.releaseDateValue > rhs.releaseDateValue
            case .ram where lhs.minRAMGB != rhs.minRAMGB:
                return lhs.minRAMGB > rhs.minRAMGB
            default:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }
}
