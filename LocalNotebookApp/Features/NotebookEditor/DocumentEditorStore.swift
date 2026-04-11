import Foundation
import Observation
import UniformTypeIdentifiers
import UIKit

@MainActor
@Observable
final class DocumentEditorStore {
    let documentID: UUID
    private let appSession: AppSessionStore
    private let kernel: any KernelClient

    var snapshot: DocumentSnapshot?
    var notebook: NotebookDocument?
    var textContent: String = ""
    var isLoading = false
    var isSaving = false
    var renderedMarkdownCellIDs = Set<String>()
    var kernelState: KernelState = .idle {
        didSet { updateRunningSession() }
    }
    var statusMessage: String = "Idle"
    var errorMessage: String?
    private var lastDeletedCell: (cell: NotebookCell, index: Int)?

    init(documentID: UUID, appSession: AppSessionStore, kernel: (any KernelClient)? = nil) {
        self.documentID = documentID
        self.appSession = appSession
        if let kernel {
            self.kernel = kernel
        } else if UITestHarness.isEnabled {
            self.kernel = UITestKernelClient(sessionID: documentID)
        } else {
            self.kernel = LocalPythonKernel(sessionID: documentID)
        }
    }

    deinit {
        let documentID = documentID
        let appSession = appSession
        Task { @MainActor in
            appSession.removeSession(documentID: documentID)
        }
    }

    var kind: DocumentKind? {
        snapshot?.kind
    }

    var title: String {
        snapshot?.displayName ?? "Document"
    }

    var workingDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let opened = try await appSession.repository.openDocument(id: documentID)
            snapshot = opened.snapshot
            switch opened.content {
            case .notebook(let notebook):
                self.notebook = notebook
                renderedMarkdownCellIDs = Set(
                    notebook.cells
                        .filter { $0.cellType == .markdown }
                        .map(\.id)
                )
            case .text(let text):
                self.textContent = text
                renderedMarkdownCellIDs = []
            }
            updateRunningSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleAutosave() {
        guard appSession.settings.autosaveEnabled else { return }
        Task {
            await appSession.autosaveCoordinator.schedule(id: documentID) { [weak self] in
                guard let self else { return }
                await self.performAutosave()
            }
        }
    }

