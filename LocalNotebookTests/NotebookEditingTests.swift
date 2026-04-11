import XCTest
@testable import LocalNotebook

final class NotebookEditingTests: XCTestCase {
    func testSplitMergeAndClearOutputs() {
        var notebook = NotebookDocument(
            cells: [
                NotebookCell(
                    id: "cell_1",
                    cellType: .code,
                    source: .string("print('hello')"),
                    executionCount: 1,
                    outputs: [NotebookOutput(outputType: "stream", name: "stdout", text: .string("hello\n"))]
                )
            ]
        )

        NotebookEditingReducer.splitCell(&notebook, id: "cell_1", at: 5)
        XCTAssertEqual(notebook.cells.count, 2)

        NotebookEditingReducer.mergeCellWithNext(&notebook, id: "cell_1")
        XCTAssertEqual(notebook.cells.count, 1)

        NotebookEditingReducer.clearOutputs(&notebook)
        XCTAssertTrue(notebook.cells[0].outputs.isEmpty)
        XCTAssertNil(notebook.cells[0].executionCount)
    }

    func testDuplicateCellGetsNewIdentity() {
        var notebook = NotebookDocument(cells: [NotebookCell(id: "cell_1", cellType: .markdown, source: .string("A"))])
        NotebookEditingReducer.duplicateCell(&notebook, id: "cell_1")

        XCTAssertEqual(notebook.cells.count, 2)
        XCTAssertNotEqual(notebook.cells[0].id, notebook.cells[1].id)
    }

    func testInsertCellCanPlaceCellsBeforeAndAfterExistingCell() {
        var notebook = NotebookDocument(
            cells: [
                NotebookCell(id: "first", cellType: .markdown, source: .string("A")),
                NotebookCell(id: "second", cellType: .code, source: .string("B"))
            ]
        )

        NotebookEditingReducer.insertCell(&notebook, type: .code, at: 0)
        NotebookEditingReducer.insertCell(&notebook, type: .markdown, at: 2)

        XCTAssertEqual(notebook.cells.count, 4)
        XCTAssertEqual(notebook.cells[0].cellType, .code)
        XCTAssertEqual(notebook.cells[1].id, "first")
        XCTAssertEqual(notebook.cells[2].cellType, .markdown)
        XCTAssertEqual(notebook.cells[3].id, "second")
    }

    func testDeleteMoveAndMergeOperationsKeepExpectedOrder() {
        var notebook = NotebookDocument(
            cells: [
                NotebookCell(id: "first", cellType: .markdown, source: .string("Alpha")),
                NotebookCell(id: "second", cellType: .markdown, source: .string("Beta")),
                NotebookCell(id: "third", cellType: .code, source: .string("print('gamma')"))
            ]
        )

        let deleted = NotebookEditingReducer.deleteCell(&notebook, id: "second")
        XCTAssertEqual(deleted?.cell.id, "second")
        XCTAssertEqual(deleted?.index, 1)
        XCTAssertEqual(notebook.cells.map(\.id), ["first", "third"])

        NotebookEditingReducer.moveCell(&notebook, from: 1, to: 0)
        XCTAssertEqual(notebook.cells.map(\.id), ["third", "first"])

        NotebookEditingReducer.insertCell(&notebook, type: .markdown, at: 2)
        notebook.cells[2].source = .string("Delta")
        NotebookEditingReducer.mergeCellWithPrevious(&notebook, id: notebook.cells[2].id)

        XCTAssertEqual(notebook.cells.count, 2)
        XCTAssertEqual(notebook.cells[1].source.joined, "Alpha\nDelta")
    }
}
