import UIKit

/// Reacts to OS events that affect the loaded model: memory pressure frees
/// caches or unloads (NFR-6/7/8), and backgrounding cancels generation
/// (NFR-18) then unloads before suspension; the model reloads on demand.
final class SystemEventCoordinator {
    private let inference: any InferenceServicing
    private var pressureSource: DispatchSourceMemoryPressure?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init(inference: any InferenceServicing) {
        self.inference = inference
    }

    func start() {
        guard pressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let source = self.pressureSource else { return }
            self.handleMemoryPressure(critical: source.data.contains(.critical))
        }
        source.activate()
        pressureSource = source
    }

    func scenePhaseChanged(toBackground: Bool) {
        if toBackground {
            enteredBackground()
        } else {
            enteredForeground()
        }
    }

    private func handleMemoryPressure(critical: Bool) {
        let inference = inference
        Task {
            if critical {
                await inference.cancelGeneration()
                await inference.unloadModel()
            } else {
                await inference.reduceMemoryFootprint()
            }
        }
    }

    private func enteredBackground() {
        let inference = inference
        Task { await inference.cancelGeneration() }
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "unload-model") { [weak self] in
            self?.finishBackgroundUnload()
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            self?.finishBackgroundUnload()
        }
    }

    private func enteredForeground() {
        endBackgroundTask()
    }

    private func finishBackgroundUnload() {
        // Skipped when the app already returned to the foreground.
        guard backgroundTaskID != .invalid else { return }
        let inference = inference
        Task {
            await inference.unloadModel()
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
