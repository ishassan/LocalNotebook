import Foundation
import Observation
import UniformTypeIdentifiers

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
        NotebookEditingReducer.deleteCell(&notebook, id: cellID)
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
}
