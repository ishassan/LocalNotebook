import Foundation

enum NotebookEditingReducer {
    static func addCell(_ notebook: inout NotebookDocument, type: NotebookCellType, after index: Int?) {
        if let index {
            insertCell(&notebook, type: type, at: index + 1)
        } else {
            insertCell(&notebook, type: type, at: notebook.cells.count)
        }
    }

    static func insertCell(_ notebook: inout NotebookDocument, type: NotebookCellType, at index: Int) {
        let cell = NotebookCell(cellType: type)
        let safeIndex = max(0, min(index, notebook.cells.count))
        notebook.cells.insert(cell, at: safeIndex)
    }

    static func deleteCell(_ notebook: inout NotebookDocument, id: String) {
        notebook.cells.removeAll { $0.id == id }
    }

    static func duplicateCell(_ notebook: inout NotebookDocument, id: String) {
        guard let index = notebook.cells.firstIndex(where: { $0.id == id }) else { return }
        var copy = notebook.cells[index]
        copy = NotebookCell(
            cellType: copy.cellType,
            source: copy.source,
            metadata: copy.metadata,
            attachments: copy.attachments,
            executionCount: nil,
            outputs: copy.outputs,
            additionalFields: copy.additionalFields
        )
        notebook.cells.insert(copy, at: index + 1)
    }

    static func moveCell(_ notebook: inout NotebookDocument, from source: Int, to destination: Int) {
        guard notebook.cells.indices.contains(source), notebook.cells.indices.contains(max(0, min(destination, notebook.cells.count - 1))) else { return }
        let cell = notebook.cells.remove(at: source)
        notebook.cells.insert(cell, at: destination)
    }

    static func clearOutputs(_ notebook: inout NotebookDocument) {
        notebook.cells.indices.forEach { index in
            guard notebook.cells[index].cellType == .code else { return }
            notebook.cells[index].outputs = []
            notebook.cells[index].executionCount = nil
        }
    }

    static func restartExecutionState(_ notebook: inout NotebookDocument) {
        clearOutputs(&notebook)
    }

    static func splitCell(_ notebook: inout NotebookDocument, id: String, at offset: Int) {
        guard let index = notebook.cells.firstIndex(where: { $0.id == id }) else { return }
        let full = notebook.cells[index].source.joined
        let safeOffset = max(0, min(offset, full.count))
        let splitIndex = full.index(full.startIndex, offsetBy: safeOffset)
        let head = String(full[..<splitIndex])
        let tail = String(full[splitIndex...])
        notebook.cells[index].source = .string(head)
        let newCell = NotebookCell(cellType: notebook.cells[index].cellType, source: .string(tail))
        notebook.cells.insert(newCell, at: index + 1)
    }

    static func mergeCellWithNext(_ notebook: inout NotebookDocument, id: String) {
        guard let index = notebook.cells.firstIndex(where: { $0.id == id }),
              notebook.cells.indices.contains(index + 1) else { return }
        notebook.cells[index].source = .string(notebook.cells[index].source.joined + notebook.cells[index + 1].source.joined)
        notebook.cells.remove(at: index + 1)
    }
}
