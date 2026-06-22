import XCTest

/// Drives one ~20s flow for an App Store *app preview* video. The simulator
/// screen is recorded externally (Scripts/preview.sh) while this runs; the test
/// only paces the on-screen action. Slow streaming makes the reasoning and reply
/// type out visibly. Gated like AppStoreScreenshots so it never runs in CI.
final class AppStorePreview: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["APPSTORE_SHOTS"] == "1",
            "Set TEST_RUNNER_APPSTORE_SHOTS=1 to record the App Store preview."
        )
    }

    @MainActor
    func test01Preview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mock-services", "--skip-onboarding", "--mock-slow-stream"]
        app.launch()

        app.buttons["New Chat"].firstMatch.tap()

        // Thinking mode so the reasoning disclosure streams alongside the reply.
        let mode = app.otherElements["Model mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.buttons["Thinking"].tap()

        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Is this really private — and can you think it through?")
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Send message"].tap()

        // Watch the reasoning + reply stream in (slow stream keeps it visible).
        _ = app.staticTexts["What works here"].waitForExistence(timeout: 40)
        Thread.sleep(forTimeInterval: 3.0)
    }
}
