import XCTest
@testable import LocalNotebook

final class ExecutionSessionTests: XCTestCase {
    func testDocumentEditorUsesKernelAbstractionAndPersistsStateAcrossCells() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = DocumentRepository(rootURL: root)
        let snapshot = try await repository.createNotebook(named: "Execution")

        let notebook = NotebookDocument(
            cells: [
                NotebookCell(id: "a", cellType: .code, source: .string("x = 2")),
                NotebookCell(id: "b", cellType: .code, source: .string("x + 3"))
            ]
        )
        try await repository.saveNotebook(notebook, for: snapshot.id)

        let appSession = await MainActor.run { AppSessionStore(repository: repository) }
        let kernel = MockKernelClient(sessionID: snapshot.id)
        let store = await MainActor.run { DocumentEditorStore(documentID: snapshot.id, appSession: appSession, kernel: kernel) }
        await store.load()
        await store.runCell("a")
        await store.runCell("b")

        let outputs = await MainActor.run { store.notebook?.cells[1].outputs ?? [] }
        XCTAssertEqual(outputs.first?.data["text/plain"], .string("5"))
    }
}

private actor MockKernelClient: KernelClient {
    let sessionID: UUID
    private var variables: [String: Int] = [:]
    private var count = 0

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func execute(code: String, workingDirectory: URL?) async throws -> KernelExecutionResult {
        count += 1
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("=") {
            let parts = trimmed.components(separatedBy: "=")
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            variables[name] = value
            return KernelExecutionResult(executionCount: count, outputs: [])
        }
        if trimmed.contains("+") {
            let parts = trimmed.components(separatedBy: "+")
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let rhs = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            let value = (variables[name] ?? 0) + rhs
            return KernelExecutionResult(
                executionCount: count,
                outputs: [
                    NotebookOutput(outputType: "display_data", data: ["text/plain": .string(String(value))])
                ]
            )
        }
        return KernelExecutionResult(executionCount: count, outputs: [])
    }

    func restart() async throws {
        variables = [:]
    }

    func interrupt() async {}
}
