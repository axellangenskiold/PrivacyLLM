import Foundation

nonisolated struct HFFileEntry: Hashable, Sendable {
    var path: String
    var size: Int64
    /// SHA-256 for LFS-stored files (the big weights).
    var sha256: String?
    /// Git blob SHA-1 for small plain files (configs, tokenizers).
    var gitSHA1: String?
}

/// Minimal Hugging Face Hub client: file listing with checksums, and download
/// URLs. Together with the search provider these are the only hosts the app
/// ever contacts (PR-2).
nonisolated struct HuggingFaceAPI: Sendable {
    static let host = "huggingface.co"

    var session: URLSession

    init(session: URLSession = HuggingFaceAPI.makeSession()) {
        self.session = session
    }

    static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return URLSession(configuration: configuration)
    }

    func fileList(repo: String, revision: String = "main") async throws -> [HFFileEntry] {
        let url = URL(string: "https://\(Self.host)/api/models/\(repo)/tree/\(revision)?recursive=true")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let entries = try JSONDecoder().decode([TreeEntry].self, from: data)
        return entries.compactMap { entry -> HFFileEntry? in
            guard entry.type == "file" else { return nil }
            let name = (entry.path as NSString).lastPathComponent
            // Repo housekeeping files aren't needed to run the model.
            if name.hasPrefix(".") || name.lowercased().hasSuffix(".md") { return nil }
            if let lfs = entry.lfs {
                return HFFileEntry(path: entry.path, size: lfs.size, sha256: lfs.oid, gitSHA1: nil)
            }
            return HFFileEntry(path: entry.path, size: entry.size ?? 0, sha256: nil, gitSHA1: entry.oid)
        }
    }

    func downloadURL(repo: String, revision: String = "main", path: String) -> URL {
        URL(string: "https://\(Self.host)/\(repo)/resolve/\(revision)/\(path)")!
    }

    private struct TreeEntry: Decodable {
        struct LFS: Decodable {
            var oid: String
            var size: Int64
        }

        var type: String
        var path: String
        var size: Int64?
        var oid: String?
        var lfs: LFS?
    }
}
