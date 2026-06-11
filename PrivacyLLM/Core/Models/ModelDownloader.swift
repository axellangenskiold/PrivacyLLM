import CryptoKit
import Foundation

/// Downloads a model's files with byte-range resume (NFR-12) and verifies
/// every file's checksum before the model is marked usable (FR-13, PR-18).
/// Pause = cancel the surrounding Task; partial files stay on disk and the
/// next run resumes from the byte offset.
nonisolated struct ModelDownloader: Sendable {
    var api: HuggingFaceAPI
    var store: ModelStore
    var chunkSize = 256 * 1024

    func download(
        spec: ModelSpec,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let files = try await api.fileList(repo: spec.hfRepo)
        guard !files.isEmpty else { throw ModelManagerError.unknownModel }

        let partialDir = store.partialDirectory(for: spec.id)
        try FileManager.default.createDirectory(at: partialDir, withIntermediateDirectories: true)

        let totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
        var completedBytes: Int64 = 0

        for file in files {
            try Task.checkCancellation()
            let destination = partialDir.appending(path: file.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if Self.fileSize(destination) == file.size, (try? verify(file, at: destination)) == true {
                completedBytes += file.size
                onProgress(completedBytes, totalBytes)
                continue
            }

            let baseCompleted = completedBytes
            try await fetch(file, repo: spec.hfRepo, to: destination) { fileBytes in
                onProgress(baseCompleted + fileBytes, totalBytes)
            }

            guard (try? verify(file, at: destination)) == true else {
                try? FileManager.default.removeItem(at: destination)
                throw ModelManagerError.checksumMismatch(file: file.path)
            }
            completedBytes += file.size
            onProgress(completedBytes, totalBytes)
        }

        try store.promotePartial(for: spec.id)
    }

    private func fetch(
        _ file: HFFileEntry,
        repo: String,
        to destination: URL,
        onFileBytes: @escaping @Sendable (Int64) -> Void
    ) async throws {
        var existingSize = Self.fileSize(destination)
        if existingSize > file.size {
            // Stale leftovers from an older revision: start over.
            try? FileManager.default.removeItem(at: destination)
            existingSize = 0
        }

        var request = URLRequest(url: api.downloadURL(repo: repo, path: file.path))
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await api.session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 206:
            break
        case 200:
            // Server ignored the range; restart the file from scratch.
            if existingSize > 0 {
                try? FileManager.default.removeItem(at: destination)
                existingSize = 0
            }
        default:
            throw URLError(.badServerResponse)
        }

        if !FileManager.default.fileExists(atPath: destination.path) {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seekToEnd()

        var written = existingSize
        var buffer = Data(capacity: chunkSize)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                try Task.checkCancellation()
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                onFileBytes(written)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            onFileBytes(written)
        }
    }

    private func verify(_ file: HFFileEntry, at url: URL) throws -> Bool {
        if let expected = file.sha256 {
            return try Self.sha256Hex(of: url) == expected.lowercased()
        }
        if let expected = file.gitSHA1 {
            return try Self.gitBlobSHA1Hex(of: url) == expected.lowercased()
        }
        // No checksum advertised: accept by size alone.
        return Self.fileSize(url) == file.size
    }

    static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64).flatMap { $0 } ?? 0
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Git hashes blobs as SHA-1 of "blob <size>\0<content>".
    static func gitBlobSHA1Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(fileSize(url))\u{0}".utf8))
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