    func save() async {
        guard let snapshot else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            switch snapshot.kind {
            case .notebook:
                if let notebook {
                    try await appSession.repository.saveNotebook(notebook, for: snapshot.id)
                }
            case .python, .markdown, .text:
                try await appSession.repository.saveText(textContent, for: snapshot.id)
            }
            statusMessage = "Saved"
            await appSession.refresh()
            self.snapshot = appSession.documents.first(where: { $0.id == snapshot.id }) ?? self.snapshot
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(to newName: String) async {
        guard let snapshot else { return }
        do {
            self.snapshot = try await appSession.repository.renameDocument(id: snapshot.id, to: newName)
            await appSession.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate() async -> DocumentSnapshot? {
        guard let snapshot else { return nil }
        do {
            let result = try await appSession.repository.duplicateDocument(id: snapshot.id, clearOutputs: appSession.settings.clearOutputsOnDuplicate)
            await appSession.refresh()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteDocument() async -> Bool {
        guard let snapshot else { return false }

        let didDelete = await appSession.deleteDocuments(ids: Set([snapshot.id]))
        if !didDelete {
            errorMessage = appSession.lastError
        }
        return didDelete
    }

    func exportDocumentData() throws -> ExportFileDocument {
        guard let snapshot else {
            throw CocoaError(.fileNoSuchFile)
        }
        switch snapshot.kind {
        case .notebook:
            guard var notebook else { throw CocoaError(.fileReadUnknown) }
            if appSession.settings.clearOutputsOnExport {
                NotebookEditingReducer.clearOutputs(&notebook)
            }
            return try ExportFileDocument(data: NotebookCodec().encode(notebook), contentType: snapshot.kind.utType)
        case .python, .markdown, .text:
            return ExportFileDocument(data: Data(textContent.utf8), contentType: snapshot.kind.utType)
        }
    }

    func updateText(_ text: String) {
        textContent = text
        scheduleAutosave()
    }

    func updateCellSource(cellID: String, source: String) {
        guard let index = notebook?.cells.firstIndex(where: { $0.id == cellID }) else { return }
        notebook?.cells[index].source = .string(source)
        if notebook?.cells[index].cellType == .markdown {
            renderedMarkdownCellIDs.remove(cellID)
        }
        scheduleAutosave()
    }

    func setCellType(_ type: NotebookCellType, cellID: String) {
        guard let index = notebook?.cells.firstIndex(where: { $0.id == cellID }) else { return }
        if notebook?.cells[index].cellType == .code && type != .code {
            notebook?.cells[index].outputs = []
            notebook?.cells[index].executionCount = nil
        }
        notebook?.cells[index].cellType = type
        if type == .markdown {
            renderedMarkdownCellIDs.insert(cellID)
        } else {
            renderedMarkdownCellIDs.remove(cellID)
        }
        scheduleAutosave()
    }

    func addCell(type: NotebookCellType, after index: Int?) {
        guard var notebook else { return }
        NotebookEditingReducer.addCell(&notebook, type: type, after: index)
        self.notebook = notebook
        scheduleAutosave()
    }

    func insertCell(type: NotebookCellType, before cellID: String) {
        guard var notebook,
              let index = notebook.cells.firstIndex(where: { $0.id == cellID }) else { return }
        NotebookEditingReducer.insertCell(&notebook, type: type, at: index)
        self.notebook = notebook
        scheduleAutosave()
    }

    func insertCell(type: NotebookCellType, after cellID: String) {
        guard var notebook,
              let index = notebook.cells.firstIndex(where: { $0.id == cellID }) else { return }
        NotebookEditingReducer.insertCell(&notebook, type: type, at: index + 1)
        self.notebook = notebook
        scheduleAutosave()
    }

    func appendCell(type: NotebookCellType) {
        addCell(type: type, after: notebook?.cells.indices.last)
    }

    func deleteCell(_ cellID: String) {
        guard var notebook else { return }
        lastDeletedCell = NotebookEditingReducer.deleteCell(&notebook, id: cellID)
        self.notebook = notebook
        renderedMarkdownCellIDs.remove(cellID)
        scheduleAutosave()
    }

    func duplicateCell(_ cellID: String) {
        guard var notebook else { return }
        NotebookEditingReducer.duplicateCell(&notebook, id: cellID)
        self.notebook = notebook
        scheduleAutosave()
    }

    func clearOutputs() {
        guard var notebook else { return }
        NotebookEditingReducer.clearOutputs(&notebook)
        self.notebook = notebook
        scheduleAutosave()
    }

    func restartKernel() async {
        do {
            kernelState = .busy
            try await kernel.restart()
            if var notebook {
                NotebookEditingReducer.restartExecutionState(&notebook)
                self.notebook = notebook
            }
            kernelState = .idle
            statusMessage = "Kernel restarted"
        } catch {
            kernelState = .unavailable
            errorMessage = error.localizedDescription
        }
    }

    func interruptKernel() async {
        await kernel.interrupt()
        kernelState = .idle
        statusMessage = "Interrupt requested"
    }

    func runCell(_ cellID: String) async {
        guard let index = notebook?.cells.firstIndex(where: { $0.id == cellID }) else { return }
        if notebook?.cells[index].cellType == .markdown {
            renderedMarkdownCellIDs.insert(cellID)
            return
        }
        guard notebook?.cells[index].cellType == .code,
              let code = notebook?.cells[index].source.joined else { return }
        await execute(code: code) { [weak self] result in
            guard let self else { return }
            self.notebook?.cells[index].outputs = result.outputs
            self.notebook?.cells[index].executionCount = result.executionCount
            self.scheduleAutosave()
        }
    }

    func runAll() async {
        guard let cells = notebook?.cells else { return }
        for cell in cells where cell.cellType == .code || cell.cellType == .markdown {
            await runCell(cell.id)
        }
    }

    func runAbove(_ cellID: String) async {
        guard let index = notebook?.cells.firstIndex(where: { $0.id == cellID }) else { return }
        let cells = notebook?.cells.prefix(index) ?? []
        for cell in cells where cell.cellType == .code || cell.cellType == .markdown {
            await runCell(cell.id)
        }
    }

    func runAllBelow(_ cellID: String) async {
        guard let index = notebook?.cells.firstIndex(where: { $0.id == cellID }) else { return }
        let cells = notebook?.cells.suffix(from: index) ?? []
        for cell in cells where cell.cellType == .code || cell.cellType == .markdown {
            await runCell(cell.id)
        }
    }

    func runAndSelectNext(_ cellID: String) async -> String? {
        await runCell(cellID)
        return nextCellID(after: cellID)
    }

    func restartAndRunAll() async {
        await restartKernel()
        guard kernelState != .unavailable else { return }
        await runAll()
    }

    func moveCellUp(_ cellID: String) -> String? {
        moveCell(cellID, offset: -1)
    }

    func moveCellDown(_ cellID: String) -> String? {
        moveCell(cellID, offset: 1)
    }

    func mergeCellAbove(_ cellID: String) -> String? {
        guard var notebook,
              let index = notebook.cells.firstIndex(where: { $0.id == cellID }),
              notebook.cells.indices.contains(index - 1) else { return nil }
        let targetID = notebook.cells[index - 1].id
        NotebookEditingReducer.mergeCellWithPrevious(&notebook, id: cellID)
        self.notebook = notebook
        scheduleAutosave()
        return targetID
    }

    func mergeCellBelow(_ cellID: String) -> String? {
        guard var notebook else { return nil }
        NotebookEditingReducer.mergeCellWithNext(&notebook, id: cellID)
        self.notebook = notebook
        scheduleAutosave()
        return cellID
    }

    func undoDelete() -> String? {
        guard var notebook, let lastDeletedCell else { return nil }
        let safeIndex = max(0, min(lastDeletedCell.index, notebook.cells.count))
        notebook.cells.insert(lastDeletedCell.cell, at: safeIndex)
        self.notebook = notebook
        if lastDeletedCell.cell.cellType == .markdown {
            renderedMarkdownCellIDs.insert(lastDeletedCell.cell.id)
        }
        self.lastDeletedCell = nil
        scheduleAutosave()
        return lastDeletedCell.cell.id
    }

    func matchingCellIDs(for query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        return notebook?.cells.compactMap { cell in
            cell.source.joined.localizedCaseInsensitiveContains(query) ? cell.id : nil
        } ?? []
    }

    func replaceFirstMatch(of searchText: String, with replacementText: String, in cellID: String) {
        guard !searchText.isEmpty,
              let index = notebook?.cells.firstIndex(where: { $0.id == cellID }) else { return }
        let source = notebook?.cells[index].source.joined ?? ""
        guard let range = source.range(of: searchText, options: .caseInsensitive) else { return }
        updateCellSource(cellID: cellID, source: source.replacingCharacters(in: range, with: replacementText))
    }

    @discardableResult
    func replaceAllMatches(of searchText: String, with replacementText: String) -> Int {
        guard !searchText.isEmpty else { return 0 }
        var replacements = 0
        guard let cellIDs = notebook?.cells.map(\.id) else { return 0 }
        for cellID in cellIDs {
            guard let index = notebook?.cells.firstIndex(where: { $0.id == cellID }) else { continue }
            let source = notebook?.cells[index].source.joined ?? ""
            if source.localizedCaseInsensitiveContains(searchText) {
                let updated = source.replacingOccurrences(of: searchText, with: replacementText, options: .caseInsensitive)
                replacements += updated == source ? 0 : 1
                updateCellSource(cellID: cellID, source: updated)
            }
        }
        return replacements
    }

    func copyCell(_ cellID: String) {
        guard let cell = notebook?.cells.first(where: { $0.id == cellID }) else { return }
        guard let data = try? JSONEncoder().encode(CellClipboardPayload(cellType: cell.cellType, source: cell.source.joined)),
              let payload = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = Self.cellClipboardPrefix + payload
    }

    func cutCell(_ cellID: String) {
        copyCell(cellID)
        deleteCell(cellID)
    }

    func pasteCell(into cellID: String) -> String? {
        guard let pasted = UIPasteboard.general.string else { return nil }
        if pasted.hasPrefix(Self.cellClipboardPrefix) {
            let payloadString = String(pasted.dropFirst(Self.cellClipboardPrefix.count))
            guard let data = payloadString.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(CellClipboardPayload.self, from: data) else { return nil }
            setCellType(payload.cellType, cellID: cellID)
            updateCellSource(cellID: cellID, source: payload.source)
            return cellID
        }

        guard let index = notebook?.cells.firstIndex(where: { $0.id == cellID }) else { return nil }
        let existing = notebook?.cells[index].source.joined ?? ""
        let separator = existing.isEmpty ? "" : "\n"
        updateCellSource(cellID: cellID, source: existing + separator + pasted)
        return cellID
    }

    func previousCellID(before cellID: String) -> String? {
        guard let index = notebook?.cells.firstIndex(where: { $0.id == cellID }),
              index > 0 else { return nil }
        return notebook?.cells[index - 1].id
    }

    func nextCellID(after cellID: String) -> String? {
        guard let index = notebook?.cells.firstIndex(where: { $0.id == cellID }),
              let notebook,
              notebook.cells.indices.contains(index + 1) else { return nil }
        return notebook.cells[index + 1].id
    }

    func previewMarkdown(_ cellID: String) {
        renderedMarkdownCellIDs.insert(cellID)
    }

    func editMarkdown(_ cellID: String) {
        renderedMarkdownCellIDs.remove(cellID)
    }

    func runScript() async {
        await execute(code: textContent) { [weak self] result in
            self?.notebook = NotebookDocument(cells: [
                NotebookCell(cellType: .code, source: .string(self?.textContent ?? ""), executionCount: result.executionCount, outputs: result.outputs)
            ])
        }
    }

    private func execute(code: String, apply: @escaping @MainActor (KernelExecutionResult) -> Void) async {
        do {
            kernelState = .busy
            statusMessage = "Running"
            let result = try await kernel.execute(code: code, workingDirectory: workingDirectory)
            apply(result)
            kernelState = .idle
            statusMessage = "Idle"
        } catch {
            kernelState = .unavailable
            errorMessage = error.localizedDescription
            statusMessage = "Execution failed"
        }
    }

    private func updateRunningSession() {
        guard let snapshot else { return }
        appSession.registerSession(documentID: snapshot.id, title: snapshot.displayName, kind: snapshot.kind, state: kernelState)
    }

    private func performAutosave() async {
        guard let snapshot else { return }
        do {
            switch snapshot.kind {
            case .notebook:
                if let notebook {
                    try await appSession.repository.saveAutosave(notebook: notebook, for: snapshot.id)
                }
            case .python, .markdown, .text:
                try await appSession.repository.saveAutosave(text: textContent, for: snapshot.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveCell(_ cellID: String, offset: Int) -> String? {
        guard var notebook,
              let index = notebook.cells.firstIndex(where: { $0.id == cellID }) else { return nil }
        let destination = index + offset
        guard destination >= 0, destination <= notebook.cells.count - 1 else { return nil }
        NotebookEditingReducer.moveCell(&notebook, from: index, to: destination)
        self.notebook = notebook
        scheduleAutosave()
        return cellID
    }

    private static let cellClipboardPrefix = "localnotebook-cell:"
}

private struct CellClipboardPayload: Codable {
    let cellType: NotebookCellType
    let source: String
}
