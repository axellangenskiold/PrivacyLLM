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
    func testDonationPageOffersAmounts() throws {
        let app = launchApp()
        app.buttons["App menu"].tap()
        app.buttons["Settings"].tap()

        // The Support section sits below the fold and Form rows are realized
        // lazily, so scroll until it comes into existence.
        let support = app.staticTexts["Support PrivacyLLM"]
        var swipes = 0
        while !support.exists, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(support.waitForExistence(timeout: 5))
        support.tap()

        // Four ways to give, none required (OD-12: the app is free).
        XCTAssertTrue(app.buttons["Donate $1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Donate $2"].exists)
        XCTAssertTrue(app.buttons["Donate $3"].exists)
        XCTAssertTrue(app.buttons["Other amount…"].exists)
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
    func testDictationFillsInputWithoutSending() throws {
        let app = launchApp()
        app.buttons["New Chat"].firstMatch.tap()

        let mic = app.buttons["Dictate message"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        mic.tap()

        // Mock voice streams partials; stop and check the draft (FR-33/34).
        let stopDictation = app.buttons["Stop dictation"]
        XCTAssertTrue(stopDictation.waitForExistence(timeout: 5))
        let input = app.textFields["Message input"]
        let populated = NSPredicate(format: "value CONTAINS %@", "Hello")
        expectation(for: populated, evaluatedWith: input)
        waitForExpectations(timeout: 8)
        stopDictation.tap()

        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 5))
        // Nothing was auto-sent: no assistant bubble exists.
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
