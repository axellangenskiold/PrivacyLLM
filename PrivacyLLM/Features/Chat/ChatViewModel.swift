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
    private(set) var streamingText = ""
    private(set) var streamingReasoning = ""
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var activeRole: ModelRole = .fast
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
            settingsStore: environment.settingsStore
        )
    }

    var isBusy: Bool { phase != .idle }

    var canSend: Bool {
        phase == .idle && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadMessages() async {
        messages = (try? await environment.messageStore.fetchAll(conversationID: conversation.id)) ?? []
        activeRole = (try? await environment.settingsStore.value(for: .activeRole, default: ModelRole.fast)) ?? .fast
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
        errorMessage = nil
        phase = .generating
        Task {
            let stream = await orchestrator.send(text: text, conversation: conversation, history: messages)
            for await event in stream {
                handle(event)
            }
            if phase != .idle { phase = .idle }
        }
    }

    func stop() {
        Task { await orchestrator.cancel() }
    }

    func dismissError() {
        errorMessage = nil
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
            streamingText += piece
        case .assistantReasoningDelta(let piece):
            if phase != .generating { phase = .generating }
            streamingReasoning += piece
        case .assistantCompleted(let message):
            messages.append(message)
            streamingText = ""
            streamingReasoning = ""
            phase = .idle
        case .turnFailed(let reason, let partial):
            if let partial { messages.append(partial) }
            streamingText = ""
            streamingReasoning = ""
            errorMessage = reason
            phase = .idle
        }
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
