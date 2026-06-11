import Foundation

nonisolated enum InferenceEvent: Sendable {
    /// A raw text delta from the model. Thinking-block and textual tool-call
    /// parsing happen above this layer.
    case token(String)
    /// A tool call the engine parsed natively from the model's template format.
    case toolCall(ToolCall)
    case finished(GenerationStats)
}

nonisolated enum InferenceError: Error, Sendable {
    case modelNotLoaded
    case modelFilesMissing
    case loadFailed(String)
    case generationFailed(String)
    case unsupportedOnSimulator
}

/// Loads a model, streams tokens, and supports cancellation and sampling
/// parameters. Implementations: MLXInferenceService (device), MockInferenceService
/// (simulator, previews, tests).
nonisolated protocol InferenceServicing: Sendable {
    /// The currently loaded model, if any.
    var loadedModel: ModelSpec? { get async }

    /// Loads model weights from `directory`. Reports coarse progress in 0...1 (NFR-5).
    func loadModel(spec: ModelSpec, directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws

    /// Frees model memory (NFR-7). Safe to call when nothing is loaded.
    func unloadModel() async

    /// Streams generation events. The engine applies the model's chat template
    /// to the structured messages (MR-3). Ends with `.finished` unless cancelled.
    func generate(_ input: PromptInput, config: GenerationConfig) async -> AsyncThrowingStream<InferenceEvent, Error>

    /// Stops an in-flight generation immediately (FR-2).
    func cancelGeneration() async

    /// Approximate bytes of memory held by the loaded model (FR-17).
    func memoryFootprintBytes() async -> Int64?

    /// Exact token count using the loaded model's tokenizer; nil when no
    /// tokenizer is available (callers fall back to estimation, MR-7).
    func countTokens(_ text: String) async -> Int?

    /// Drops caches without unloading the model — memory-warning response (NFR-8).
    func reduceMemoryFootprint() async
}
