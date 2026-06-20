import Foundation

/// In-memory model manager with simulated downloads, used on the simulator and in tests.
actor MockModelManager: ModelManaging {
    nonisolated let catalog: [ModelSpec]

    private var phases: [String: ModelDownloadPhase]
    private var imported: [ModelSpec] = []
    private var active: [ModelRole: String] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var observers: [UUID: AsyncStream<[ModelState]>.Continuation] = [:]
    private let downloadTickDelay: Duration

    init(
        catalog: [ModelSpec] = ModelSpec.previewCatalog,
        downloadedModelIDs: Set<String> = [],
        downloadTickDelay: Duration = .milliseconds(120)
    ) {
        self.catalog = catalog
        self.downloadTickDelay = downloadTickDelay
        self.phases = Dictionary(uniqueKeysWithValues: catalog.map {
            ($0.id, downloadedModelIDs.contains($0.id) ? ModelDownloadPhase.downloaded : .notDownloaded)
        })
        for spec in catalog where downloadedModelIDs.contains(spec.id) {
            for role in spec.roles where active[role] == nil {
                active[role] = spec.id
            }
        }
    }

    func states() -> [ModelState] {
        (catalog + imported).map { spec in
            ModelState(
                spec: spec,
                phase: phases[spec.id] ?? .notDownloaded,
                diskBytes: phases[spec.id] == .downloaded ? spec.sizeBytes : nil
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

    func startDownload(_ modelID: String) {
        guard phases[modelID] == .notDownloaded || isFailed(modelID) else { return }
        runDownload(modelID, from: 0)
    }

    func pauseDownload(_ modelID: String) {
        guard case .downloading(let progress) = phases[modelID] else { return }
        downloadTasks[modelID]?.cancel()
        downloadTasks[modelID] = nil
        phases[modelID] = .paused(progress: progress)
        notify()
    }

    func resumeDownload(_ modelID: String) {
        guard case .paused(let progress) = phases[modelID] else { return }
        runDownload(modelID, from: progress)
    }

    func cancelDownload(_ modelID: String) {
        downloadTasks[modelID]?.cancel()
        downloadTasks[modelID] = nil
        phases[modelID] = .notDownloaded
        notify()
    }

    func deleteModel(_ modelID: String) {
        phases[modelID] = .notDownloaded
        for (role, id) in active where id == modelID {
            active[role] = nil
        }
        notify()
    }

    func importModel(displayName: String, from folder: URL) async throws -> ModelSpec {
        let name = displayName.isEmpty ? folder.lastPathComponent : displayName
        let spec = ModelSpec(
            id: "imported-\(UUID().uuidString.prefix(8).lowercased())",
            displayName: name,
            family: "imported",
            hfRepo: "",
            roles: [.fast, .thinking],
            sizeBytes: 1_000_000_000,
            parameterCount: "Custom",
            quantization: "—",
            minRAMGB: 4,
            contextLength: 8192,
            licenseName: "Imported",
            licenseURLString: "",
            capabilities: ModelCapabilities(),
            releaseDate: nil
        )
        imported.append(spec)
        phases[spec.id] = .downloaded
        notify()
        return spec
    }

    func localDirectory(for modelID: String) -> URL? {
        guard phases[modelID] == .downloaded else { return nil }
        return FileManager.default.temporaryDirectory.appendingPathComponent("MockModels/\(modelID)")
    }

    func activeModelID(for role: ModelRole) -> String? {
        active[role]
    }

    func setActiveModel(_ modelID: String, for role: ModelRole) {
        active[role] = modelID
        notify()
    }

    nonisolated func exceedsDeviceRAM(_ spec: ModelSpec) -> Bool {
        let deviceRAMGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return Double(spec.minRAMGB) > deviceRAMGB
    }

    private func isFailed(_ modelID: String) -> Bool {
        if case .failed = phases[modelID] { return true }
        return false
    }

    private func runDownload(_ modelID: String, from startProgress: Double) {
        phases[modelID] = .downloading(progress: startProgress)
        notify()
        let task = Task {
            var progress = startProgress
            while progress < 1, !Task.isCancelled {
                try? await Task.sleep(for: downloadTickDelay)
                if Task.isCancelled { return }
                progress = min(1, progress + 0.1)
                setPhaseIfDownloading(modelID, .downloading(progress: progress))
            }
            guard !Task.isCancelled else { return }
            setPhaseIfDownloading(modelID, .verifying)
            try? await Task.sleep(for: downloadTickDelay)
            finishDownload(modelID)
        }
        downloadTasks[modelID] = task
    }

    private func setPhaseIfDownloading(_ modelID: String, _ phase: ModelDownloadPhase) {
        switch phases[modelID] {
        case .downloading, .verifying:
            phases[modelID] = phase
            notify()
        default:
            break
        }
    }

    private func finishDownload(_ modelID: String) {
        phases[modelID] = .downloaded
        downloadTasks[modelID] = nil
        if let spec = catalog.first(where: { $0.id == modelID }) {
            for role in spec.roles where active[role] == nil {
                active[role] = modelID
            }
        }
        notify()
    }
}
