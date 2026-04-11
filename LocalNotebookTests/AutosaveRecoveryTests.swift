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

    func testDeleteRemovesStoredFilesAndAutosaves() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = DocumentRepository(rootURL: root)

        defer {
            try? fileManager.removeItem(at: root)
        }

        let snapshot = try await repository.createTextDocument(named: "Delete Me", kind: .python)
        try await repository.saveAutosave(text: "print('autosave')", for: snapshot.id)

        let localDocumentURL = root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(snapshot.relativePath)
        let autosaveURL = root
            .appendingPathComponent("Autosaves", isDirectory: true)
            .appendingPathComponent(snapshot.relativePath)

        XCTAssertTrue(fileManager.fileExists(atPath: localDocumentURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: autosaveURL.path))

        try await repository.deleteDocuments(ids: [snapshot.id])
        let remainingDocuments = try await repository.listDocuments()

        XCTAssertFalse(fileManager.fileExists(atPath: localDocumentURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: autosaveURL.path))
        XCTAssertTrue(remainingDocuments.isEmpty)
    }
}
