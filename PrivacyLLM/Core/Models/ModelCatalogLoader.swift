import Foundation

nonisolated struct ModelCatalogFile: Codable, Sendable {
    var version: Int
    var models: [ModelSpec]
}

/// The catalog ships as Config/ModelCatalog.json so models can be added
/// without touching code (NFR-22, MR-2).
nonisolated enum ModelCatalogLoader {
    static func load(bundle: Bundle = .main) -> [ModelSpec] {
        guard let url = bundle.url(forResource: "ModelCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ModelCatalogFile.self, from: data)
        else { return [] }
        return file.models
    }
}
