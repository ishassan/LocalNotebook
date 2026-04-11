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

    func testRunAllRendersMarkdownCells() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = DocumentRepository(rootURL: root)
        let snapshot = try await repository.createNotebook(named: "Markdown")

        let notebook = NotebookDocument(
            cells: [
                NotebookCell(id: "m1", cellType: .markdown, source: .string("# Title")),
                NotebookCell(id: "c1", cellType: .code, source: .string("print('ok')"))
            ]
        )
        try await repository.saveNotebook(notebook, for: snapshot.id)

        let appSession = await MainActor.run { AppSessionStore(repository: repository) }
        let kernel = MockKernelClient(sessionID: snapshot.id)
        let store = await MainActor.run { DocumentEditorStore(documentID: snapshot.id, appSession: appSession, kernel: kernel) }
        await store.load()
        await store.runAll()

        let renderedIDs = await MainActor.run { store.renderedMarkdownCellIDs }
        XCTAssertTrue(renderedIDs.contains("m1"))
    }

    func testLoadRendersMarkdownCellsWithoutExecutingCode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = DocumentRepository(rootURL: root)
        let snapshot = try await repository.createNotebook(named: "Open Notebook")

        let notebook = NotebookDocument(
            cells: [
                NotebookCell(id: "m1", cellType: .markdown, source: .string("# Title")),
                NotebookCell(id: "c1", cellType: .code, source: .string("print('do not run')"))
            ]
        )
        try await repository.saveNotebook(notebook, for: snapshot.id)

        let appSession = await MainActor.run { AppSessionStore(repository: repository) }
        let kernel = MockKernelClient(sessionID: snapshot.id)
        let store = await MainActor.run { DocumentEditorStore(documentID: snapshot.id, appSession: appSession, kernel: kernel) }
        await store.load()

        let renderedIDs = await MainActor.run { store.renderedMarkdownCellIDs }
        let executionCount = await kernel.executionCount()
        XCTAssertTrue(renderedIDs.contains("m1"))
        XCTAssertEqual(executionCount, 0)
    }

    func testImportDocumentCanSelectFilesTabAndOpenImportedNotebook() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = DocumentRepository(rootURL: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let externalURL = root.appendingPathComponent("External.ipynb")
        try """
        {
          "cells": [],
          "metadata": {},
          "nbformat": 4,
          "nbformat_minor": 5
        }
        """.write(to: externalURL, atomically: true, encoding: .utf8)

        let appSession = await MainActor.run { AppSessionStore(repository: repository) }
        await MainActor.run {
            appSession.settings.openImportedFilesAsCopy = true
        }
        let snapshot = await appSession.importDocument(from: externalURL, openAfterImport: true)

        let selectedTab = await MainActor.run { appSession.selectedTab }
        let path = await MainActor.run { appSession.filesNavigationPath }

        XCTAssertEqual(selectedTab, 0)
        XCTAssertEqual(path, [snapshot?.id].compactMap { $0 })
    }

    func testChangingCellTypeToMarkdownClearsOutputsAndRendersPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = DocumentRepository(rootURL: root)
        let snapshot = try await repository.createNotebook(named: "Retype")

        let notebook = NotebookDocument(
            cells: [
                NotebookCell(
                    id: "c1",
                    cellType: .code,
                    source: .string("# title"),
                    executionCount: 1,
                    outputs: [NotebookOutput(outputType: "display_data", data: ["text/plain": .string("old")])]
                )
            ]
        )
        try await repository.saveNotebook(notebook, for: snapshot.id)

        let appSession = await MainActor.run { AppSessionStore(repository: repository) }
        let kernel = MockKernelClient(sessionID: snapshot.id)
        let store = await MainActor.run { DocumentEditorStore(documentID: snapshot.id, appSession: appSession, kernel: kernel) }
        await store.load()
        await MainActor.run {
            store.setCellType(.markdown, cellID: "c1")
        }

        let cell = await MainActor.run { store.notebook?.cells.first }
        let renderedIDs = await MainActor.run { store.renderedMarkdownCellIDs }

        XCTAssertEqual(cell?.cellType, .markdown)
        XCTAssertNil(cell?.executionCount)
        XCTAssertEqual(cell?.outputs, [])
        XCTAssertTrue(renderedIDs.contains("c1"))
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

    func executionCount() -> Int {
        count
    }
}
