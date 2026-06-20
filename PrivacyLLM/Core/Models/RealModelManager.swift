import Foundation

/// Production model manager: catalog from Config/ModelCatalog.json, downloads
/// via ModelDownloader, weights in ModelStore, active fast/thinking selections
/// in SettingsStore, and a local egress-log entry per download (PR-14).
actor RealModelManager: ModelManaging {
    /// Bundled models plus any the user imported (read from disk so runtime
    /// imports are visible everywhere `catalog` is consulted).
    nonisolated var catalog: [ModelSpec] {
        bundleCatalog + store.loadImportedSpecs()
    }

    private let bundleCatalog: [ModelSpec]
    private let store: ModelStore
    private let downloader: ModelDownloader
    private let settings: SettingsStore
    private let egressLog: EgressEventStore

    private var phases: [String: ModelDownloadPhase] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var observers: [UUID: AsyncStream<[ModelState]>.Continuation] = [:]
    private var lastReportedProgress: [String: Double] = [:]

    init(
        catalog: [ModelSpec] = ModelCatalogLoader.load(),
        store: ModelStore = ModelStore(),
        session: URLSession = HuggingFaceAPI.makeSession(),
        settingsStore: SettingsStore,
        egressEventStore: EgressEventStore
    ) {
        self.bundleCatalog = catalog
        self.store = store
        let api = HuggingFaceAPI(session: session)
        self.downloader = ModelDownloader(api: api, store: store)
        self.settings = settingsStore
        self.egressLog = egressEventStore
        for spec in catalog {
            phases[spec.id] = if store.isDownloaded(spec.id) {
                .downloaded
            } else if store.hasPartial(spec.id) {
                .paused(progress: Double(store.partialBytes(for: spec.id)) / Double(max(1, spec.sizeBytes)))
            } else {
                .notDownloaded
            }
        }
    }

    // MARK: State

    func states() -> [ModelState] {
        catalog.map { spec in
            ModelState(
                spec: spec,
                phase: phases[spec.id] ?? .notDownloaded,
                diskBytes: store.diskBytes(for: spec.id)
            )
        }
    }

    func stateUpdates() -> AsyncStream<[ModelState]> {
        let (stream, continuation) = AsyncStream<[ModelState]>.makeStream()
        let id = UUID()
        observers[id] = continuation
        continuation.yield(states())
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func notify() {
        let snapshot = states()
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    // MARK: Downloads

    func startDownload(_ modelID: String) {
        switch phases[modelID] {
        case .notDownloaded, .failed, .paused:
            runDownload(modelID)
        default:
            break
        }
    }

    func resumeDownload(_ modelID: String) {
        if case .paused = phases[modelID] {
            runDownload(modelID)
        }
    }

    func pauseDownload(_ modelID: String) {
        guard case .downloading(let progress) = phases[modelID] else { return }
        phases[modelID] = .paused(progress: progress)
        downloadTasks[modelID]?.cancel()
        downloadTasks[modelID] = nil
        notify()
    }

    func cancelDownload(_ modelID: String) {
        phases[modelID] = .notDownloaded
        downloadTasks[modelID]?.cancel()
        downloadTasks[modelID] = nil
        store.deletePartial(for: modelID)
        notify()
    }

    private func runDownload(_ modelID: String) {
        guard let spec = catalog.first(where: { $0.id == modelID }) else { return }
        let resumeProgress: Double = if case .paused(let p) = phases[modelID] { p } else { 0 }
        phases[modelID] = .downloading(progress: resumeProgress)
        lastReportedProgress[modelID] = resumeProgress
        notify()

        let downloader = downloader
        let egressLog = egressLog
        let task = Task {
            // Weight downloads are expected egress; log them like everything else (PR-2/14).
            try? await egressLog.append(EgressEvent(
                kind: .modelDownload,
                destinationHost: HuggingFaceAPI.host,
                detail: spec.displayName
            ))
            do {
                try await downloader.download(spec: spec) { downloaded, total in
                    let fraction = total > 0 ? Double(downloaded) / Double(total) : 0
                    Task { await self.reportProgress(modelID, fraction: fraction) }
                }
                await self.finishDownload(modelID)
            } catch is CancellationError {
                // pause/cancel already updated the phase.
            } catch {
                await self.failDownload(modelID, reason: Self.userFacingReason(for: error))
            }
        }
        downloadTasks[modelID] = task
    }

    private func reportProgress(_ modelID: String, fraction: Double) {
        guard case .downloading = phases[modelID] else { return }
        let last = lastReportedProgress[modelID] ?? 0
        guard fraction - last >= 0.002 || fraction >= 0.999 else { return }
        lastReportedProgress[modelID] = fraction
        phases[modelID] = fraction >= 0.999 ? .verifying : .downloading(progress: fraction)
        notify()
    }

    private func finishDownload(_ modelID: String) async {
        downloadTasks[modelID] = nil
        phases[modelID] = .downloaded
        if let spec = catalog.first(where: { $0.id == modelID }) {
            for role in spec.roles where await activeModelID(for: role) == nil {
                await setActiveModel(modelID, for: role)
            }
        }
        notify()
    }

    private func failDownload(_ modelID: String, reason: String) {
        downloadTasks[modelID] = nil
        phases[modelID] = .failed(reason)
        notify()
    }

    private static func userFacingReason(for error: any Error) -> String {
        if case ModelManagerError.checksumMismatch = error {
            return String(localized: "The download didn't verify. It may be corrupted — try again.")
        }
        return String(localized: "The download failed. Check your connection and try again.")
    }

    // MARK: Storage & selection

    func deleteModel(_ modelID: String) async throws {
        downloadTasks[modelID]?.cancel()
        downloadTasks[modelID] = nil
        do {
            try store.delete(modelID)
        } catch {
            throw ModelManagerError.deletionFailed(error.localizedDescription)
        }
        phases[modelID] = .notDownloaded
        for role in ModelRole.allCases where await activeModelID(for: role) == modelID {
            try? await settings.remove(Self.settingsKey(for: role))
        }
        // Drop imported models from the manifest entirely so they don't linger
        // as ghost "not downloaded" rows.
        var imported = store.loadImportedSpecs()
        if let index = imported.firstIndex(where: { $0.id == modelID }) {
            imported.remove(at: index)
            store.saveImportedSpecs(imported)
            phases[modelID] = nil
        }
        notify()
    }

    func importModel(displayName: String, from folder: URL) async throws -> ModelSpec {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? folder.lastPathComponent : trimmed
        // A folder is only a usable MLX model if it carries a config.json.
        let configURL = folder.appending(path: "config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw ModelManagerError.invalidImport(
                String(localized: "That folder has no config.json — pick a folder with MLX model files.")
            )
        }

        let id = "imported-\(UUID().uuidString.prefix(8).lowercased())"
        try store.importDirectory(from: folder, as: id)

        let sizeBytes = store.diskBytes(for: id) ?? 0
        let spec = ModelSpec(
            id: id,
            displayName: name,
            family: Self.detectFamily(configURL: configURL),
            hfRepo: "",
            roles: [.fast, .thinking],
            sizeBytes: sizeBytes,
            parameterCount: String(localized: "Custom"),
            quantization: "—",
            minRAMGB: max(4, Int((Double(sizeBytes) / 1_073_741_824).rounded(.up)) + 1),
            contextLength: 8192,
            licenseName: String(localized: "Imported"),
            licenseURLString: "",
            capabilities: ModelCapabilities(nativeThinking: false, toolCalling: false),
            releaseDate: Self.today()
        )

        var imported = store.loadImportedSpecs()
        imported.append(spec)
        store.saveImportedSpecs(imported)
        phases[id] = .downloaded
        notify()
        return spec
    }

    /// Reads `model_type` from config.json so our prompt scaffolds can match a
    /// known family (e.g. "qwen3", "llama"); falls back to a generic family.
    private static func detectFamily(configURL: URL) -> String {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["model_type"] as? String
        else { return "imported" }
        return type
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    func localDirectory(for modelID: String) -> URL? {
        store.isDownloaded(modelID) ? store.directory(for: modelID) : nil
    }

    func activeModelID(for role: ModelRole) async -> String? {
        let stored: String? = (try? await settings.value(for: Self.settingsKey(for: role), default: String?.none)) ?? nil
        guard let stored, store.isDownloaded(stored) else { return nil }
        return stored
    }

    func setActiveModel(_ modelID: String, for role: ModelRole) async {
        try? await settings.set(modelID, for: Self.settingsKey(for: role))
        notify()
    }

    nonisolated func exceedsDeviceRAM(_ spec: ModelSpec) -> Bool {
        let deviceRAMGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return Double(spec.minRAMGB) > deviceRAMGB
    }

    private static func settingsKey(for role: ModelRole) -> SettingsKey {
        role == .fast ? .activeFastModelID : .activeThinkingModelID
    }
}
