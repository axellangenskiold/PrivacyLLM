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
