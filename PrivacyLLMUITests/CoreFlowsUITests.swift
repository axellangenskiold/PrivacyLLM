import XCTest

/// TR-11/12/13 core flows on the all-mock environment.
final class CoreFlowsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mock-services", "--skip-onboarding"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    func testStopGenerationReturnsToIdle() throws {
        // Slow streaming keeps generation in flight long enough that the stop
        // affordance is reliably observable, even on a loaded machine.
        let app = launchApp(extraArguments: ["--mock-slow-stream"])
        app.buttons["New Chat"].firstMatch.tap()

        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Tell me something long")
        app.buttons["Send message"].tap()

        let stop = app.buttons["Stop generating"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        if stop.exists {
            stop.tap()
        }

        // FR-2: generation halts — the stop affordance leaves promptly and
        // the input stays usable.
        XCTAssertTrue(stop.waitForNonExistence(timeout: 10))
        XCTAssertTrue(input.isHittable)
    }

    @MainActor
    func testScrollingUpStopsAutoFollowAndJumpButtonReturns() throws {
        let app = launchApp()
        app.buttons["New Chat"].firstMatch.tap()
        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))

        // Build up enough content to scroll, then stream a third reply.
        for index in 0..<3 {
            input.tap()
            input.typeText("Message number \(index)")
            app.buttons["Send message"].tap()
            if index < 2 {
                XCTAssertTrue(app.buttons["Dictate message"].waitForExistence(timeout: 15))
            }
        }

        // Scroll towards older content with raw drags (element-independent;
        // a finger moving down reveals earlier messages).
        let window = app.windows.firstMatch
        for _ in 0..<2 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        }

        // Auto-follow disengaged: the jump affordance appears and tapping it
        // re-pins to the live tail (the fix for the streaming-scroll bug).
        let jump = app.buttons["Scroll to latest"]
        let appeared = jump.waitForExistence(timeout: 5)
        if !appeared {
            add(XCTAttachment(screenshot: app.screenshot()))
        }
        XCTAssertTrue(appeared)
        jump.tap()
        XCTAssertTrue(jump.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testFastThinkingToggleSticks() throws {
        let app = launchApp()
        app.buttons["New Chat"].firstMatch.tap()

        // PVSegmentedPill is an accessibility container, not a native segmented control.
        let mode = app.otherElements["Model mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.buttons["Thinking"].tap()
        XCTAssertTrue(mode.buttons["Thinking"].isSelected)
    }

    @MainActor
    func testChatModelPickerListsDownloadedModels() throws {
        let app = launchApp()
        app.buttons["New Chat"].firstMatch.tap()

        let picker = app.buttons["Choose model"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        // The mock environment pre-downloads only the fast model; it's offered
        // (and already selected) for the current role.
        let model = app.buttons["Mock Fast 1B"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.tap()
        XCTAssertTrue(app.textFields["Message input"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDonationsHiddenWhenDisabled() throws {
        // Force the donations flag off (independent of the shipped default) and
        // confirm the menu offers no Donate entry — the gate works.
        let app = launchApp(extraArguments: ["--no-feature-donations"])
        app.buttons["App menu"].tap()
        // Settings being present confirms the menu actually opened, so the
        // absence of Donate below is meaningful.
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Donate"].exists)
    }

    @MainActor
    func testDonationPageOffersAmounts() throws {
        // Force the flag on so the page is covered regardless of the shipped
        // default.
        let app = launchApp(extraArguments: ["--feature-donations"])
        app.buttons["App menu"].tap()
        let donate = app.buttons["Donate"]
        XCTAssertTrue(donate.waitForExistence(timeout: 5))
        donate.tap()

        // Exactly three tiers ($1 / $3 / $5), none required (OD-12: the app is
        // free). Queried by identifier because the visible labels are App Store
        // prices. There is no "other amount" affordance.
        XCTAssertTrue(app.buttons["donate-tier-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["donate-tier-1"].exists)
        XCTAssertTrue(app.buttons["donate-tier-2"].exists)
        XCTAssertFalse(app.buttons["donate-other"].exists)
    }

    @MainActor
    func testSearchToggleFlipsState() throws {
        let app = launchApp()
        app.buttons["New Chat"].firstMatch.tap()

        let off = app.buttons["Web search off"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.tap()
        XCTAssertTrue(app.buttons["Web search on"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDictationOffersTranscriptForReviewWithoutSending() throws {
        let app = launchApp()
        app.buttons["New Chat"].firstMatch.tap()

        let mic = app.buttons["Dictate message"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        mic.tap()

        // Recording UI replaces the input field; end it (a pause in speech would
        // auto-stop too). Mock voice yields a final transcript on stop.
        let finish = app.buttons["Finish dictation"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        // FR-34: the transcript is offered for review with a Send button, not
        // auto-sent — no assistant reply exists yet.
        XCTAssertTrue(app.buttons["Send recorded message"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["What works here"].exists)
    }

    @MainActor
    func testModelManagerListsCatalogAndStates() throws {
        let app = launchApp()
        app.buttons["App menu"].tap()
        app.buttons["Models"].tap()

        XCTAssertTrue(app.staticTexts["Mock Fast 1B"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mock Thinking 4B"].exists)
        // The mock environment pre-downloads the fast model: its options menu exists.
        XCTAssertTrue(app.buttons["Downloaded. Model options"].firstMatch.exists)
    }

    @MainActor
    func testModelManagerSortAndImportMenu() throws {
        let app = launchApp()
        app.buttons["App menu"].tap()
        app.buttons["Models"].tap()
        XCTAssertTrue(app.staticTexts["Mock Fast 1B"].waitForExistence(timeout: 5))

        // The toolbar menu exposes both the sort options and the import affordance.
        app.buttons["Sort and import models"].tap()
        XCTAssertTrue(app.buttons["Import Model…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["RAM required"].exists)
        XCTAssertTrue(app.buttons["Newest"].exists)

        // Choosing a sort order keeps the catalog on screen (no crash, list re-renders).
        app.buttons["RAM required"].tap()
        XCTAssertTrue(app.staticTexts["Mock Thinking 4B"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsPrivacySurface() throws {
        let app = launchApp()
        app.buttons["App menu"].tap()
        app.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["What leaves this device"].waitForExistence(timeout: 5))
        app.staticTexts["What leaves this device"].tap()
        XCTAssertTrue(app.staticTexts["The only network activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Model downloads"].exists)
    }

    @MainActor
    func testDocumentsEmptyState() throws {
        let app = launchApp()
        app.buttons["App menu"].tap()
        app.buttons["Documents"].tap()

        XCTAssertTrue(app.staticTexts["No documents"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Import PDF"].firstMatch.exists)
    }

    @MainActor
    func testVoiceMemoGenerationFlow() throws {
        let app = launchApp()
        // Entry point sits next to New Chat on the main screen.
        app.buttons["Voice Memos"].firstMatch.tap()

        // Open the composer, type text, and generate (mock TTS is instant).
        app.buttons["New Voice Memo"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Hello world memo")
        app.buttons["Generate"].tap()

        // The generated memo lands in the library with a play control.
        XCTAssertTrue(app.staticTexts["Hello world memo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Play"].firstMatch.exists)
    }

    @MainActor
    func testSessionInfoSheetShowsContext() throws {
        let app = launchApp()
        app.buttons["New Chat"].firstMatch.tap()
        XCTAssertTrue(app.textFields["Message input"].waitForExistence(timeout: 5))

        app.buttons["Conversation options"].tap()
        app.buttons["Session Info"].tap()

        // The sheet surfaces the context window and cumulative token counts.
        XCTAssertTrue(app.staticTexts["Context used"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tokens generated"].exists)
    }

    @MainActor
    func testChatSurvivesHugeDynamicType() throws {
        let app = launchApp(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
        ])
        app.buttons["New Chat"].firstMatch.tap()
        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.isHittable)
    }
}
