import Foundation

nonisolated enum ChatTurnEvent: Sendable {
    case userMessageSaved(Message)
    case modelLoadProgress(Double)
    case assistantDelta(String)
    /// Live "thinking" output, rendered separately from the answer (UX-6).
    case assistantReasoningDelta(String)
    case assistantCompleted(Message)
    /// Terminal failure. If tokens already streamed, the partial assistant
    /// message is persisted and attached so nothing the user saw is lost.
    case turnFailed(reason: String, partial: Message?)
}

/// Owns one conversation's turn lifecycle (§3.3): persists the user message,
/// resolves and loads the active model, builds the prompt, streams tokens,
/// and persists the assistant reply. Stop/cancel keeps the partial text (FR-2).
actor ChatOrchestrator {
    private let inference: any InferenceServicing
    private let modelManager: any ModelManaging
    private let messageStore: MessageStore
    private let conversationStore: ConversationStore
    private let settingsStore: SettingsStore
    private let promptBuilder = PromptBuilder()
    private var turnTask: Task<Void, Never>?

    init(
        inference: any InferenceServicing,
        modelManager: any ModelManaging,
        messageStore: MessageStore,
        conversationStore: ConversationStore,
        settingsStore: SettingsStore
    ) {
        self.inference = inference
        self.modelManager = modelManager
        self.messageStore = messageStore
        self.conversationStore = conversationStore
        self.settingsStore = settingsStore
    }

    func send(text: String, conversation: Conversation, history: [Message]) -> AsyncStream<ChatTurnEvent> {
        run(newUserText: text, conversation: conversation, history: history)
    }

    /// Re-runs generation for a history that already ends with the user
    /// message — regenerate (FR-3) and edit-and-rerun (FR-4).
    func regenerate(conversation: Conversation, history: [Message]) -> AsyncStream<ChatTurnEvent> {
        run(newUserText: nil, conversation: conversation, history: history)
    }

    private func run(newUserText: String?, conversation: Conversation, history: [Message]) -> AsyncStream<ChatTurnEvent> {
        let (stream, continuation) = AsyncStream<ChatTurnEvent>.makeStream()
        let task = Task {
            await runTurn(newUserText: newUserText, conversation: conversation, history: history, continuation: continuation)
            continuation.finish()
        }
        turnTask = task
        return stream
    }

    /// Stops generation immediately; the in-flight turn persists what streamed so far.
    func cancel() async {
        await inference.cancelGeneration()
    }

    private func runTurn(
        newUserText: String?,
        conversation: Conversation,
        history: [Message],
        continuation: AsyncStream<ChatTurnEvent>.Continuation
    ) async {
        var fullHistory = history
        if let newUserText {
            let trimmed = newUserText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let userMessage = Message(conversationID: conversation.id, role: .user, content: trimmed)
            do {
                try await messageStore.append(userMessage)
            } catch {
                continuation.yield(.turnFailed(reason: String(localized: "Couldn't save your message."), partial: nil))
                return
            }
            continuation.yield(.userMessageSaved(userMessage))
            fullHistory.append(userMessage)
        } else {
            guard fullHistory.last?.role == .user else {
                continuation.yield(.turnFailed(reason: String(localized: "Nothing to regenerate."), partial: nil))
                return
            }
        }

        guard let (spec, directory) = await resolveActiveModel() else {
            continuation.yield(.turnFailed(
                reason: String(localized: "No model is downloaded yet. Add one in the model manager."),
                partial: nil
            ))
            return
        }

        do {
            let loaded = await inference.loadedModel
            if loaded?.id != spec.id {
                try await inference.loadModel(spec: spec, directory: directory) { progress in
                    continuation.yield(.modelLoadProgress(progress))
                }
            }
        } catch {
            continuation.yield(.turnFailed(reason: String(localized: "The model failed to load."), partial: nil))
            return
        }

        let config = await generationConfig()
        let systemPrompt: String? = if let custom = conversation.systemPrompt, !custom.isEmpty {
            custom
        } else {
            (try? await settingsStore.globalSystemPrompt()) ?? nil
        }
        let inference = inference
        let input = await promptBuilder.build(
            systemPrompt: systemPrompt,
            history: fullHistory,
            config: config,
            countTokens: { await inference.countTokens($0) }
        )

        var parser = ThinkStreamParser()
        var content = ""
        var reasoning = ""
        var stats: GenerationStats?
        var failureReason: String?

        func emit(_ parsed: (reasoning: String, content: String)) {
            if !parsed.reasoning.isEmpty {
                reasoning += parsed.reasoning
                continuation.yield(.assistantReasoningDelta(parsed.reasoning))
            }
            if !parsed.content.isEmpty {
                content += parsed.content
                continuation.yield(.assistantDelta(parsed.content))
            }
        }

        do {
            let stream = await inference.generate(input, config: config)
            for try await event in stream {
                switch event {
                case .token(let piece):
                    emit(parser.feed(piece))
                case .finished(let finalStats):
                    stats = finalStats
                }
            }
        } catch {
            failureReason = String(localized: "Generation failed.")
        }
        emit(parser.finish())

        guard !content.isEmpty || !reasoning.isEmpty else {
            continuation.yield(.turnFailed(
                reason: failureReason ?? String(localized: "The model produced no output."),
                partial: nil
            ))
            return
        }

        let trimmedReasoning = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantMessage = Message(
            conversationID: conversation.id,
            role: .assistant,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            reasoning: trimmedReasoning.isEmpty ? nil : trimmedReasoning,
            modelID: spec.id,
            stats: stats
        )
        do {
            try await messageStore.append(assistantMessage)
        } catch {
            continuation.yield(.turnFailed(reason: String(localized: "Couldn't save the reply."), partial: nil))
            return
        }

        if let failureReason {
            continuation.yield(.turnFailed(reason: failureReason, partial: assistantMessage))
        } else {
            continuation.yield(.assistantCompleted(assistantMessage))
        }
    }

    private func resolveActiveModel() async -> (ModelSpec, URL)? {
        let role = (try? await settingsStore.value(for: .activeRole, default: ModelRole.fast)) ?? .fast
        let preferred = await modelManager.activeModelID(for: role)
        let fallback = await modelManager.activeModelID(for: .fast)
        guard let modelID = preferred ?? fallback,
              let spec = modelManager.catalog.first(where: { $0.id == modelID }),
              let directory = await modelManager.localDirectory(for: modelID)
        else { return nil }
        return (spec, directory)
    }

    private func generationConfig() async -> GenerationConfig {
        let sampling = (try? await settingsStore.sampling()) ?? SamplingParams()
        let contextLength = (try? await settingsStore.contextLength()) ?? 4096
        let role = (try? await settingsStore.value(for: .activeRole, default: ModelRole.fast)) ?? .fast
        return GenerationConfig(
            sampling: sampling,
            contextLength: contextLength,
            thinkingEnabled: role == .thinking
        )
    }
}
