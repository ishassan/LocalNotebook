import XCTest

@MainActor
final class LocalNotebookUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"]
        app.launch()
    }

    func testImportNotebook() {
        app.buttons["import-sample-notebook"].tap()
        XCTAssertTrue(app.otherElements["document-UITestNotebook"].waitForExistence(timeout: 5))
    }

    func testRunCell() {
        openSampleNotebook()
        app.buttons["run-all"].tap()
        XCTAssertTrue(app.otherElements["output-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UI Test Success"].waitForExistence(timeout: 5))
    }

    func testSaveAndReopen() {
        openSampleNotebook()
        app.buttons["run-all"].tap()
        app.buttons["save-document"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.otherElements["document-UITestNotebook"].tap()
        XCTAssertTrue(app.otherElements["output-text"].waitForExistence(timeout: 5))
    }

    func testClearOutputs() {
        openSampleNotebook()
        app.buttons["run-all"].tap()
        app.buttons["notebook-menu"].tap()
        app.buttons["Clear Outputs"].tap()
        XCTAssertFalse(app.otherElements["output-text"].waitForExistence(timeout: 2))
    }

    func testDuplicateNotebook() {
        openSampleNotebook()
        app.buttons["notebook-menu"].tap()
        app.buttons["Duplicate"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["document-UITestNotebook Copy"].waitForExistence(timeout: 5))
    }

    private func openSampleNotebook() {
        app.buttons["import-sample-notebook"].tap()
        app.otherElements["document-UITestNotebook"].tap()
    }
}
