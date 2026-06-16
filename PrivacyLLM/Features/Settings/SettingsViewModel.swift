import Foundation
import Observation

@Observable
final class SettingsViewModel {
    var searchEnabled = false {
        didSet { persist(searchEnabled, for: .searchEnabled, ifChanged: oldValue != searchEnabled) }
    }

    var searchProviderID = "duckduckgo" {
        didSet { persist(searchProviderID, for: .searchProviderID, ifChanged: oldValue != searchProviderID) }
    }

    var globalSystemPrompt = "" {
        didSet { persist(globalSystemPrompt, for: .globalSystemPrompt, ifChanged: oldValue != globalSystemPrompt) }
    }

    var temperature = 0.7 {
        didSet { persistSampling(ifChanged: oldValue != temperature) }
    }

    var topP = 0.9 {
        didSet { persistSampling(ifChanged: oldValue != topP) }
    }

    var maxTokens = 1024 {
        didSet { persistSampling(ifChanged: oldValue != maxTokens) }
    }

    var contextLength = 4096 {
        didSet { persist(contextLength, for: .contextLength, ifChanged: oldValue != contextLength) }
    }

    var appearance = AppearanceSetting.system {
        didSet {
            guard oldValue != appearance else { return }
            environment.appearance = appearance
            persist(appearance, for: .appearance, ifChanged: true)
        }
    }

    private(set) var providers: [SearchProvider] = []
    private(set) var downloadedModels: [ModelSpec] = []
    private(set) var activeFastID: String?
    private(set) var activeThinkingID: String?
    private(set) var recentEgressEvents: [EgressEvent] = []
    private(set) var loaded = false

    /// Llama 3.2 Community License (§1.b.i) requires a visible "Built with Llama"
    /// attribution plus a copy of the license whenever a Llama model ships. Driven
    /// by the catalog so the attribution disappears automatically if Llama is ever
    /// dropped from Config/ModelCatalog.json. Returns the license URL to link, or
    /// nil when no Llama-family model is offered.
    var llamaLicenseURL: URL? {
        environment.modelManager.catalog
            .first { $0.family.lowercased().hasPrefix("llama") }
            .flatMap { URL(string: $0.licenseURLString) }
    }

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() async {
        let settings = environment.settingsStore
        providers = SearchProviderLoader.load().providers
        searchEnabled = (try? await settings.searchEnabled()) ?? false
        searchProviderID = (try? await settings.value(for: .searchProviderID, default: "duckduckgo")) ?? "duckduckgo"
        globalSystemPrompt = (try? await settings.globalSystemPrompt()) ?? ""
        let sampling = (try? await settings.sampling()) ?? SamplingParams()
        temperature = sampling.temperature
        topP = sampling.topP
        maxTokens = sampling.maxTokens
        contextLength = (try? await settings.contextLength()) ?? 4096
        appearance = (try? await settings.value(for: .appearance, default: AppearanceSetting.system)) ?? .system
        await refreshModels()
        await refreshEgressEvents()
        loaded = true
    }

    func refreshModels() async {
        let manager = environment.modelManager
        let states = await manager.states()
        downloadedModels = states.filter { $0.phase == .downloaded }.map(\.spec)
        activeFastID = await manager.activeModelID(for: .fast)
        activeThinkingID = await manager.activeModelID(for: .thinking)
    }

    func setActiveModel(_ id: String, role: ModelRole) {
        let manager = environment.modelManager
        Task {
            await manager.setActiveModel(id, for: role)
            await refreshModels()
        }
    }

    func refreshEgressEvents() async {
        recentEgressEvents = (try? await environment.egressEventStore.recent(limit: 50)) ?? []
    }

    func clearEgressLog() {
        Task {
            try? await environment.egressEventStore.deleteAll()
            await refreshEgressEvents()
        }
    }

    // MARK: Data controls (FR-40)

    func clearAllConversations() async {
        try? await environment.conversationStore.deleteAll()
    }

    func clearDocumentIndex() async {
        try? await environment.documentStore.deleteAll()
    }

    func resetApp() async {
        try? await environment.database.eraseAllContent()
        await load()
    }

    // MARK: Persistence plumbing

    private func persist(_ value: some Codable & Sendable, for key: SettingsKey, ifChanged: Bool) {
        guard loaded, ifChanged else { return }
        let settings = environment.settingsStore
        Task { try? await settings.set(value, for: key) }
    }

    private func persistSampling(ifChanged: Bool) {
        guard loaded, ifChanged else { return }
        let sampling = SamplingParams(temperature: temperature, topP: topP, maxTokens: maxTokens)
        let settings = environment.settingsStore
        Task { try? await settings.set(sampling, for: .sampling) }
    }
}
