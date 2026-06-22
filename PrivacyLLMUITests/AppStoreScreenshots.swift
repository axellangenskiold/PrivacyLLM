import XCTest

/// App Store screenshot capture, driving the all-mock environment to its most
/// photogenic states. Skipped unless `APPSTORE_SHOTS=1` reaches the test runner
/// (pass `TEST_RUNNER_APPSTORE_SHOTS=1` to xcodebuild), so it never runs in CI.
///
/// Appearance (dark/light) is set on the simulator before the run — the app
/// follows the system appearance — and the run must be non-parallel so the shots
/// inherit it. See Scripts/screenshots.sh, which orchestrates both passes and
/// extracts the PNGs. Methods are numbered so the captured order is stable.
final class AppStoreScreenshots: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["APPSTORE_SHOTS"] == "1",
            "Set TEST_RUNNER_APPSTORE_SHOTS=1 to capture App Store screenshots."
        )
    }

    private func launch(_ extra: [String] = ["--skip-onboarding"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mock-services"] + extra
        app.launch()
        return app
    }

    /// Full-screen device-resolution capture, kept in the result bundle.
    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Last line of the mock reply — its presence means the reply finished rendering.
    private let replyDone = "Everything you type stays on this device."

    /// iOS shows a one-time "Type in two languages" intro over the keyboard the
    /// first time it appears; clear it so it never lands in a shot.
    private func clearKeyboardIntro(_ app: XCUIApplication) {
        let cont = app.buttons["Continue"]
        if cont.exists { cont.tap() }
    }

    /// Drag the transcript down. ChatView dismisses the keyboard on an interactive
    /// scroll (.scrollDismissesKeyboard), and repeated drags reach the top.
    private func dragDown(_ app: XCUIApplication) {
        let w = app.windows.firstMatch
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)))
    }

    /// Re-pin to the live tail so no jump-to-bottom affordance lingers.
    private func pinToBottom(_ app: XCUIApplication) {
        let jump = app.buttons["Scroll to latest"]
        if jump.waitForExistence(timeout: 2) { jump.tap() }
    }

    @MainActor
    func test01Onboarding() throws {
        // No --skip-onboarding: land on the privacy-promise page.
        let app = launch([])
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 10))
        snap("01-onboarding")
    }

    @MainActor
    func test02Chat() throws {
        let app = launch()
        app.buttons["New Chat"].firstMatch.tap()
        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("How do you keep my data private?")
        app.buttons["Send message"].tap()
        // Canned reply finished rendering once its markdown heading is on screen.
        XCTAssertTrue(app.staticTexts["What works here"].waitForExistence(timeout: 20))
        snap("02-chat")
    }

    @MainActor
    func test03Thinking() throws {
        let app = launch()
        app.buttons["New Chat"].firstMatch.tap()
        let mode = app.otherElements["Model mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.buttons["Thinking"].tap()

        let input = app.textFields["Message input"]
        input.tap()
        input.typeText("Plan a focused week for me.")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["What works here"].waitForExistence(timeout: 20))

        // The persisted reply keeps a collapsed reasoning disclosure — expand it
        // so the on-device reasoning is the star of the shot.
        let reasoning = app.buttons["reasoning"]
        if reasoning.waitForExistence(timeout: 5) {
            reasoning.tap()
        }
        snap("03-thinking")
    }

    @MainActor
    func test04Search() throws {
        let app = launch()
        app.buttons["New Chat"].firstMatch.tap()
        let off = app.buttons["Web search off"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.tap()
        XCTAssertTrue(app.buttons["Web search on"].waitForExistence(timeout: 5))

        let input = app.textFields["Message input"]
        input.tap()
        input.typeText("What's new in on-device AI this week?")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["What works here"].waitForExistence(timeout: 20))
        snap("04-search")
    }

    @MainActor
    func test05Privacy() throws {
        let app = launch()
        app.buttons["App menu"].tap()
        app.buttons["Settings"].tap()
        let row = app.staticTexts["What leaves this device"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["The only network activity"].waitForExistence(timeout: 5))
        snap("05-privacy")
    }
}
