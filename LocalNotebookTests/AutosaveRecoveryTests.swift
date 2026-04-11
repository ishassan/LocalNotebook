import XCTest
@testable import LocalNotebook

final class AutosaveRecoveryTests: XCTestCase {
    func testAutosaveIsPreferredOnReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = DocumentRepository(rootURL: root)
        let snapshot = try await repository.createNotebook(named: "Autosave Demo")

        var notebook = NotebookDocument.empty(named: "Autosave Demo")
        notebook.cells[1].source = .string("print('saved')")
        try await repository.saveNotebook(notebook, for: snapshot.id)

        notebook.cells[1].source = .string("print('autosaved')")
        try await repository.saveAutosave(notebook: notebook, for: snapshot.id)

        let reopened = try await repository.openDocument(id: snapshot.id)
        guard case .notebook(let reopenedNotebook) = reopened.content else {
            XCTFail("Expected notebook content.")
            return
        }

        XCTAssertEqual(reopenedNotebook.cells[1].source.joined, "print('autosaved')")
    }
}
