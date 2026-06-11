import Foundation
import Observation

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

    func loadMessages() async {
        messages = (try? await environment.messageStore.fetchAll(conversationID: conversation.id)) ?? []
        activeRole = (try? await environment.settingsStore.value(for: .activeRole, default: ModelRole.fast)) ?? .fast
        searchEnabled = (try? await environment.settingsStore.searchEnabled()) ?? false
    }

    /// Flips the global search opt-in (FR-18); takes effect on the next turn.
    func setSearchEnabled(_ enabled: Bool) {
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
        let conversationID = conversation.id
        Task {
            do {
                let meta = try await service.importPDF(at: url, scope: .conversation(conversationID))
                attachmentNotice = String(localized: "“\(meta.title)” attached — ask away.")
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
    private var dictationBase = ""

    func toggleRecording() {
        if isRecording {
            let voice = environment.voice
            Task { await voice.stopTranscribing() }
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !isRecording, phase == .idle else { return }
        voicePermissionDenied = false
        Task {
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

            // Dictation appends to whatever was already typed (FR-34).
            dictationBase = draft.isEmpty ? "" : draft + " "
            isRecording = true
            do {
                let stream = try await environment.voice.startTranscribing()
                for try await transcript in stream {
                    switch transcript {
                    case .partial(let text), .final(let text):
                        draft = dictationBase + text
                    }
                }
            } catch {
                errorMessage = String(localized: "Dictation failed. Try again.")
            }
            isRecording = false
        }
    }

    func dismissVoicePermissionHelp() {
        voicePermissionDenied = false
    }

    /// One-tap Fast/Thinking switch (FR-15); the next turn loads the new role's model.
    func setActiveRole(_ role: ModelRole) {
        guard role != activeRole else { return }
        activeRole = role
        let settings = environment.settingsStore
        Task { try? await settings.set(role, for: .activeRole) }
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
        case .turnFailed(let reason, let partial):
            if let partial { messages.append(partial) }
            clearStreamingState()
            errorMessage = reason
            phase = .idle
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
