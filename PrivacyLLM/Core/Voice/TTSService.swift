import AVFoundation
import Foundation

/// Voice quality tier — the user-facing speed/quality tradeoff. Standard is
/// instant and always available; Enhanced/Premium sound more natural but need a
/// one-time voice download in iOS Settings and take longer to synthesize.
nonisolated enum TTSQuality: String, Codable, Sendable, CaseIterable, Identifiable {
    case standard
    case enhanced
    case premium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .enhanced: String(localized: "Enhanced")
        case .premium: String(localized: "Premium")
        }
    }

    var detail: String {
        switch self {
        case .standard: String(localized: "Instant · robotic")
        case .enhanced: String(localized: "Slower · natural")
        case .premium: String(localized: "Slowest · most natural")
        }
    }

    var avQuality: AVSpeechSynthesisVoiceQuality {
        switch self {
        case .standard: .default
        case .enhanced: .enhanced
        case .premium: .premium
        }
    }
}

/// Which speaker reads a line. Conversations alternate the two voices; pasted
/// text uses `.primary` throughout.
nonisolated enum SpeakerRole: String, Codable, Sendable, Hashable {
    case primary
    case secondary
}

nonisolated struct SpokenLine: Codable, Sendable, Hashable {
    var text: String
    var role: SpeakerRole

    init(_ text: String, role: SpeakerRole = .primary) {
        self.text = text
        self.role = role
    }
}

nonisolated enum TTSError: Error, Sendable {
    case nothingToSpeak
    case synthesisFailed(String)
    case exportFailed(String)
}

/// Local text-to-speech (the podcast/voice-memo feature). Synthesizes entirely
/// on-device and writes a playable m4a; no audio ever leaves the phone.
/// ponytail: native AVSpeechSynthesizer — swap a neural backend behind this
/// protocol if the robotic voice isn't good enough.
nonisolated protocol TTSServicing: Sendable {
    /// Synthesizes `lines` to an m4a at `url`, returning the audio duration.
    func synthesize(lines: [SpokenLine], quality: TTSQuality, to url: URL) async throws -> Double
    /// Quality tiers the device can actually produce (has voices installed for).
    func availableQualities() async -> [TTSQuality]
}

/// AVSpeechSynthesizer backend: renders each line offline, then stitches the
/// segments into one m4a with AVMutableComposition so playback is seekable.
nonisolated final class AVSpeechTTSService: TTSServicing {
    func availableQualities() async -> [TTSQuality] {
        let installed = Set(Self.deviceVoices().map(\.quality))
        var result: [TTSQuality] = [.standard]
        if installed.contains(.enhanced) { result.append(.enhanced) }
        if installed.contains(.premium) { result.append(.premium) }
        return result
    }

    func synthesize(lines: [SpokenLine], quality: TTSQuality, to url: URL) async throws -> Double {
        let spoken = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !spoken.isEmpty else { throw TTSError.nothingToSpeak }
        let (primary, secondary) = Self.voices(for: quality)

        var segments: [URL] = []
        defer { for segment in segments { try? FileManager.default.removeItem(at: segment) } }
        for line in spoken {
            let voice = line.role == .secondary ? secondary : primary
            let segment = try await writeUtterance(line.text, voice: voice)
            if FileManager.default.fileExists(atPath: segment.path) { segments.append(segment) }
        }
        guard !segments.isEmpty else { throw TTSError.synthesisFailed("no audio produced") }
        return try await compose(segments, to: url)
    }

    /// Renders one utterance to a temporary LinearPCM file.
    private func writeUtterance(_ text: String, voice: AVSpeechSynthesisVoice?) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        var file: AVAudioFile?
        return try await withCheckedThrowingContinuation { continuation in
            var done = false
            func finish(_ result: Result<URL, Error>) {
                guard !done else { return }
                done = true
                continuation.resume(with: result)
            }
            synth.write(utterance) { [synth] buffer in
                _ = synth // retain the synthesizer until synthesis completes
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    finish(.success(tmp)) // a zero-length buffer signals the end
                    return
                }
                do {
                    if file == nil {
                        file = try AVAudioFile(forWriting: tmp, settings: pcm.format.settings)
                    }
                    try file?.write(from: pcm)
                } catch {
                    finish(.failure(TTSError.synthesisFailed(error.localizedDescription)))
                }
            }
        }
    }

    /// Concatenates segment files end-to-end and exports one m4a.
    private func compose(_ segments: [URL], to url: URL) async throws -> Double {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw TTSError.exportFailed("no track") }

        var cursor = CMTime.zero
        for segment in segments {
            let asset = AVURLAsset(url: segment)
            guard let assetTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: assetTrack, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }

        try? FileManager.default.removeItem(at: url)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw TTSError.exportFailed("no export session")
        }
        do {
            try await export.export(to: url, as: .m4a)
        } catch {
            throw TTSError.exportFailed(error.localizedDescription)
        }
        return cursor.seconds
    }

    private static func deviceVoices() -> [AVSpeechSynthesisVoice] {
        let prefix = String(AVSpeechSynthesisVoice.currentLanguageCode().prefix(2))
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
    }

    /// Two distinct voices at (or below) the requested quality for the device
    /// language, so conversations sound like two speakers.
    private static func voices(for quality: TTSQuality) -> (AVSpeechSynthesisVoice?, AVSpeechSynthesisVoice?) {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let all = deviceVoices()
        func pick(excluding: AVSpeechSynthesisVoice?) -> AVSpeechSynthesisVoice? {
            let pool = all.filter { $0.identifier != excluding?.identifier }
            return pool.first { $0.quality == quality.avQuality }
                ?? pool.max { $0.quality.rawValue < $1.quality.rawValue }
                ?? AVSpeechSynthesisVoice(language: language)
        }
        let primary = pick(excluding: nil)
        let secondary = pick(excluding: primary) ?? primary
        return (primary, secondary)
    }
}

/// Deterministic stand-in for tests: writes a tiny placeholder file instantly
/// and reports a length proportional to the text.
nonisolated final class MockTTSService: TTSServicing {
    func availableQualities() async -> [TTSQuality] { [.standard, .enhanced] }

    func synthesize(lines: [SpokenLine], quality: TTSQuality, to url: URL) async throws -> Double {
        let text = lines.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TTSError.nothingToSpeak }
        try Data("mock-audio".utf8).write(to: url)
        return max(1, Double(text.count) * 0.06)
    }
}
