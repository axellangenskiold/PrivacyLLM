import Foundation

/// On-disk layout for model weights (DR-3): Application Support/Models/<id>/,
/// with in-progress downloads under Models/.partial/<id>/. The whole tree is
/// excluded from iCloud backup (PR-7).
nonisolated struct ModelStore: Sendable {
    let baseDirectory: URL
    private static let completionMarker = ".verified"

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let support = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
            self.baseDirectory = support.appending(path: "Models", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
        excludeFromBackup(self.baseDirectory)
    }

    func directory(for modelID: String) -> URL {
        baseDirectory.appending(path: modelID, directoryHint: .isDirectory)
    }

    // MARK: Imported models

    /// Specs for user-imported models live alongside the weights so they survive
    /// relaunches without touching the bundled catalog (OD-10).
    private var importedManifestURL: URL {
        baseDirectory.appending(path: "imported.json")
    }

    func loadImportedSpecs() -> [ModelSpec] {
        guard let data = try? Data(contentsOf: importedManifestURL),
              let specs = try? JSONDecoder().decode([ModelSpec].self, from: data)
        else { return [] }
        return specs
    }

    func saveImportedSpecs(_ specs: [ModelSpec]) {
        if specs.isEmpty {
            try? FileManager.default.removeItem(at: importedManifestURL)
            return
        }
        if let data = try? JSONEncoder().encode(specs) {
            try? data.write(to: importedManifestURL)
        }
    }

    /// Copies a user-picked model folder into place and marks it ready to load.
    func importDirectory(from source: URL, as modelID: String) throws {
        let final = directory(for: modelID)
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.copyItem(at: source, to: final)
        let marker = final.appending(path: Self.completionMarker)
        try Data(ISO8601DateFormatter().string(from: .now).utf8).write(to: marker)
        excludeFromBackup(final)
    }

    func partialDirectory(for modelID: String) -> URL {
        baseDirectory.appending(path: ".partial", directoryHint: .isDirectory)
            .appending(path: modelID, directoryHint: .isDirectory)
    }

    func isDownloaded(_ modelID: String) -> Bool {
        FileManager.default.fileExists(
            atPath: directory(for: modelID).appending(path: Self.completionMarker).path
        )
    }

    func hasPartial(_ modelID: String) -> Bool {
        FileManager.default.fileExists(atPath: partialDirectory(for: modelID).path)
    }

    /// Atomically promotes a fully verified partial download (FR-13).
    func promotePartial(for modelID: String) throws {
        let final = directory(for: modelID)
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: partialDirectory(for: modelID), to: final)
        let marker = final.appending(path: Self.completionMarker)
        try Data(ISO8601DateFormatter().string(from: .now).utf8).write(to: marker)
        excludeFromBackup(final)
    }

    func deletePartial(for modelID: String) {
        try? FileManager.default.removeItem(at: partialDirectory(for: modelID))
    }

    func delete(_ modelID: String) throws {
        deletePartial(for: modelID)
        let final = directory(for: modelID)
        if FileManager.default.fileExists(atPath: final.path) {
            try FileManager.default.removeItem(at: final)
        }
    }

    func diskBytes(for modelID: String) -> Int64? {
        let directory = isDownloaded(modelID) ? directory(for: modelID) : partialDirectory(for: modelID)
        return Self.directorySize(directory)
    }

    func partialBytes(for modelID: String) -> Int64 {
        Self.directorySize(partialDirectory(for: modelID)) ?? 0
    }

    func totalDiskBytes() -> Int64 {
        Self.directorySize(baseDirectory) ?? 0
    }

    private func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static func directorySize(_ url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else { return nil }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
