import CryptoKit
import Foundation
import Testing
@testable import PrivacyLLM

/// Serves canned responses for huggingface URLs, with Range support so the
/// downloader's resume path can be exercised offline.
final class HFMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: Data] = [:]
    nonisolated(unsafe) static var requestedRanges: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, var body = Self.responses[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        var statusCode = 200
        var headers: [String: String] = ["Content-Length": "\(body.count)"]
        if let range = request.value(forHTTPHeaderField: "Range"),
           let start = Int(range.replacingOccurrences(of: "bytes=", with: "").split(separator: "-")[0]) {
            Self.requestedRanges[url.absoluteString] = range
            statusCode = 206
            headers["Content-Range"] = "bytes \(start)-\(body.count - 1)/\(body.count)"
            body = body.subdata(in: start..<body.count)
        }
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ModelDownloaderTests {
    private let weightsContent = Data(repeating: 0xAB, count: 300_000)
    private let configContent = Data("config-content".utf8)
    // `printf 'config-content' | git hash-object --stdin`
    private let configGitSHA1 = "fd6670b567aad4d8abd4f6aa03e14be29d3c7bba"

    private var weightsSHA256: String {
        SHA256.hash(data: weightsContent).map { String(format: "%02x", $0) }.joined()
    }

    private func spec(repo: String = "test/repo") -> ModelSpec {
        var spec = ModelSpec.previewFast
        spec.hfRepo = repo
        return spec
    }

    private func treeJSON(weightsSHA: String) -> Data {
        Data("""
        [
            {"type": "file", "path": ".gitattributes", "size": 10, "oid": "ignored"},
            {"type": "file", "path": "README.md", "size": 10, "oid": "ignored"},
            {"type": "file", "path": "config.json", "size": \(configContent.count), "oid": "\(configGitSHA1)"},
            {"type": "file", "path": "model.safetensors", "size": \(weightsContent.count),
             "oid": "sha1ignored", "lfs": {"oid": "\(weightsSHA)", "size": \(weightsContent.count)}}
        ]
        """.utf8)
    }

    private func makeFixture(weightsSHA: String? = nil) -> (ModelDownloader, ModelStore, ModelSpec) {
        let spec = spec()
        HFMockURLProtocol.responses = [
            "https://huggingface.co/api/models/\(spec.hfRepo)/tree/main?recursive=true":
                treeJSON(weightsSHA: weightsSHA ?? weightsSHA256),
            "https://huggingface.co/\(spec.hfRepo)/resolve/main/config.json": configContent,
            "https://huggingface.co/\(spec.hfRepo)/resolve/main/model.safetensors": weightsContent,
        ]
        HFMockURLProtocol.requestedRanges = [:]
        let session = HuggingFaceAPI.makeSession(protocolClasses: [HFMockURLProtocol.self])
        let base = FileManager.default.temporaryDirectory.appending(path: "model-tests-\(UUID().uuidString)")
        let store = ModelStore(baseDirectory: base)
        let downloader = ModelDownloader(api: HuggingFaceAPI(session: session), store: store, chunkSize: 64 * 1024)
        return (downloader, store, spec)
    }

    @Test func fileListSkipsRepoHousekeeping() async throws {
        let (downloader, _, spec) = makeFixture()
        let files = try await downloader.api.fileList(repo: spec.hfRepo)
        #expect(files.map(\.path) == ["config.json", "model.safetensors"])
        #expect(files[0].gitSHA1 == configGitSHA1)
        #expect(files[1].sha256 == weightsSHA256)
    }

    @Test func downloadsVerifiesAndPromotes() async throws {
        let (downloader, store, spec) = makeFixture()
        var lastProgress: (Int64, Int64) = (0, 0)
        try await downloader.download(spec: spec) { downloaded, total in
            lastProgress = (downloaded, total)
        }
        #expect(store.isDownloaded(spec.id))
        #expect(!store.hasPartial(spec.id))
        #expect(lastProgress.0 == lastProgress.1)
        let weights = store.directory(for: spec.id).appending(path: "model.safetensors")
        #expect(try Data(contentsOf: weights) == weightsContent)
    }

    @Test func corruptDownloadThrowsChecksumMismatch() async throws {
        let bogusSHA = String(repeating: "0", count: 64)
        let (downloader, store, spec) = makeFixture(weightsSHA: bogusSHA)
        await #expect(throws: ModelManagerError.self) {
            try await downloader.download(spec: spec) { _, _ in }
        }
        #expect(!store.isDownloaded(spec.id))
        // The corrupt file is removed so a retry starts clean (NFR-13).
        let leftover = store.partialDirectory(for: spec.id).appending(path: "model.safetensors")
        #expect(ModelDownloader.fileSize(leftover) == 0)
    }

    @Test func resumeRequestsRemainingBytesOnly() async throws {
        let (downloader, store, spec) = makeFixture()
        // Simulate an interrupted download: half the weights already on disk.
        let partialDir = store.partialDirectory(for: spec.id)
        try FileManager.default.createDirectory(at: partialDir, withIntermediateDirectories: true)
        let half = weightsContent.count / 2
        try weightsContent.subdata(in: 0..<half).write(to: partialDir.appending(path: "model.safetensors"))

        try await downloader.download(spec: spec) { _, _ in }

        let weightsURL = "https://huggingface.co/\(spec.hfRepo)/resolve/main/model.safetensors"
        #expect(HFMockURLProtocol.requestedRanges[weightsURL] == "bytes=\(half)-")
        #expect(store.isDownloaded(spec.id))
        let weights = store.directory(for: spec.id).appending(path: "model.safetensors")
        #expect(try Data(contentsOf: weights) == weightsContent)
    }

    @Test func gitBlobHashMatchesGit() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "blob-\(UUID().uuidString)")
        try configContent.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ModelDownloader.gitBlobSHA1Hex(of: url) == configGitSHA1)
    }
}

