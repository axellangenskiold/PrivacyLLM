import XCTest

final class ChatFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSendMessageStreamsMarkdownReply() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mock-services", "--skip-onboarding"]
        app.launch()

        app.buttons["New Chat"].firstMatch.tap()

        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Hello from the UI test")
        app.buttons["Send message"].tap()

        // The mock model's canned reply renders this markdown heading (FR-1/FR-5).
        let heading = app.staticTexts["What works here"]
        XCTAssertTrue(heading.waitForExistence(timeout: 15))
    }

    @MainActor
    func testOnboardingAppearsOnFirstLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mock-services"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 5))
        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pick your model"].waitForExistence(timeout: 5))
    }
}
