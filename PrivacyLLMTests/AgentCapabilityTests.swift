import EventKit
import Foundation
import Testing
@testable import PrivacyLLM

struct UserMemoryTests {
    private func makeMemory() throws -> UserMemory {
        UserMemory(settingsStore: SettingsStore(database: try AppDatabase.inMemory()))
    }

    @Test func storesFactsAndBuildsAPromptBlock() async throws {
        let memory = try makeMemory()
        #expect(await memory.promptBlock() == nil)

        _ = await memory.remember("  Lives in Stockholm.  ")
        _ = await memory.remember("Writes Swift for a living.")

        let facts = await memory.facts()
        #expect(facts == ["Lives in Stockholm.", "Writes Swift for a living."])
        let block = await memory.promptBlock()
        #expect(block?.contains("- Lives in Stockholm.") == true)
    }

    @Test func replacesNearDuplicatesInsteadOfStacking() async throws {
        let memory = try makeMemory()
        _ = await memory.remember("Prefers espresso")
        _ = await memory.remember("The user prefers espresso")
        #expect(await memory.facts() == ["The user prefers espresso"])
    }

    @Test func capsCountAndLengthSoItStaysCheapInContext() async throws {
        let memory = try makeMemory()
        for index in 0..<(UserMemory.maxFacts + 5) {
            _ = await memory.remember("Fact number \(index) about something")
        }
        let facts = await memory.facts()
        #expect(facts.count == UserMemory.maxFacts)
        #expect(facts.first == "Fact number 5 about something")

        _ = await memory.remember(String(repeating: "x", count: 500))
        #expect(await memory.facts().allSatisfy { $0.count <= UserMemory.maxFactCharacters })
    }

    @Test func tooShortIsRejected() async throws {
        let memory = try makeMemory()
        #expect(await memory.remember("ok") == "")
        #expect(await memory.facts().isEmpty)
    }

    @Test func offMeansNothingIsInjected() async throws {
        let database = try AppDatabase.inMemory()
        let settings = SettingsStore(database: database)
        let memory = UserMemory(settingsStore: settings)
        _ = await memory.remember("Lives in Stockholm.")
        try await settings.set(false, for: .memoryEnabled)
        #expect(await memory.promptBlock() == nil)
    }
}

