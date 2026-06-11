import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text (FR-32). `requiresOnDeviceRecognition` is
/// non-negotiable: audio and transcripts never leave the phone (PR-1).
actor SpeechVoiceService: VoiceServicing {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func availability() -> VoiceAvailability {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .permissionNotDetermined
        case .authorized: break
        @unknown default: return .unsupported
        }
        switch AVAudioApplication.shared.recordPermission {
        case .denied: return .denied
        case .undetermined: return .permissionNotDetermined
        case .granted: break
        @unknown default: return .unsupported
        }
        guard let recognizer = SFSpeechRecognizer(),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else { return .unsupported }
        return .available
    }

    func requestAuthorization() async -> VoiceAvailability {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return availability() }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else { return .denied }
        return availability()
    }

    func startTranscribing() throws -> AsyncThrowingStream<VoiceTranscript, Error> {
        guard availability() == .available else { throw VoiceError.notAuthorized }
        cleanup()

        guard let recognizer = SFSpeechRecognizer() else { throw VoiceError.recognitionFailed("no recognizer") }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceError.audioSessionFailed(error.localizedDescription)
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw VoiceError.audioSessionFailed(error.localizedDescription)
        }

        let (stream, continuation) = AsyncThrowingStream<VoiceTranscript, Error>.makeStream()
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                continuation.yield(result.isFinal ? .final(text) : .partial(text))
                if result.isFinal {
                    continuation.finish()
                }
            } else if error != nil {
                // End of audio without a final result (silence or stop):
                // callers keep the last partial they saw (FR-34).
                continuation.finish()
            }
        }

        audioEngine = engine
        recognitionRequest = request
        recognitionTask = task
        continuation.onTermination = { _ in
            Task { await self.stopTranscribing() }
        }
        return stream
    }

    func stopTranscribing() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        // endAudio lets the recognizer deliver its final result.
        recognitionRequest?.endAudio()
        audioEngine = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        stopTranscribing()
    }
}
