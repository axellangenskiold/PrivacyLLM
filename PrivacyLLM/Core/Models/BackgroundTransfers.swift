import Foundation

/// One background `URLSession` for model weights, so a download keeps going
/// after the user leaves the app (NFR-12).
///
/// The transfer model is unchanged from the foreground path: one file at a
/// time, `Range` header from what is already on disk, append the delivered
/// bytes, verify the checksum. Only the session differs. Two consequences
/// worth knowing:
///
/// - A task that finishes while the app is suspended has no continuation left
///   to resume, so the delegate writes the file to the destination encoded in
///   `taskDescription`. On the next launch the size check finds it done and
///   moves on.
/// - Only the *enqueued* file continues while suspended; the next one starts
///   when the app runs again. MLX repos are one large weights file plus small
///   configs, so in practice the file that matters is the one that continues.
///
/// ponytail: no parallel transfers. The Hub throttles per connection anyway,
/// and serial keeps resume state to "what's on disk".
nonisolated protocol FileTransferring: Sendable {
    /// Fetches `request` and appends the delivered bytes to `destination`.
    /// `existingBytes` is what is already on disk, reported back as part of the
    /// running per-file total.
    func download(
        _ request: URLRequest,
        appendingTo destination: URL,
        existingBytes: Int64,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws
}

final class BackgroundTransfers: NSObject, FileTransferring, @unchecked Sendable {
    static let shared = BackgroundTransfers()

    /// Set by the app delegate so iOS can be told when the queue is drained.
    var backgroundEventsCompletion: (@Sendable () -> Void)?

    private let separator = "\u{1}"
    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var progressHandlers: [Int: @Sendable (Int64) -> Void] = [:]
    private var baseOffsets: [Int: Int64] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: "com.axellangenskiold.PrivacyLLM.model-downloads"
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    /// Downloads `request` and appends the bytes to `destination`.
    /// `existingBytes` is what is already there, used only to report progress
    /// as a running total for the file.
    func download(
        _ request: URLRequest,
        appendingTo destination: URL,
        existingBytes: Int64,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let task = session.downloadTask(with: request)
        task.taskDescription = destination.path + separator + String(existingBytes)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                continuations[task.taskIdentifier] = continuation
                progressHandlers[task.taskIdentifier] = onProgress
                baseOffsets[task.taskIdentifier] = existingBytes
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Re-attaches nothing, but tells callers whether the session still has work
    /// in flight from a previous launch — the manager uses it to avoid starting
    /// a second transfer for a file iOS is already fetching.
    func hasTasksInFlight() async -> Bool {
        await !session.allTasks.isEmpty
    }

    private func finish(_ taskIdentifier: Int, with error: Error?) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: taskIdentifier)
        progressHandlers[taskIdentifier] = nil
        baseOffsets[taskIdentifier] = nil
        lock.unlock()
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    /// Appends a delivered temp file onto the partial file on disk.
    private func append(_ temporary: URL, toPath path: String) throws {
        let destination = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.fileExists(atPath: path) else {
            try FileManager.default.moveItem(at: temporary, to: destination)
            return
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let reader = try FileHandle(forReadingFrom: temporary)
        defer { try? reader.close() }
        while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }
    }
}

extension BackgroundTransfers: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let description = downloadTask.taskDescription,
              let separatorIndex = description.range(of: separator, options: .backwards)
        else { return }
        let path = String(description[description.startIndex..<separatorIndex.lowerBound])

        // A 200 means the server ignored our Range and sent the whole file, so
        // whatever was on disk is stale and must go before appending.
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
        do {
            try append(location, toPath: path)
        } catch {
            finish(downloadTask.taskIdentifier, with: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let handler = progressHandlers[downloadTask.taskIdentifier]
        let base = baseOffsets[downloadTask.taskIdentifier] ?? 0
        lock.unlock()
        handler?(base + totalBytesWritten)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as? URLError)?.code != .cancelled {
            finish(task.taskIdentifier, with: error)
        } else {
            finish(task.taskIdentifier, with: nil)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = backgroundEventsCompletion
        backgroundEventsCompletion = nil
        DispatchQueue.main.async { completion?() }
    }
}

/// Foreground streaming transfer. Background sessions ignore `protocolClasses`,
/// so this is what the download tests drive — and what any caller that supplies
/// its own `URLSession` gets.
nonisolated struct SessionTransfers: FileTransferring {
    var session: URLSession
    var chunkSize = 256 * 1024

    func download(
        _ request: URLRequest,
        appendingTo destination: URL,
        existingBytes: Int64,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        var existing = existingBytes
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 206:
            break
        case 200:
            // Server ignored the range; the partial file is stale.
            if existing > 0 {
                try? FileManager.default.removeItem(at: destination)
                existing = 0
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

        var written = existing
        var buffer = Data(capacity: chunkSize)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                try Task.checkCancellation()
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                onProgress(written)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            onProgress(written)
        }
    }
}
