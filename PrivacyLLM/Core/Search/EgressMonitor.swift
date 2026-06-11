import Foundation
import Observation

/// Receives notice immediately before and after a query leaves the device.
nonisolated protocol EgressReporting: Sendable {
    func searchWillFire(query: String, host: String) async
    func searchDidFinish() async
}

/// Drives the live egress indicator (FR-21, PR-13) and appends each event to
/// the local-only privacy activity log (PR-14).
@Observable
final class EgressMonitor: EgressReporting {
    private(set) var activeSearchCount = 0
    var isSearchInFlight: Bool { activeSearchCount > 0 }

    private let store: EgressEventStore

    init(store: EgressEventStore) {
        self.store = store
    }

    func searchWillFire(query: String, host: String) {
        activeSearchCount += 1
        let store = store
        Task {
            try? await store.append(EgressEvent(kind: .webSearch, destinationHost: host, detail: query))
        }
    }

    func searchDidFinish() {
        activeSearchCount = max(0, activeSearchCount - 1)
    }
}
