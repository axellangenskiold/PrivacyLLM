import AVFoundation
import Foundation
import Observation

/// Owns the voice-memo library and playback. Playback position is persisted so
/// a memo resumes where it stopped, across pauses and app launches (like a
/// podcast player).
@Observable
final class VoiceMemoViewModel: NSObject {
    private(set) var memos: [VoiceMemo] = []
    private(set) var nowPlayingID: UUID?
    private(set) var isPlaying = false
    /// Live playback head, in seconds, for the currently playing memo.
    private(set) var currentTime: Double = 0

    private let store: VoiceMemoStore
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    init(environment: AppEnvironment) {
        store = environment.voiceMemoStore
        super.init()
    }

    func load() {
        memos = store.all().sorted { $0.createdAt > $1.createdAt }
    }

    func toggle(_ memo: VoiceMemo) {
        if nowPlayingID == memo.id {
            if isPlaying { pause() } else { resume() }
        } else {
            start(memo)
        }
    }

    private func start(_ memo: VoiceMemo) {
        persistPosition() // save the previously-playing memo's spot first
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: store.audioURL(for: memo))
            player.delegate = self
            // Resume where it stopped, unless it had essentially finished.
            if memo.positionSeconds > 0, memo.positionSeconds < player.duration - 0.5 {
                player.currentTime = memo.positionSeconds
            }
            player.play()
            self.player = player
            nowPlayingID = memo.id
            isPlaying = true
            currentTime = player.currentTime
            startTicker()
        } catch {
            stopPlayback()
        }
    }

    private func resume() {
        player?.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
        persistPosition()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = min(max(0, seconds), player.duration)
        player.currentTime = clamped
        currentTime = clamped
        persistPosition()
    }

    func delete(_ memo: VoiceMemo) {
        if nowPlayingID == memo.id { stopPlayback() }
        store.delete(memo)
        load()
    }

    /// Saves the resume point of the current memo (pause, background, or leaving
    /// the screen). Cheap: writes only the position.
    func persistPosition() {
        guard let id = nowPlayingID, let player else { return }
        store.updatePosition(id, seconds: player.currentTime)
        if let index = memos.firstIndex(where: { $0.id == id }) {
            memos[index].positionSeconds = player.currentTime
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        nowPlayingID = nil
        currentTime = 0
        stopTicker()
    }

    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let player = self.player, self.isPlaying else { continue }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    /// "m:ss" for durations and the playback head.
    static func timeLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension VoiceMemoViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if let id = nowPlayingID {
                store.updatePosition(id, seconds: 0) // finished → restart next time
                if let index = memos.firstIndex(where: { $0.id == id }) {
                    memos[index].positionSeconds = 0
                }
            }
            stopPlayback()
        }
    }
}
