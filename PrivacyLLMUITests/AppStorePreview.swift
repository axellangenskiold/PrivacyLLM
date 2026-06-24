import Foundation
import XCTest

/// Drives one ~25s flow for an App Store *app preview* video. The simulator
/// screen is recorded externally (Scripts/preview.sh) while this runs; the test
/// only paces the on-screen action. Slow streaming makes the reasoning and reply
/// type out visibly, then the keyboard is dismissed to reveal the whole answer.
/// Gated like AppStoreScreenshots so it never runs in CI.
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
        if app.buttons["Continue"].exists { app.buttons["Continue"].tap() } // keyboard intro
        input.typeText("Is my data really private?")
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["Send message"].tap()

        // Dismiss the keyboard immediately and re-pin so the reasoning + reply
        // stream in full-screen and clean (the only keyboard moment is the brief
        // typing above, which the end-trim drops). Pinning keeps auto-follow on.
        let w = app.windows.firstMatch
        var tries = 0
        while app.keyboards.firstMatch.exists, tries < 4 {
            w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                .press(forDuration: 0.1, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)))
            tries += 1
        }
        let jump = app.buttons["Scroll to latest"]
        if jump.waitForExistence(timeout: 2) { jump.tap() }

        // Watch the whole reply stream in, then hold on the final answer.
        _ = app.staticTexts["Everything you type stays on this device."].waitForExistence(timeout: 45)
        Thread.sleep(forTimeInterval: 4.0)
    }
}
