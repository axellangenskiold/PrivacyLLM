import Foundation
import MetricKit

/// Local-only crash/hang/metric collection (NFR-11). Payloads are written to
/// Application Support/Diagnostics and never transmitted anywhere (PR-10) —
/// inspect them via Xcode's device file browser when debugging.
nonisolated final class MetricsCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsCollector()

    private let directory: URL = {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let dir = base.appending(path: "Diagnostics", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            write(payload.jsonRepresentation(), prefix: "diagnostic")
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            write(payload.jsonRepresentation(), prefix: "metrics")
        }
    }

    private func write(_ data: Data, prefix: String) {
        let stamp = ISO8601DateFormatter().string(from: .now)
        let url = directory.appending(path: "\(prefix)-\(stamp)-\(UUID().uuidString.prefix(6)).json")
        try? data.write(to: url)
        pruneOldFiles()
    }

    /// Local logs shouldn't grow unbounded; keep the newest ~50.
    private func pruneOldFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        ), files.count > 50 else { return }
        let sorted = files.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return l < r
        }
        for url in sorted.prefix(files.count - 50) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
