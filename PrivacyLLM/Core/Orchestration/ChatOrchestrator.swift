import Foundation

nonisolated enum ChatTurnEvent: Sendable {
    case userMessageSaved(Message)
    case modelLoadProgress(Double)
    case assistantDelta(String)
    /// Live "thinking" output, rendered separately from the answer (UX-6).
    case assistantReasoningDelta(String)
    case toolStarted(name: String)
    case toolFinished(name: String, isError: Bool)
    case assistantCompleted(Message)
    /// Terminal failure. If tokens already streamed, the partial assistant
    /// message is persisted and attached so nothing the user saw is lost.
    case turnFailed(reason: String, partial: Message?)
}

/// Owns one conversation's turn lifecycle (§3.3): persists the user message,
/// resolves and loads the active model, builds the prompt, streams tokens
/// through the bounded agent loop, and persists the assistant reply.
/// Stop/cancel keeps the partial text (FR-2).
actor ChatOrchestrator {
    /// Max tool rounds per turn — the runaway-loop guard (TL-2).
    static let maxToolRounds = 3

    private let inference: any InferenceServicing
    private let modelManager: any ModelManaging
    private let messageStore: MessageStore
    private let conversationStore: ConversationStore
    private let settingsStore: SettingsStore
    private let documents: any DocumentServicing
    private let toolRouter: ToolRouter
    private let promptBuilder = PromptBuilder()
    private var turnTask: Task<Void, Never>?

    init(
        inference: any InferenceServicing,
        modelManager: any ModelManaging,
        messageStore: MessageStore,
        conversationStore: ConversationStore,
        settingsStore: SettingsStore,
        documents: any DocumentServicing = MockDocumentService(),
        tools: [any LocalTool] = [DateTimeTool(), CalculatorTool(), UnitConversionTool()]
    ) {
        self.inference = inference
        self.modelManager = modelManager
        self.messageStore = messageStore
        self.conversationStore = conversationStore
        self.settingsStore = settingsStore
        self.documents = documents
        self.toolRouter = ToolRouter(tools: tools, settingsStore: settingsStore)
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
        let basePrompt: String? = if let custom = conversation.systemPrompt, !custom.isEmpty {
            custom
        } else {
            (try? await settingsStore.globalSystemPrompt()) ?? nil
        }

        let searchEnabled = (try? await settingsStore.searchEnabled()) ?? false
        let toolSpecs = spec.capabilities.toolCalling
            ? toolRouter.specs(includeEgressTools: searchEnabled)
            : []

        // Document Q&A (§3.4): retrieve before generating and ride the
        // excerpts in the system prompt; short single docs go in whole.
        let queryText = fullHistory.last(where: { $0.role == .user })?.content ?? ""
        let docContext = await documentContext(for: queryText, conversationID: conversation.id)
        // Persona (custom/global) → behavior rules → document excerpts.
        let systemPrompt = [
            basePrompt,
            Self.coreGuidance(canSearch: toolSpecs.contains { $0.name == "web_search" }),
            docContext.block,
        ]
        .compactMap(\.self)
        .joined(separator: "\n\n")
        let inference = inference

        // Agent loop (TL-1/2): generate → run any tool calls → feed results
        // back as tool messages → resume, at most maxToolRounds times.
        var workingHistory = fullHistory
        var content = ""
        var reasoning = ""
        var collectedSources: [SourceAttribution] = docContext.sources
        var stats: GenerationStats?
        var failureReason: String?

        for round in 0...Self.maxToolRounds {
            var thinkParser = ThinkStreamParser()
            var toolParser = ToolCallParser()
            var roundRawAssistant = ""
            var roundCalls: [ParsedToolCall] = []

            func emitVisible(_ piece: String) {
                guard !piece.isEmpty else { return }
                content += piece
                continuation.yield(.assistantDelta(piece))
            }
            func processContent(_ piece: String) {
                guard !piece.isEmpty else { return }
                roundRawAssistant += piece
                let parsed = toolParser.feed(piece)
                emitVisible(parsed.visible)
                roundCalls += parsed.calls
            }
            func processToken(_ piece: String) {
                let thought = thinkParser.feed(piece)
                if !thought.reasoning.isEmpty {
                    reasoning += thought.reasoning
                    continuation.yield(.assistantReasoningDelta(thought.reasoning))
                }
                processContent(thought.content)
            }

            do {
                let input = await promptBuilder.build(
                    systemPrompt: systemPrompt,
                    history: workingHistory,
                    config: config,
                    tools: toolSpecs,
                    countTokens: { await inference.countTokens($0) }
                )
                let stream = await inference.generate(input, config: config)
                for try await event in stream {
                    switch event {
                    case .token(let piece):
                        processToken(piece)
                    case .toolCall(let call):
                        roundCalls.append(ParsedToolCall(call: call, rawBlock: Self.rawBlock(for: call)))
                    case .finished(let finalStats):
                        stats = finalStats
                    }
                }
            } catch {
                failureReason = String(localized: "Generation failed.")
                break
            }
            let thinkTail = thinkParser.finish()
            if !thinkTail.reasoning.isEmpty {
                reasoning += thinkTail.reasoning
                continuation.yield(.assistantReasoningDelta(thinkTail.reasoning))
            }
            processContent(thinkTail.content)
            let toolTail = toolParser.finish()
            emitVisible(toolTail.visible)
            roundCalls += toolTail.calls

            guard !roundCalls.isEmpty, round < Self.maxToolRounds else { break }

            // Tool exchange lives only in the working transcript, not the database.
            workingHistory.append(Message(
                conversationID: conversation.id,
                role: .assistant,
                content: roundRawAssistant
            ))
            for parsed in roundCalls {
                let name = parsed.call?.name ?? "invalid"
                continuation.yield(.toolStarted(name: name))
                let result = await toolRouter.execute(parsed)
                collectedSources += result.sources
                continuation.yield(.toolFinished(name: name, isError: result.isError))
                workingHistory.append(Message(
                    conversationID: conversation.id,
                    role: .tool,
                    content: result.content
                ))
            }
        }

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
            stats: stats,
            sources: collectedSources
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

    private static func rawBlock(for call: ToolCall) -> String {
        "<tool_call>{\"name\": \"\(call.name)\", \"arguments\": \(call.argumentsJSON)}</tool_call>"
    }

    /// Always-on behavior rules appended to the system prompt. Small on-device
    /// models don't infer *when* to reach for a tool from the schema listing
    /// alone, so when web_search is available this spells out the trigger cases
    /// (time-sensitive facts, uncertainty); when it isn't, the model is told to
    /// admit staleness instead of guessing. The current date anchors "recent".
    private static func coreGuidance(canSearch: Bool) -> String {
        let today = Date.now.formatted(date: .abbreviated, time: .omitted)
        if canSearch {
            return """
            Today is \(today).
            Use the web_search tool before answering when the question involves recent events or facts that change over time — news, sports results, scores, prices, weather, schedules, product releases, or anything "latest", "current", or after your training data — and whenever you are unsure of a fact. Search with 2-5 keywords (example: {"query": "brazil norway result"}), then answer using only the results and cite them. Never answer about current events from memory.
            Answer directly without searching for general knowledge, math, code, and questions about the user's attached documents.
            """
        }
        return """
        Today is \(today).
        You cannot access the web. If an answer may have changed since your training data, or you are unsure of a fact, say so plainly instead of guessing.
        """
    }

    /// Builds the document-context block for this turn (FR-27, §3.4).
    private func documentContext(
        for query: String,
        conversationID: UUID
    ) async -> (block: String?, sources: [SourceAttribution]) {
        guard let allDocs = try? await documents.documents() else { return (nil, []) }
        let visible = allDocs.filter { doc in
            guard doc.indexState == .ready else { return false }
            switch doc.scope {
            case .global: return true
            case .conversation(let id): return id == conversationID
            }
        }
        guard !visible.isEmpty, !query.isEmpty else { return (nil, []) }

        // A single short document fits whole — skip retrieval (§3.4).
        if visible.count == 1,
           let doc = visible.first,
           let fullText = (try? await documents.fullTextIfShort(documentID: doc.id, maxCharacters: 6000)) ?? nil {
            let block = """
            The user has attached the document "\(doc.title)". Its full text:

            \(fullText)

            Use it to answer when relevant, and cite the document by name.
            """
            return (block, [SourceAttribution(kind: .document, title: doc.title, documentID: doc.id)])
        }

        guard let retrieved = try? await documents.retrieve(query: query, conversationID: conversationID, topK: 4),
              !retrieved.isEmpty
        else { return (nil, []) }

        let excerpts = retrieved.map { item in
            let page = item.chunk.pageNumber.map { ", page \($0)" } ?? ""
            return "[\(item.documentTitle)\(page)]: \(item.chunk.text)"
        }
        .joined(separator: "\n\n")
        let block = """
        Relevant excerpts from the user's documents:

        \(excerpts)

        Answer using these excerpts when relevant, and cite the document name and page.
        """
        var seen = Set<String>()
        let sources = retrieved.compactMap { item -> SourceAttribution? in
            let key = "\(item.chunk.documentID)-\(item.chunk.pageNumber ?? 0)"
            guard seen.insert(key).inserted else { return nil }
            return SourceAttribution(
                kind: .document,
                title: item.documentTitle,
                documentID: item.chunk.documentID,
                pageNumber: item.chunk.pageNumber
            )
        }
        return (block, sources)
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
