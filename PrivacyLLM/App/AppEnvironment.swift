import Foundation
import Observation

/// Dependency container handed to the view tree. Capability services sit behind
/// protocols (NFR-20); real implementations replace mocks module by module, and
/// the simulator keeps mock inference since MLX needs a physical device.
@Observable
final class AppEnvironment {
    let inference: any InferenceServicing
    let modelManager: any ModelManaging
    let search: any SearchServicing
    let documents: any DocumentServicing
    let voice: any VoiceServicing

    init(
        inference: any InferenceServicing,
        modelManager: any ModelManaging,
        search: any SearchServicing,
        documents: any DocumentServicing,
        voice: any VoiceServicing
    ) {
        self.inference = inference
        self.modelManager = modelManager
        self.search = search
        self.documents = documents
        self.voice = voice
    }

    /// Wires the services for a normal app launch. UI tests pass "--mock-services"
    /// to force the all-mock environment regardless of platform.
    static func bootstrap() -> AppEnvironment {
        if ProcessInfo.processInfo.arguments.contains("--mock-services") {
            return .mock()
        }
        // Real services arrive in later modules; until then everything is mocked.
        return .mock()
    }

    static func mock(
        inference: (any InferenceServicing)? = nil,
        modelManager: (any ModelManaging)? = nil
    ) -> AppEnvironment {
        AppEnvironment(
            inference: inference ?? MockInferenceService(),
            modelManager: modelManager ?? MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            search: MockSearchService(),
            documents: MockDocumentService(),
            voice: MockVoiceService()
        )
    }
}