struct ModelCatalogTests {
    @Test func bundledCatalogIsValid() {
        let catalog = ModelCatalogLoader.load()
        #expect(!catalog.isEmpty)
        #expect(Set(catalog.map(\.id)).count == catalog.count)
        for spec in catalog {
            #expect(!spec.licenseName.isEmpty)
            #expect(spec.sizeBytes > 100_000_000)
            #expect(!spec.roles.isEmpty)
        }
        #expect(catalog.contains { $0.roles.contains(.fast) })
        #expect(catalog.contains { $0.roles.contains(.thinking) })
    }
}

struct RealModelManagerTests {
    private func makeManager(markDownloaded: [String] = []) throws -> (RealModelManager, ModelStore) {
        let base = FileManager.default.temporaryDirectory.appending(path: "manager-tests-\(UUID().uuidString)")
        let store = ModelStore(baseDirectory: base)
        for id in markDownloaded {
            let dir = store.partialDirectory(for: id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("w".utf8).write(to: dir.appending(path: "model.safetensors"))
            try store.promotePartial(for: id)
        }
        let database = try AppDatabase.inMemory()
        let manager = RealModelManager(
            catalog: ModelSpec.previewCatalog,
            store: store,
            settingsStore: SettingsStore(database: database),
            egressEventStore: EgressEventStore(database: database)
        )
        return (manager, store)
    }

    @Test func seedsPhasesFromDisk() async throws {
        let (manager, _) = try makeManager(markDownloaded: [ModelSpec.previewFast.id])
        let states = await manager.states()
        #expect(states.first { $0.id == ModelSpec.previewFast.id }?.phase == .downloaded)
        #expect(states.first { $0.id == ModelSpec.previewThinking.id }?.phase == .notDownloaded)
        let directory = await manager.localDirectory(for: ModelSpec.previewFast.id)
        #expect(directory != nil)
    }

    @Test func activeSelectionPersistsAndValidates() async throws {
        let (manager, _) = try makeManager(markDownloaded: [ModelSpec.previewFast.id])
        // Selecting a downloaded model sticks.
        await manager.setActiveModel(ModelSpec.previewFast.id, for: .fast)
        #expect(await manager.activeModelID(for: .fast) == ModelSpec.previewFast.id)
        // A selection pointing at a model that isn't on disk resolves to nil.
        await manager.setActiveModel(ModelSpec.previewThinking.id, for: .thinking)
        #expect(await manager.activeModelID(for: .thinking) == nil)
    }

    @Test func deleteClearsStateAndSelection() async throws {
        let (manager, store) = try makeManager(markDownloaded: [ModelSpec.previewFast.id])
        await manager.setActiveModel(ModelSpec.previewFast.id, for: .fast)
        try await manager.deleteModel(ModelSpec.previewFast.id)
        #expect(!store.isDownloaded(ModelSpec.previewFast.id))
        #expect(await manager.activeModelID(for: .fast) == nil)
        let states = await manager.states()
        #expect(states.first { $0.id == ModelSpec.previewFast.id }?.phase == .notDownloaded)
    }
}
