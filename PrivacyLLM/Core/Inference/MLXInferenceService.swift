import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// On-device GPU inference via MLX (OD-1). Requires a physical device — the
/// simulator's Metal stack can't run MLX, so AppEnvironment routes the
/// simulator to MockInferenceService instead.
actor MLXInferenceService: InferenceServicing {
    private var container: ModelContainer?
    private var loadedSpec: ModelSpec?
    private var generationTask: Task<Void, Never>?
    private var gpuConfigured = false

    var loadedModel: ModelSpec? { loadedSpec }

    func loadModel(spec: ModelSpec, directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        #if targetEnvironment(simulator)
        throw InferenceError.unsupportedOnSimulator
        #else
        unloadModel()
        if !gpuConfigured {
            // Bound the Metal buffer cache so pressure handling has less to reclaim (NFR-6).
            MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
            gpuConfigured = true
        }
        do {
            let configuration = ModelConfiguration(directory: directory)
            let container = try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration
            ) { loadProgress in
                progress(loadProgress.fractionCompleted)
            }
            self.container = container
            loadedSpec = spec
        } catch {
            throw InferenceError.loadFailed(error.localizedDescription)
        }
        #endif
    }

    func unloadModel() {
        container = nil
        loadedSpec = nil
        #if !targetEnvironment(simulator)
        if gpuConfigured {
            MLX.GPU.clearCache()
        }
        #endif
    }

    func memoryFootprintBytes() -> Int64? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard loadedSpec != nil else { return nil }
        return Int64(MLX.GPU.activeMemory)
        #endif
    }

    func countTokens(_ text: String) async -> Int? {
        guard let container else { return nil }
        let tokenizer = await container.tokenizer
        return tokenizer.encode(text: text).count
    }

    func reduceMemoryFootprint() {
        #if !targetEnvironment(simulator)
        if gpuConfigured {
            MLX.GPU.clearCache()
        }
        #endif
    }

    func cancelGeneration() {
        generationTask?.cancel()
    }

    func generate(_ input: PromptInput, config: GenerationConfig) -> AsyncThrowingStream<InferenceEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent, Error>.makeStream()
        guard let container, let spec = loadedSpec else {
            continuation.finish(throwing: InferenceError.modelNotLoaded)
            return stream
        }

        let parameters = GenerateParameters(
            maxTokens: config.sampling.maxTokens,
            temperature: Float(config.sampling.temperature),
            topP: Float(config.sampling.topP)
        )

        let task = Task {
            let start = ContinuousClock.now
            do {
                try await container.perform { (context: ModelContext) in
                    // UserInput is not Sendable; build it inside the isolation domain.
                    let userInput = Self.userInput(for: input, spec: spec, config: config)
                    let lmInput = try await context.processor.prepare(input: userInput)
                    let generations = try MLXLMCommon.generate(
                        input: lmInput,
                        parameters: parameters,
                        context: context
                    )
                    var firstTokenSeconds: Double?
                    var info: GenerateCompletionInfo?
                    for await generation in generations {
                        if Task.isCancelled { break }
                        switch generation {
                        case .chunk(let text):
                            if firstTokenSeconds == nil {
                                firstTokenSeconds = Self.seconds(since: start)
                            }
                            continuation.yield(.token(text))
                        case .toolCall(let call):
                            continuation.yield(.toolCall(Self.domainToolCall(from: call)))
                        case .info(let completionInfo):
                            info = completionInfo
                        default:
                            break
                        }
                    }
                    continuation.yield(.finished(GenerationStats(
                        promptTokens: info?.promptTokenCount,
                        completionTokens: info?.generationTokenCount,
                        tokensPerSecond: info?.tokensPerSecond,
                        firstTokenSeconds: firstTokenSeconds
                    )))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: InferenceError.generationFailed(error.localizedDescription))
            }
        }
        generationTask = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private static func userInput(for input: PromptInput, spec: ModelSpec, config: GenerationConfig) -> UserInput {
        let chat: [Chat.Message] = input.messages.map { message in
            switch message.role {
            case .system: .system(message.content)
            case .user: .user(message.content)
            case .assistant: .assistant(message.content)
            case .tool: .tool(message.content)
            }
        }
        var additionalContext: [String: any Sendable] = [:]
        if spec.capabilities.nativeThinking {
            // Qwen3-style chat templates honor enable_thinking (OD-2, MR-5).
            additionalContext["enable_thinking"] = config.thinkingEnabled
        }
        return UserInput(
            chat: chat,
            tools: mlxToolSpecs(from: input.tools),
            additionalContext: additionalContext.isEmpty ? nil : additionalContext
        )
    }

    /// Bridges the app's tool specs into the template-native OpenAI-style
    /// dictionaries the chat template renders (TL-1).
    private static func mlxToolSpecs(from specs: [PrivacyLLM.ToolSpec]) -> [MLXLMCommon.ToolSpec]? {
        guard !specs.isEmpty else { return nil }
        return specs.map { spec in
            var parameters: any Sendable = [String: String]()
            if let decoded = try? JSONDecoder().decode(JSONValue.self, from: Data(spec.parametersJSONSchema.utf8)),
               let object = decoded.anyValue as? [String: any Sendable] {
                parameters = object
            }
            return [
                "type": "function",
                "function": [
                    "name": spec.name,
                    "description": spec.summary,
                    "parameters": parameters,
                ] as [String: any Sendable],
            ]
        }
    }

    private static func domainToolCall(from call: MLXLMCommon.ToolCall) -> PrivacyLLM.ToolCall {
        let argumentsObject = call.function.arguments.mapValues { $0.anyValue }
        let argumentsJSON: String
        if JSONSerialization.isValidJSONObject(argumentsObject),
           let data = try? JSONSerialization.data(withJSONObject: argumentsObject) {
            argumentsJSON = String(decoding: data, as: UTF8.self)
        } else {
            argumentsJSON = "{}"
        }
        return PrivacyLLM.ToolCall(name: call.function.name, argumentsJSON: argumentsJSON)
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
