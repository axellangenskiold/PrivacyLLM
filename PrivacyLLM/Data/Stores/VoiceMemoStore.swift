import Foundation

/// Local persistence for generated voice memos: a JSON manifest plus the audio
/// files, both inside one directory in the app container. iOS Data Protection
/// covers them at rest (same as the rest of the app's on-device data).
/// ponytail: JSON manifest, not a GRDB table — a handful of memos never needs a
/// query engine or a migration.
nonisolated struct VoiceMemoStore: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var manifestURL: URL { directory.appending(path: "memos.json") }

    func audioURL(for memo: VoiceMemo) -> URL { directory.appending(path: memo.audioFileName) }

    /// A fresh (fileName, url) for a synthesis run.
    func newAudioFile() -> (fileName: String, url: URL) {
        let name = "\(UUID().uuidString).m4a"
        return (name, directory.appending(path: name))
    }

    func all() -> [VoiceMemo] {
        guard let data = try? Data(contentsOf: manifestURL),
              let memos = try? JSONDecoder().decode([VoiceMemo].self, from: data)
        else { return [] }
        return memos
    }

    func upsert(_ memo: VoiceMemo) {
        var memos = all()
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[index] = memo
        } else {
            memos.append(memo)
        }
        write(memos)
    }

    /// Persists just the resume point (called on pause/background — cheap).
    func updatePosition(_ id: UUID, seconds: Double) {
        var memos = all()
        guard let index = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[index].positionSeconds = seconds
        write(memos)
    }

    func delete(_ memo: VoiceMemo) {
        write(all().filter { $0.id != memo.id })
        try? FileManager.default.removeItem(at: audioURL(for: memo))
    }

    private func write(_ memos: [VoiceMemo]) {
        guard let data = try? JSONEncoder().encode(memos) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
