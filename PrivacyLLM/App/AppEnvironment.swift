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
    let egressMonitor: EgressMonitor

    init(
        database: AppDatabase,
        inference: any InferenceServicing,
        modelManager: any ModelManaging,
        search: (any SearchServicing)? = nil,
        documents: any DocumentServicing,
        voice: any VoiceServicing
    ) {
        self.database = database
        self.inference = inference
        self.modelManager = modelManager
        let monitor = EgressMonitor(store: EgressEventStore(database: database))
        egressMonitor = monitor
        self.search = search ?? ConfiguredSearchService(
            settingsStore: SettingsStore(database: database),
            egress: monitor
        )
        self.documents = documents
        self.voice = voice
    }

    /// Tools available to the agent loop; the search tool reaches the network
    /// only through the gated SearchServicing (TL-4).
    var chatTools: [any LocalTool] {
        [DateTimeTool(), CalculatorTool(), UnitConversionTool(), WebSearchTool(search: search)]
    }

    var conversationStore: ConversationStore { ConversationStore(database: database) }
    var messageStore: MessageStore { MessageStore(database: database) }
    var documentStore: DocumentStore { DocumentStore(database: database) }
    var settingsStore: SettingsStore { SettingsStore(database: database) }
    var egressEventStore: EgressEventStore { EgressEventStore(database: database) }

    /// Wires the services for a normal app launch. UI tests pass "--mock-services"
    /// to force the all-mock environment, plus "--skip-onboarding" to land
    /// directly in the chat list.
    static func bootstrap() -> AppEnvironment {
        if ProcessInfo.processInfo.arguments.contains("--mock-services") {
            let environment = AppEnvironment.mock()
            if ProcessInfo.processInfo.arguments.contains("--skip-onboarding") {
                let settings = environment.settingsStore
                Task { try? await settings.set(true, for: .hasCompletedOnboarding) }
            }
            return environment
        }
        // Persistence is real everywhere; capability services arrive module by module.
        let database: AppDatabase
        do {
            database = try AppDatabase.live()
        } catch {
            // Last resort: keep the app usable this session without persistence.
            database = (try? AppDatabase.inMemory()) ?? { fatalError("Cannot open any database: \(error)") }()
        }
        let modelManager = RealModelManager(
            settingsStore: SettingsStore(database: database),
            egressEventStore: EgressEventStore(database: database)
        )
        // MLX needs a physical device's GPU; the simulator chats with the mock.
        #if targetEnvironment(simulator)
        let inference: any InferenceServicing = MockInferenceService()
        #else
        let inference: any InferenceServicing = MLXInferenceService()
        #endif
        return AppEnvironment(
            database: database,
            inference: inference,
            modelManager: modelManager,
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
