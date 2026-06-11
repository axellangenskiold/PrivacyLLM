import Foundation
import Testing
@testable import PrivacyLLM

#if targetEnvironment(simulator)
private let onPhysicalDevice = false
#else
private let onPhysicalDevice = true
#endif

/// TR-7: real end-to-end inference with a tiny model. Runs only on a physical
/// device (MLX needs the GPU). First run downloads ~80 MB from Hugging Face;
/// the weights are cached for subsequent runs.
@Suite(.enabled(if: onPhysicalDevice))
struct MLXDeviceIntegrationTests {
    private static let tinySpec = ModelSpec(
        id: "smollm-135m-test",
        displayName: "SmolLM 135M (test)",
        family: "smollm",
        hfRepo: "mlx-community/SmolLM-135M-Instruct-4bit",
        roles: [.fast],
        sizeBytes: 79_217_711,
        parameterCount: "135M",
        quantization: "4-bit",
        minRAMGB: 2,
        contextLength: 2048,
        licenseName: "Apache-2.0",
        licenseURLString: "https://www.apache.org/licenses/LICENSE-2.0",
        capabilities: ModelCapabilities()
    )

    @Test(.timeLimit(.minutes(10)))
    func tinyModelLoadsAndStreams() async throws {
        let spec = Self.tinySpec
        let store = ModelStore()
        if !store.isDownloaded(spec.id) {
            let downloader = ModelDownloader(api: HuggingFaceAPI(), store: store)
            try await downloader.download(spec: spec) { _, _ in }
        }
        #expect(store.isDownloaded(spec.id))

        let service = MLXInferenceService()
        try await service.loadModel(spec: spec, directory: store.directory(for: spec.id)) { _ in }
        let loaded = await service.loadedModel
        #expect(loaded?.id == spec.id)

        var config = GenerationConfig()
        config.sampling.maxTokens = 24
        let input = PromptInput(messages: [
            PromptMessage(role: .user, content: "Say hello in one short sentence."),
        ])

        var text = ""
        var stats: GenerationStats?
        let stream = await service.generate(input, config: config)
        for try await event in stream {
            switch event {
            case .token(let piece): text += piece
            case .finished(let finalStats): stats = finalStats
            }
        }

        #expect(!text.isEmpty)
        #expect((stats?.completionTokens ?? 0) > 0)
        #expect((stats?.tokensPerSecond ?? 0) > 0)

        let tokenCount = await service.countTokens("hello world")
        #expect((tokenCount ?? 0) > 0)

        await service.unloadModel()
        let afterUnload = await service.loadedModel
        #expect(afterUnload == nil)
    }
}
