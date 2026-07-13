import Foundation
import Observation
import UIKit

/// Snapshot shown in the Session Info sheet (FR-24): the model's context window
/// with live usage, plus cumulative token and web-search counts.
nonisolated struct SessionStats: Sendable, Equatable {
    var modelName: String
    var contextWindow: Int
    var contextUsed: Int
    var promptTokensTotal: Int
    var completionTokensTotal: Int
    var webSearchCount: Int
    var lastTokensPerSecond: Double?

    var usageFraction: Double {
        contextWindow > 0 ? min(1, Double(contextUsed) / Double(contextWindow)) : 0
    }

    /// True once the conversation no longer fits: older turns are automatically
    /// dropped from the model's context to keep replies accurate (autocompact).
    var isCompacting: Bool { contextWindow > 0 && contextUsed >= contextWindow }
}

@Observable
final class ChatViewModel {
    enum Phase: Equatable {
        case idle
        case loadingModel(Double)
        case generating
    }

    private(set) var conversation: Conversation
    private(set) var messages: [Message] = []
    struct ToolActivity: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var isRunning: Bool
        var isError: Bool
    }

    private(set) var streamingText = ""
    private(set) var streamingReasoning = ""
    private(set) var toolActivity: [ToolActivity] = []
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var activeRole: ModelRole = .fast
    private(set) var searchEnabled = false
    private(set) var downloadedModels: [ModelSpec] = []
    private(set) var activeModelID: String?
    var draft = ""

    private let environment: AppEnvironment
    private let orchestrator: ChatOrchestrator

    init(conversation: Conversation, environment: AppEnvironment) {
        self.conversation = conversation
        self.environment = environment
        self.orchestrator = ChatOrchestrator(
            inference: environment.inference,
            modelManager: environment.modelManager,
            messageStore: environment.messageStore,
            conversationStore: environment.conversationStore,
            settingsStore: environment.settingsStore,
            tools: environment.chatTools
        )
    }

    var isBusy: Bool { phase != .idle }

    var canSend: Bool {
        phase == .idle && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True once preferences reflect either stored values or a user action;
    /// guards against a late load clobbering a fast user toggle.
    private var preferencesResolved = false

    func loadMessages() async {
        messages = (try? await environment.messageStore.fetchAll(conversationID: conversation.id)) ?? []
        if !preferencesResolved {
            activeRole = (try? await environment.settingsStore.value(for: .activeRole, default: ModelRole.fast)) ?? .fast
            searchEnabled = (try? await environment.settingsStore.searchEnabled()) ?? false
            preferencesResolved = true
        }
        await refreshModelOptions()
    }

    /// Downloaded models offered by the chat toolbar picker, plus which one the
    /// current role resolves to. Selection applies on the next turn (FR-15).
    func refreshModelOptions() async {
        let manager = environment.modelManager
        let states = await manager.states()
        downloadedModels = states.filter { $0.phase == .downloaded }.map(\.spec)
        activeModelID = await manager.activeModelID(for: activeRole)
    }

    func setActiveModel(_ id: String) {
        guard id != activeModelID else { return }
        activeModelID = id
        let manager = environment.modelManager
        let role = activeRole
        Task { await manager.setActiveModel(id, for: role) }
    }

    /// Flips the global search opt-in (FR-18); takes effect on the next turn.
    func setSearchEnabled(_ enabled: Bool) {
        preferencesResolved = true
        guard enabled != searchEnabled else { return }
        searchEnabled = enabled
        let settings = environment.settingsStore
        Task { try? await settings.set(enabled, for: .searchEnabled) }
    }

    // MARK: Document attachment (OD-6: per-conversation scope)

    private(set) var isIndexingAttachment = false
    private(set) var attachmentNotice: String?

    func attachDocument(at url: URL) {
        guard !isIndexingAttachment else { return }
        isIndexingAttachment = true
        attachmentNotice = nil
        let service = environment.documents
        let store = environment.messageStore
        let conversationID = conversation.id
        Task {
            do {
                let meta = try await service.importPDF(at: url, scope: .conversation(conversationID))
                // The attachment joins the transcript as a persisted message;
                // PromptBuilder keeps it away from the model.
                let message = Message(
                    conversationID: conversationID,
                    role: .attachment,
                    content: meta.title,
                    sources: [SourceAttribution(kind: .document, title: meta.title, documentID: meta.id)]
                )
                try await store.append(message)
                messages.append(message)
            } catch {
                attachmentNotice = DocumentsViewModel.message(for: error)
            }
            isIndexingAttachment = false
        }
    }

    func dismissAttachmentNotice() {
        attachmentNotice = nil
    }

    // MARK: Voice input (FR-32...35)

    private(set) var isRecording = false
    private(set) var voicePermissionDenied = false
    /// Live transcript shown in place of the text field while recording.
    private(set) var liveTranscript = ""
    /// Captured transcript awaiting the user's review-then-send (FR-34); nil
    /// unless a recording just finished with speech in it.
    private(set) var pendingVoiceTranscript: String?
    /// Pause in speech after which dictation auto-stops (FR-33). Overridable in tests.
    var silenceTimeout: Duration = .seconds(2)

    private var dictationBase = ""
    private var recordingCancelled = false
    private var silenceTask: Task<Void, Never>?

    func startVoiceRecording() {
        guard !isRecording, phase == .idle else { return }
        voicePermissionDenied = false
        pendingVoiceTranscript = nil
        recordingCancelled = false
        // Dictation continues whatever was already typed (FR-34).
        dictationBase = draft.isEmpty ? "" : draft + " "
        draft = ""
        Task { await runRecording() }
    }

    private func runRecording() async {
        let availability = await environment.voice.requestAuthorization()
        switch availability {
        case .available:
            break
        case .denied, .restricted:
            voicePermissionDenied = true
            return
        case .permissionNotDetermined:
            return
        case .unsupported:
            errorMessage = String(localized: "On-device dictation isn't available on this device or language.")
            return
        }

        isRecording = true
        liveTranscript = dictationBase
        do {
            let stream = try await environment.voice.startTranscribing()
            for try await transcript in stream {
                switch transcript {
                case .partial(let text), .final(let text):
                    liveTranscript = dictationBase + text
                    armSilenceTimer()
                }
            }
        } catch {
            errorMessage = String(localized: "Dictation failed. Try again.")
        }
        silenceTask?.cancel()
        isRecording = false
        finalizeRecording()
    }

    /// Restarts the "no speech" countdown; fires once speech pauses (FR-33).
    private func armSilenceTimer() {
        silenceTask?.cancel()
        let timeout = silenceTimeout
        silenceTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.finishVoiceRecording()
        }
    }

    /// Ends capture and keeps the transcript for review (silence auto-stop, or
    /// the user tapping done).
    func finishVoiceRecording() {
        guard isRecording else { return }
        silenceTask?.cancel()
        let voice = environment.voice
        Task { await voice.stopTranscribing() }
    }

    /// Discards an in-progress recording without keeping the transcript.
    func cancelVoiceRecording() {
        guard isRecording else { return }
        recordingCancelled = true
        silenceTask?.cancel()
        let voice = environment.voice
        Task { await voice.stopTranscribing() }
    }

    private func finalizeRecording() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscript = ""
        guard !recordingCancelled, !text.isEmpty else {
            // Cancelled or silent: restore whatever had been typed before.
            recordingCancelled = false
            draft = dictationBase.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        pendingVoiceTranscript = text
    }

    /// Commits the reviewed transcript and sends it (FR-34).
    func sendVoiceTranscript() {
        guard let text = pendingVoiceTranscript else { return }
        pendingVoiceTranscript = nil
        draft = text
        send()
    }

    /// Moves the transcript into the editable field instead of sending it.
    func editVoiceTranscript() {
        guard let text = pendingVoiceTranscript else { return }
        pendingVoiceTranscript = nil
        draft = text
    }

    /// Throws away the reviewed transcript without sending.
    func discardVoiceTranscript() {
        pendingVoiceTranscript = nil
        draft = ""
    }

    func dismissVoicePermissionHelp() {
        voicePermissionDenied = false
    }

    // MARK: Session info (FR-24)

    /// Snapshot for the Session Info sheet: the active model's context window +
    /// live usage, and cumulative token / web-search counts for this chat.
    func sessionStats() async -> SessionStats {
        let spec = downloadedModels.first { $0.id == activeModelID }
        let userCap = (try? await environment.settingsStore.contextLength()) ?? 0
        let window = spec?.resolvedContextLength(userCap: userCap) ?? (userCap > 0 ? userCap : 4096)

        var prompt = 0, completion = 0, searches = 0
        var lastTPS: Double?
        for message in messages where message.role == .assistant {
            prompt += message.stats?.promptTokens ?? 0
            completion += message.stats?.completionTokens ?? 0
            searches += message.stats?.webSearchCount ?? 0
            if let tps = message.stats?.tokensPerSecond { lastTPS = tps }
        }
        return SessionStats(
            modelName: spec?.displayName ?? String(localized: "No model"),
            contextWindow: window,
            contextUsed: await currentContextTokens(),
            promptTokensTotal: prompt,
            completionTokensTotal: completion,
            webSearchCount: searches,
            lastTokensPerSecond: lastTPS
        )
    }

    /// Approximate tokens the current conversation occupies — the live context
    /// fill. Uses the loaded model's tokenizer when available, else chars/token.
    private func currentContextTokens() async -> Int {
        let inference = environment.inference
        func count(_ text: String) async -> Int {
            if let exact = await inference.countTokens(text) { return exact }
            return max(1, text.count / 4)
        }
        var total = 0
        if let persona = conversation.systemPrompt, !persona.isEmpty {
            total += await count(persona)
        }
        for message in messages where message.role != .attachment {
            total += await count(message.content)
        }
        return total
    }

    /// One-tap Fast/Thinking switch (FR-15); the next turn loads the new role's model.
    func setActiveRole(_ role: ModelRole) {
        preferencesResolved = true
        guard role != activeRole else { return }
        activeRole = role
        let settings = environment.settingsStore
        let manager = environment.modelManager
        Task {
            try? await settings.set(role, for: .activeRole)
            activeModelID = await manager.activeModelID(for: role)
        }
    }

    func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        runTurn { [orchestrator, conversation, messages] in
            await orchestrator.send(text: text, conversation: conversation, history: messages)
        }
    }

    /// Replaces the last assistant reply with a fresh generation (FR-3).
    func regenerate() {
        guard phase == .idle, let last = messages.last, last.role == .assistant else { return }
        messages.removeLast()
        let store = environment.messageStore
        runTurn { [orchestrator, conversation, messages] in
            try? await store.delete([last.id])
            return await orchestrator.regenerate(conversation: conversation, history: messages)
        }
    }

    /// Rewrites a user message and re-runs the conversation from that point,
    /// discarding everything after it (FR-4).
    func editAndRerun(_ message: Message, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .idle, message.role == .user, !trimmed.isEmpty else { return }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages = Array(messages[..<index])
        }
        let store = environment.messageStore
        runTurn { [orchestrator, conversation, messages] in
            try? await store.deleteFrom(message)
            return await orchestrator.send(text: trimmed, conversation: conversation, history: messages)
        }
    }

    private func runTurn(_ makeStream: @escaping () async -> AsyncStream<ChatTurnEvent>) {
        errorMessage = nil
        phase = .generating
        Task {
            let stream = await makeStream()
            for await event in stream {
                handle(event)
            }
            flushStreamBuffers()
            if phase != .idle { phase = .idle }
        }
    }

    func stop() {
        Task { await orchestrator.cancel() }
    }

    func dismissError() {
        errorMessage = nil
    }

    func exportMarkdown() -> String {
        ConversationExporter.markdown(conversation: conversation, messages: messages)
    }

    func exportPlainText() -> String {
        ConversationExporter.plainText(conversation: conversation, messages: messages)
    }

    /// Per-conversation persona override (FR-8); empty reverts to the global default.
    func updateSystemPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.systemPrompt = trimmed.isEmpty ? nil : trimmed
        conversation.updatedAt = .now
        let updated = conversation
        let store = environment.conversationStore
        Task { try? await store.update(updated) }
    }

    private func handle(_ event: ChatTurnEvent) {
        switch event {
        case .userMessageSaved(let message):
            messages.append(message)
            autoTitleIfNeeded(from: message.content)
        case .modelLoadProgress(let progress):
            phase = .loadingModel(progress)
        case .assistantDelta(let piece):
            if phase != .generating { phase = .generating }
            pendingText += piece
            scheduleStreamFlush()
        case .assistantReasoningDelta(let piece):
            if phase != .generating { phase = .generating }
            pendingReasoning += piece
            scheduleStreamFlush()
        case .toolStarted(let name):
            toolActivity.append(ToolActivity(name: name, isRunning: true, isError: false))
        case .toolFinished(let name, let isError):
            if let index = toolActivity.lastIndex(where: { $0.name == name && $0.isRunning }) {
                toolActivity[index].isRunning = false
                toolActivity[index].isError = isError
            }
        case .assistantCompleted(let message):
            messages.append(message)
            clearStreamingState()
            phase = .idle
            Haptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Reply finished"))
        case .turnFailed(let reason, let partial):
            if let partial { messages.append(partial) }
            clearStreamingState()
            errorMessage = reason
            phase = .idle
            Haptics.error()
        }
    }

    // MARK: Streaming throttle

    // Re-rendering markdown on every token is wasteful (NFR-3); deltas are
    // batched and flushed to the UI a few times per frame-budget instead.
    private var pendingText = ""
    private var pendingReasoning = ""
    private var flushScheduled = false

    private func scheduleStreamFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            flushScheduled = false
            flushStreamBuffers()
        }
    }

    private func flushStreamBuffers() {
        if !pendingText.isEmpty {
            streamingText += pendingText
            pendingText = ""
        }
        if !pendingReasoning.isEmpty {
            streamingReasoning += pendingReasoning
            pendingReasoning = ""
        }
    }

    private func clearStreamingState() {
        pendingText = ""
        pendingReasoning = ""
        streamingText = ""
        streamingReasoning = ""
        toolActivity = []
    }

    /// First user message names the conversation (FR-6 quality-of-life).
    private func autoTitleIfNeeded(from text: String) {
        guard messages.count == 1 else { return }
        let title = String(text.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        conversation.title = title
        conversation.updatedAt = .now
        let updated = conversation
        Task { try? await environment.conversationStore.update(updated) }
    }
}
