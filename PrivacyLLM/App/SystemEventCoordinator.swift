import UIKit

/// Reacts to OS events that affect the loaded model: memory pressure frees
/// caches or unloads (NFR-6/7/8), backgrounding cancels generation (NFR-18)
/// then unloads before suspension, and leaving the chat screen for long enough
/// unloads too (NFR-7). The model reloads on demand.
final class SystemEventCoordinator {
    /// How long the model stays resident after the user leaves the chat. Long
    /// enough to step out to Settings and back without paying a reload,
    /// short enough that a forgotten app isn't sitting on ~2 GB and a live
    /// Metal allocation.
    static let idleUnloadDelay = Duration.seconds(120)

    /// How long a backgrounded turn is allowed to keep going before the model is
    /// cancelled and unloaded. iOS grants roughly 30s; stopping short of that
    /// leaves room to unload cleanly instead of being killed mid-flight.
    static let backgroundGrace = Duration.seconds(20)

    private let inference: any InferenceServicing
    private var pressureSource: DispatchSourceMemoryPressure?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var idleUnloadTask: Task<Void, Never>?

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

    /// The user opened a chat: the model may be needed again at any moment.
    func chatOpened() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    /// The user left the chat. Unload after a grace period unless they come back.
    func chatClosed() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [inference] in
            try? await Task.sleep(for: Self.idleUnloadDelay)
            guard !Task.isCancelled else { return }
            await inference.unloadModel()
        }
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

    /// Leaving no longer kills an in-flight reply on the spot (was NFR-18): the
    /// turn gets the OS grace window to finish, and ChatViewModel notifies when
    /// it does. iOS blocks GPU work in a backgrounded app, so this only rescues
    /// replies that were nearly done — when it isn't enough the partial text is
    /// kept and the user finishes it on the next open.
    private func enteredBackground() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "finish-turn") { [weak self] in
            self?.finishBackgroundUnload()
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.backgroundGrace)
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
            await inference.cancelGeneration()
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
