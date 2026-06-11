import Foundation

nonisolated enum VoiceTranscript: Hashable, Sendable {
    case partial(String)
    case final(String)
}

nonisolated enum VoiceAvailability: Hashable, Sendable {
    case available
    case permissionNotDetermined
    case denied
    case restricted
    /// On-device recognition unsupported for the current locale/hardware.
    case unsupported
}

nonisolated enum VoiceError: Error, Sendable {
    case notAuthorized
    case audioSessionFailed(String)
    case recognitionFailed(String)
}

/// On-device speech-to-text (FR-32...FR-35). Implementations must require
/// on-device recognition; audio never leaves the phone.
nonisolated protocol VoiceServicing: Sendable {
    func availability() async -> VoiceAvailability
    /// Requests mic + speech permissions, returning the resulting availability.
    func requestAuthorization() async -> VoiceAvailability
    /// Starts capture; yields partial transcripts while speaking, then `.final` on stop.
    func startTranscribing() async throws -> AsyncThrowingStream<VoiceTranscript, Error>
    /// Ends capture, triggering the final transcript on the active stream.
    func stopTranscribing() async
}

/// Scripted transcripts for simulator, previews, and tests.
actor MockVoiceService: VoiceServicing {
    private let script: [String]
    private let partialDelay: Duration
    private var continuation: AsyncThrowingStream<VoiceTranscript, Error>.Continuation?
    private var feedTask: Task<Void, Never>?

    init(
        script: [String] = ["Hello", "Hello there,", "Hello there, what can", "Hello there, what can you do?"],
        partialDelay: Duration = .milliseconds(350)
    ) {
        self.script = script
        self.partialDelay = partialDelay
    }

    func availability() -> VoiceAvailability { .available }

    func requestAuthorization() -> VoiceAvailability { .available }

    func startTranscribing() -> AsyncThrowingStream<VoiceTranscript, Error> {
        let (stream, continuation) = AsyncThrowingStream<VoiceTranscript, Error>.makeStream()
        self.continuation = continuation
        let script = script
        let delay = partialDelay
        feedTask = Task {
            for partial in script.dropLast() {
                if Task.isCancelled { return }
                try? await Task.sleep(for: delay)
                continuation.yield(.partial(partial))
            }
        }
        return stream
    }

    func stopTranscribing() {
        feedTask?.cancel()
        feedTask = nil
        continuation?.yield(.final(script.last ?? ""))
        continuation?.finish()
        continuation = nil
    }
}
