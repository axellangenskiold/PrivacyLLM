import Foundation

/// Streams canned tokens on a timer. Drives the entire app on the simulator,
/// in SwiftUI previews, and in unit/UI tests, since MLX requires a physical device.
actor MockInferenceService: InferenceServicing {
    private var loadedSpec: ModelSpec?
    private var generationTask: Task<Void, Never>?
    private let tokenDelay: Duration
    private var replyQueue: [String]
    /// Captured for tests asserting what the orchestrator actually sent.
    private(set) var lastInput: PromptInput?

    init(tokenDelay: Duration = .milliseconds(24), scriptedReply: String? = nil) {
        self.tokenDelay = tokenDelay
        replyQueue = scriptedReply.map { [$0] } ?? []
    }

    /// Each generate call pops the next reply; the last one repeats. Lets
    /// tests script multi-round agent conversations.
    init(tokenDelay: Duration = .milliseconds(24), replies: [String]) {
        self.tokenDelay = tokenDelay
        replyQueue = replies
    }

    var loadedModel: ModelSpec? { loadedSpec }

    func loadModel(spec: ModelSpec, directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        for step in 1...4 {
            try? await Task.sleep(for: .milliseconds(50))
            progress(Double(step) / 4)
        }
        loadedSpec = spec
    }

    func unloadModel() {
        loadedSpec = nil
    }

    func memoryFootprintBytes() -> Int64? {
        loadedSpec == nil ? nil : 900_000_000
    }

    func countTokens(_ text: String) -> Int? {
        nil
    }

    func reduceMemoryFootprint() {}

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    func generate(_ input: PromptInput, config: GenerationConfig) -> AsyncThrowingStream<InferenceEvent, Error> {
        lastInput = input
        let reply = nextReply() ?? Self.cannedReply(
            to: input.messages.last(where: { $0.role == .user })?.content ?? "",
            thinking: config.thinkingEnabled
        )
        let delay = tokenDelay
        let maxTokens = config.sampling.maxTokens
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent, Error>.makeStream()
        let task = Task {
            let start = ContinuousClock.now
            var firstTokenSeconds: Double?
            var emitted = 0
            for piece in Self.pieces(of: reply) {
                if Task.isCancelled || emitted >= maxTokens { break }
                try? await Task.sleep(for: delay)
                if Task.isCancelled { break }
                if firstTokenSeconds == nil {
                    firstTokenSeconds = Self.seconds(since: start)
                }
                continuation.yield(.token(piece))
                emitted += 1
            }
            let elapsed = Self.seconds(since: start)
            continuation.yield(.finished(GenerationStats(
                promptTokens: input.messages.reduce(0) { $0 + $1.content.count / 4 },
                completionTokens: emitted,
                tokensPerSecond: elapsed > 0 ? Double(emitted) / elapsed : nil,
                firstTokenSeconds: firstTokenSeconds
            )))
            continuation.finish()
        }
        generationTask = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func nextReply() -> String? {
        guard !replyQueue.isEmpty else { return nil }
        return replyQueue.count == 1 ? replyQueue[0] : replyQueue.removeFirst()
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Splits a reply into word-ish streaming pieces, keeping whitespace attached.
    private static func pieces(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == " " || character == "\n" {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func cannedReply(to userText: String, thinking: Bool) -> String {
        let prefix = thinking
            ? "<think>\nThe user said: \"\(userText)\". This is the mock engine, so I will demonstrate a reasoning block before answering.\n</think>\n"
            : ""
        return prefix + """
        You said: *\(userText)*

        I'm the **mock model** that runs on the simulator — the real on-device model replies on an iPhone. Here's a quick markdown sample:

        ## What works here
        - Streaming, token by token
        - **Bold**, *italic*, and [links](https://example.com)
        - Code blocks:

        ```swift
        let answer = 42
        print("The answer is \\(answer)")
        ```

        Everything you type stays on this device.
        """
    }
}
