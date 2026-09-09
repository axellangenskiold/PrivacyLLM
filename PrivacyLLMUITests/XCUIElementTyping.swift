import XCTest

extension XCUIElement {
    /// Taps a text field and waits for the keyboard to actually take focus
    /// before typing.
    ///
    /// `tap()` returns as soon as the event is dispatched, not when the field
    /// is ready. On a loaded CI runner — where a single app launch can take
    /// 24 seconds — the keystrokes arrive first and XCTest fails the test with
    /// "Failed to synthesize event: Neither element nor any descendant has
    /// keyboard focus". Locally it never reproduces, because nothing is ever
    /// slow enough.
    func tapAndType(_ text: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        tap()
        if !waitForKeyboardFocus(timeout: timeout) {
            // One retry: the first tap can land while the view is still
            // settling, in which case it never reaches the field at all.
            tap()
            XCTAssertTrue(
                waitForKeyboardFocus(timeout: timeout),
                "\(self) never took keyboard focus",
                file: file,
                line: line
            )
        }
        typeText(text)
    }

    private func waitForKeyboardFocus(timeout: TimeInterval) -> Bool {
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: self
        )
        return XCTWaiter().wait(for: [focused], timeout: timeout) == .completed
    }
}
