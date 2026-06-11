import Foundation
import Observation

/// Dependency container handed to the view tree. Capability services sit behind
/// protocols (NFR-20); real implementations replace mocks module by module, and
/// the simulator keeps mock inference since MLX needs a physical device.
@Observable
final class AppEnvironment {
    let database: AppDatabase
    let inference: any InferenceServicing
    let modelManager: any ModelManaging
    let search: any SearchServicing
    let documents: any DocumentServicing
    let voice: any VoiceServicing

    init(
        database: AppDatabase,
        inference: any InferenceServicing,
        modelManager: any ModelManaging,
        search: any SearchServicing,
        documents: any DocumentServicing,
        voice: any VoiceServicing
    ) {
        self.database = database
        self.inference = inference
        self.modelManager = modelManager
        self.search = search
        self.documents = documents
        self.voice = voice
    }

    var conversationStore: ConversationStore { ConversationStore(database: database) }
    var messageStore: MessageStore { MessageStore(database: database) }
    var documentStore: DocumentStore { DocumentStore(database: database) }
    var settingsStore: SettingsStore { SettingsStore(database: database) }
    var egressEventStore: EgressEventStore { EgressEventStore(database: database) }

    /// Wires the services for a normal app launch. UI tests pass "--mock-services"
    /// to force the all-mock environment regardless of platform.
    static func bootstrap() -> AppEnvironment {
        if ProcessInfo.processInfo.arguments.contains("--mock-services") {
            return .mock()
        }
        // Persistence is real everywhere; capability services arrive module by module.
        let database: AppDatabase
        do {
            database = try AppDatabase.live()
        } catch {
            // Last resort: keep the app usable this session without persistence.
            database = (try? AppDatabase.inMemory()) ?? { fatalError("Cannot open any database: \(error)") }()
        }
        return AppEnvironment(
            database: database,
            inference: MockInferenceService(),
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            search: MockSearchService(),
            documents: MockDocumentService(),
            voice: MockVoiceService()
        )
    }

    static func mock(
        inference: (any InferenceServicing)? = nil,
        modelManager: (any ModelManaging)? = nil
    ) -> AppEnvironment {
        AppEnvironment(
            database: (try? AppDatabase.inMemory()) ?? { fatalError("Cannot open in-memory database") }(),
            inference: inference ?? MockInferenceService(),
            modelManager: modelManager ?? MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            search: MockSearchService(),
            documents: MockDocumentService(),
            voice: MockVoiceService()
        )
    }
}