struct DeviceActionTests {
    @Test func parsesTheDateShapesASmallModelActuallyEmits() throws {
        let expected = DateComponents(year: 2026, month: 9, day: 5, hour: 14, minute: 30)
        for text in ["2026-09-05T14:30:00", "2026-09-05T14:30", "2026-09-05 14:30"] {
            let parsed = try #require(DeviceActionDates.parse(text))
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: parsed)
            #expect(components == expected, "failed for \(text)")
        }
        #expect(DeviceActionDates.parse("2026-09-05") != nil)
        #expect(DeviceActionDates.parse("next friday") == nil)
    }

    @Test func deviceToolsAreHiddenAndBlockedWhileTheSwitchIsOff() async throws {
        let database = try AppDatabase.inMemory()
        let settings = SettingsStore(database: database)
        let router = ToolRouter(
            tools: [DateTimeTool(), ReminderTool(store: EKEventStore())],
            settingsStore: settings
        )

        #expect(router.specs(includeEgressTools: false).map(\.name) == ["current_datetime"])
        let blocked = await router.execute(ParsedToolCall(
            call: ToolCall(name: "create_reminder", argumentsJSON: #"{"title":"Call the dentist"}"#),
            rawBlock: ""
        ))
        #expect(blocked.isError)
        #expect(blocked.content.contains("Device actions are switched off"))

        try await settings.set(true, for: .deviceActionsEnabled)
        #expect(router.specs(includeEgressTools: false, includeDeviceActions: true).count == 2)
    }

    @Test func phoneToolRefusesRubbishAndBuildsTheRightURL() async {
        var opened: URL?
        let tool = PhoneTool(open: { url in opened = url; return true })

        let bad = await tool.execute(argumentsJSON: #"{"number":"hi"}"#)
        #expect(bad.isError)

        _ = await tool.execute(argumentsJSON: #"{"number":"+46 70 123 45 67"}"#)
        #expect(opened?.absoluteString == "tel://+46701234567")

        _ = await tool.execute(argumentsJSON: #"{"number":"0701234567","message":"on my way"}"#)
        #expect(opened?.scheme == "sms")
        #expect(opened?.absoluteString.contains("body=") == true)
    }
}

struct FeedbackTests {
    @Test func asksEveryFifthLaunchAndOnlyFourTimes() async throws {
        let prompt = FeedbackPrompt(settingsStore: SettingsStore(database: try AppDatabase.inMemory()))
        var asked: [Int] = []
        for launch in 1...40 where await prompt.registerLaunchAndShouldAsk() {
            asked.append(launch)
        }
        #expect(asked == [5, 10, 15, 20])
    }

    @Test func sendingFeedbackStopsTheAsking() async throws {
        let prompt = FeedbackPrompt(settingsStore: SettingsStore(database: try AppDatabase.inMemory()))
        for _ in 1...4 { _ = await prompt.registerLaunchAndShouldAsk() }
        await prompt.silence()
        var asked = false
        for _ in 5...30 where await prompt.registerLaunchAndShouldAsk() { asked = true }
        #expect(!asked)
    }

    private func query(_ url: URL) throws -> [String: String] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func buildsAPrefilledIssueURL() throws {
        let url = try #require(FeedbackView.issueURL(body: "Please add an iPad layout & widgets"))
        #expect(url.host() == "github.com")
        #expect(url.path().hasSuffix("/issues/new"))
        let items = try query(url)
        #expect(items["body"]?.hasPrefix("Please add an iPad layout & widgets") == true)
        #expect(items["labels"] == "feedback")
        #expect(FeedbackView.issueURL(body: "   ") == nil)
    }

    @Test func buildsAPrefilledMailURLToTheSupportAddress() throws {
        let url = try #require(FeedbackView.mailURL(body: "Dark mode is too dark\nespecially the code blocks"))
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.contains(FeedbackView.supportEmail))
        let items = try query(url)
        // Subject is the first line only, so an inbox stays scannable.
        #expect(items["subject"] == "PrivacyLLM: Dark mode is too dark")
        #expect(items["body"]?.contains("especially the code blocks") == true)
        #expect(FeedbackView.mailURL(body: " \n ") == nil)
    }

    @Test func bothDestinationsCarryTheVersionAndNothingElse() throws {
        for destination in FeedbackDestination.allCases {
            let url = try #require(FeedbackView.url(for: destination, body: "hello"))
            let body = try #require(try query(url)["body"])
            #expect(body.hasPrefix("hello"))
            #expect(body.contains("PrivacyLLM"))
        }
        #expect(FeedbackView.emailHost == "langenskiold.se")
    }
}

struct ClearContextTests {
    /// The orchestrator should send only what comes after the clear mark, while
    /// the transcript itself is untouched (FR-48).
    @Test func clearedMessagesAreHiddenFromTheModelButKeptOnDisk() async throws {
        let database = try AppDatabase.inMemory()
        let inference = MockInferenceService(tokenDelay: .milliseconds(1), scriptedReply: "ok")
        var conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)
        let messageStore = MessageStore(database: database)
        let orchestrator = ChatOrchestrator(
            inference: inference,
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            messageStore: messageStore,
            conversationStore: ConversationStore(database: database),
            settingsStore: SettingsStore(database: database)
        )

        let old = Message(
            conversationID: conversation.id,
            role: .user,
            content: "forget me",
            createdAt: .now.addingTimeInterval(-60)
        )
        try await messageStore.append(old)
        conversation.contextClearedAt = .now.addingTimeInterval(-30)

        for await _ in await orchestrator.send(
            text: "remember me",
            conversation: conversation,
            history: [old]
        ) {}

        let sent = try #require(await inference.lastInput)
        let userTurns = sent.messages.filter { $0.role == .user }.map(\.content)
        #expect(userTurns == ["remember me"])
        // Still on disk: clearing context is not deleting the chat.
        #expect(try await messageStore.fetchAll(conversationID: conversation.id).contains { $0.content == "forget me" })
    }

    @Test func withoutAClearMarkTheWholeHistoryGoes() async throws {
        let database = try AppDatabase.inMemory()
        let inference = MockInferenceService(tokenDelay: .milliseconds(1), scriptedReply: "ok")
        let conversation = Conversation()
        try await ConversationStore(database: database).insert(conversation)
        let messageStore = MessageStore(database: database)
        let orchestrator = ChatOrchestrator(
            inference: inference,
            modelManager: MockModelManager(downloadedModelIDs: [ModelSpec.previewFast.id]),
            messageStore: messageStore,
            conversationStore: ConversationStore(database: database),
            settingsStore: SettingsStore(database: database)
        )
        let old = Message(
            conversationID: conversation.id,
            role: .user,
            content: "keep me",
            createdAt: .now.addingTimeInterval(-60)
        )
        try await messageStore.append(old)

        for await _ in await orchestrator.send(text: "and me", conversation: conversation, history: [old]) {}

        let sent = try #require(await inference.lastInput)
        #expect(sent.messages.filter { $0.role == .user }.map(\.content) == ["keep me", "and me"])
    }
}
