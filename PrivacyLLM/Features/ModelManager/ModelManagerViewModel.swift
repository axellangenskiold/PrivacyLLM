import Foundation
import Observation

@Observable
final class ModelManagerViewModel {
    private(set) var states: [ModelState] = []
    private(set) var activeFastID: String?
    private(set) var activeThinkingID: String?

    private let manager: any ModelManaging
    private var observationTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        manager = environment.modelManager
    }

    var totalDiskBytes: Int64 {
        states.reduce(0) { $0 + ($1.diskBytes ?? 0) }
    }

    func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self, manager] in
            for await snapshot in await manager.stateUpdates() {
                guard let self else { break }
                self.states = snapshot
                await self.refreshActiveSelections()
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    func isActive(_ state: ModelState, as role: ModelRole) -> Bool {
        switch role {
        case .fast: state.id == activeFastID
        case .thinking: state.id == activeThinkingID
        }
    }

    func exceedsDeviceRAM(_ spec: ModelSpec) -> Bool {
        manager.exceedsDeviceRAM(spec)
    }

    func download(_ id: String) {
        Task { await manager.startDownload(id) }
    }

    func pause(_ id: String) {
        Task { await manager.pauseDownload(id) }
    }

    func resume(_ id: String) {
        Task { await manager.resumeDownload(id) }
    }

    func cancel(_ id: String) {
        Task { await manager.cancelDownload(id) }
    }

    func delete(_ id: String) {
        Task {
            try? await manager.deleteModel(id)
            await refreshActiveSelections()
        }
    }

    func setActive(_ id: String, role: ModelRole) {
        Task {
            await manager.setActiveModel(id, for: role)
            await refreshActiveSelections()
        }
    }

    private func refreshActiveSelections() async {
        activeFastID = await manager.activeModelID(for: .fast)
        activeThinkingID = await manager.activeModelID(for: .thinking)
    }
}
