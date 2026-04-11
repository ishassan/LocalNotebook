import XCTest

@MainActor
final class LocalNotebookUITests: XCTestCase {
    private let appBundleID = "com.ishassan.localnotebook"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: appBundleID)
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"]
        app.launch()
        if app.buttons["Browse"].waitForExistence(timeout: 2) {
            app.buttons["Browse"].tap()
        } else if app.buttons["Files"].waitForExistence(timeout: 2) {
            app.buttons["Files"].tap()
        }
    }

    func testImportNotebook() {
        app.buttons["import-sample-notebook"].tap()
        XCTAssertTrue(documentRow(named: "UITestNotebook").waitForExistence(timeout: 5))
    }

    func testRunCell() {
        openSampleNotebook()
        app.buttons["run-all"].tap()
        XCTAssertTrue(renderedOutput().waitForExistence(timeout: 15))
    }

    func testSaveAndReopen() {
        openSampleNotebook()
        app.buttons["run-all"].tap()
        app.buttons["save-document"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = documentRow(named: "UITestNotebook")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(renderedOutput().waitForExistence(timeout: 15))
    }

    func testClearOutputs() {
        openSampleNotebook()
        app.buttons["run-all"].tap()
        app.buttons["notebook-menu"].tap()
        app.buttons["Clear Outputs"].tap()
        XCTAssertFalse(renderedOutput().waitForExistence(timeout: 2))
    }

    func testDuplicateNotebook() {
        openSampleNotebook()
        app.buttons["notebook-menu"].tap()
        app.buttons["Duplicate"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(documentRow(named: "UITestNotebook Copy").waitForExistence(timeout: 5))
    }

    private func openSampleNotebook() {
        app.buttons["import-sample-notebook"].tap()
        documentRow(named: "UITestNotebook").tap()
    }

    private func documentRow(named name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "document-\(name)").firstMatch
    }

    private func renderedOutput() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "output-text").firstMatch
    }
}
