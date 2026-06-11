import Foundation

nonisolated enum ModelDownloadPhase: Hashable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case paused(progress: Double)
    case verifying
    case downloaded
    case failed(String)
}

nonisolated struct ModelState: Hashable, Sendable, Identifiable {
    var spec: ModelSpec
    var phase: ModelDownloadPhase
    var diskBytes: Int64?

    var id: String { spec.id }
}

nonisolated enum ModelManagerError: Error, Sendable {
    case unknownModel
    case checksumMismatch(file: String)
    case deletionFailed(String)
}

/// Catalog, downloads (progress + pause/resume + checksum), storage, and the
/// active fast/thinking selections (FR-11...FR-16).
nonisolated protocol ModelManaging: Sendable {
    var catalog: [ModelSpec] { get }

    /// Current snapshot of every catalog model's state.
    func states() async -> [ModelState]

    /// Emits a fresh snapshot whenever any model's state changes. Finishes when
    /// the manager is deallocated.
    func stateUpdates() async -> AsyncStream<[ModelState]>

    func startDownload(_ modelID: String) async
    func pauseDownload(_ modelID: String) async
    func resumeDownload(_ modelID: String) async
    func cancelDownload(_ modelID: String) async
    func deleteModel(_ modelID: String) async throws

    /// Directory containing the downloaded weights, nil until downloaded.
    func localDirectory(for modelID: String) async -> URL?

    func activeModelID(for role: ModelRole) async -> String?
    func setActiveModel(_ modelID: String, for role: ModelRole) async

    /// True when the device's physical RAM is below the model's requirement (FR-16).
    func exceedsDeviceRAM(_ spec: ModelSpec) -> Bool
}
