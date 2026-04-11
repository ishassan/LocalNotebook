import Foundation

protocol DocumentRepositoryProtocol: Sendable {
    func listDocuments() async throws -> [DocumentSnapshot]
    func createNotebook(named: String) async throws -> DocumentSnapshot
    func createTextDocument(named: String, kind: DocumentKind) async throws -> DocumentSnapshot
    func importDocument(from externalURL: URL, strategy: ImportStrategy) async throws -> DocumentSnapshot
    func openDocument(id: UUID) async throws -> OpenedDocument
    func saveNotebook(_ notebook: NotebookDocument, for id: UUID) async throws
    func saveText(_ text: String, for id: UUID) async throws
    func saveAutosave(notebook: NotebookDocument, for id: UUID) async throws
    func saveAutosave(text: String, for id: UUID) async throws
    func renameDocument(id: UUID, to newName: String) async throws -> DocumentSnapshot
    func duplicateDocument(id: UUID, clearOutputs: Bool) async throws -> DocumentSnapshot
    func exportDocument(id: UUID, to destinationURL: URL, clearOutputs: Bool) async throws
}

actor DocumentRepository: DocumentRepositoryProtocol {
    private let fileManager: FileManager
    private let bookmarkStore: SecurityScopedBookmarkStore
    private let codec = NotebookCodec()
    private let rootURL: URL
    private let metadataURL: URL

    init(
        fileManager: FileManager = .default,
        bookmarkStore: SecurityScopedBookmarkStore = SecurityScopedBookmarkStore(),
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.bookmarkStore = bookmarkStore
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let resolvedRootURL = rootURL ?? appSupport.appendingPathComponent("LocalNotebook", isDirectory: true)
        self.rootURL = resolvedRootURL
        self.metadataURL = resolvedRootURL.appendingPathComponent("documents.json")
    }

    func listDocuments() async throws -> [DocumentSnapshot] {
        try ensureLayout()
        return try loadRegistry().sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt })
    }

    func createNotebook(named: String) async throws -> DocumentSnapshot {
        try ensureLayout()
        let snapshot = try makeSnapshot(baseName: named, kind: .notebook, prefersExternalSync: false, externalBookmarkKey: nil)
        let url = localURL(for: snapshot)
        try codec.encode(.empty(named: named)).write(to: url, options: .atomic)
        try persist(snapshot: snapshot, replacing: nil)
        return snapshot
    }

    func createTextDocument(named: String, kind: DocumentKind) async throws -> DocumentSnapshot {
        try ensureLayout()
        let snapshot = try makeSnapshot(baseName: named, kind: kind, prefersExternalSync: false, externalBookmarkKey: nil)
        try "".write(to: localURL(for: snapshot), atomically: true, encoding: .utf8)
        try persist(snapshot: snapshot, replacing: nil)
        return snapshot
    }

    func importDocument(from externalURL: URL, strategy: ImportStrategy) async throws -> DocumentSnapshot {
        try ensureLayout()
        let kind = try documentKind(for: externalURL)
        let baseName = externalURL.deletingPathExtension().lastPathComponent
        let bookmarkKey = UUID().uuidString
        let snapshot = try makeSnapshot(
            baseName: baseName,
            kind: kind,
            prefersExternalSync: strategy == .keepExternalBookmark,
            externalBookmarkKey: strategy == .keepExternalBookmark ? bookmarkKey : nil
        )

        let startedAccess = externalURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                externalURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.copyItem(at: externalURL, to: localURL(for: snapshot))
        if strategy == .keepExternalBookmark {
            try bookmarkStore.saveBookmark(for: bookmarkKey, url: externalURL)
        }

        try persist(snapshot: snapshot, replacing: nil)
        return snapshot
    }

    func openDocument(id: UUID) async throws -> OpenedDocument {
        try ensureLayout()
        let registry = try loadRegistry()
        guard let snapshot = registry.first(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let sourceURL = autosaveURL(for: snapshot)
        let effectiveURL = fileManager.fileExists(atPath: sourceURL.path) ? sourceURL : localURL(for: snapshot)
        let data = try Data(contentsOf: effectiveURL)
        let updated = withUpdatedOpenDate(snapshot)
        try persist(snapshot: updated, replacing: snapshot.id)

        let content: OpenedDocumentContent
        switch snapshot.kind {
        case .notebook:
            content = .notebook(try codec.decode(data))
        case .python, .markdown, .text:
            let text = String(decoding: data, as: UTF8.self)
            content = .text(text)
        }
        return OpenedDocument(snapshot: updated, content: content, source: effectiveURL)
    }

    func saveNotebook(_ notebook: NotebookDocument, for id: UUID) async throws {
        let snapshot = try snapshot(for: id)
        let data = try codec.encode(notebook)
        try data.write(to: localURL(for: snapshot), options: .atomic)
        try removeAutosave(for: snapshot)
        try syncToExternalIfNeeded(data: data, snapshot: snapshot)
        try persist(snapshot: withUpdatedOpenDate(snapshot), replacing: id)
    }

    func saveText(_ text: String, for id: UUID) async throws {
        let snapshot = try snapshot(for: id)
        let data = Data(text.utf8)
        try data.write(to: localURL(for: snapshot), options: .atomic)
        try removeAutosave(for: snapshot)
        try syncToExternalIfNeeded(data: data, snapshot: snapshot)
        try persist(snapshot: withUpdatedOpenDate(snapshot), replacing: id)
    }

    func saveAutosave(notebook: NotebookDocument, for id: UUID) async throws {
        let snapshot = try snapshot(for: id)
        let data = try codec.encode(notebook)
        try data.write(to: autosaveURL(for: snapshot), options: .atomic)
    }

    func saveAutosave(text: String, for id: UUID) async throws {
        let snapshot = try snapshot(for: id)
        try Data(text.utf8).write(to: autosaveURL(for: snapshot), options: .atomic)
    }

    func renameDocument(id: UUID, to newName: String) async throws -> DocumentSnapshot {
        let current = try snapshot(for: id)
        let renamed = try makeSnapshot(
            id: id,
            baseName: newName,
            kind: current.kind,
            prefersExternalSync: current.prefersExternalSync,
            externalBookmarkKey: current.externalBookmarkKey,
            createdAt: current.createdAt
        )
        try fileManager.moveItem(at: localURL(for: current), to: localURL(for: renamed))
        if fileManager.fileExists(atPath: autosaveURL(for: current).path) {
            try fileManager.moveItem(at: autosaveURL(for: current), to: autosaveURL(for: renamed))
        }
        try persist(snapshot: renamed, replacing: id)
        return renamed
    }

    func duplicateDocument(id: UUID, clearOutputs: Bool) async throws -> DocumentSnapshot {
        let source = try snapshot(for: id)
        let duplicated = try makeSnapshot(baseName: source.displayName + " Copy", kind: source.kind, prefersExternalSync: false, externalBookmarkKey: nil)
        switch source.kind {
        case .notebook:
            var notebook = try codec.decode(Data(contentsOf: localURL(for: source)))
            if clearOutputs {
                NotebookEditingReducer.clearOutputs(&notebook)
            }
            try codec.encode(notebook).write(to: localURL(for: duplicated), options: .atomic)
        case .python, .markdown, .text:
            try fileManager.copyItem(at: localURL(for: source), to: localURL(for: duplicated))
        }
        try persist(snapshot: duplicated, replacing: nil)
        return duplicated
    }

    func exportDocument(id: UUID, to destinationURL: URL, clearOutputs: Bool) async throws {
        let snapshot = try snapshot(for: id)
        let startedAccess = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        switch snapshot.kind {
        case .notebook:
            var notebook = try codec.decode(Data(contentsOf: localURL(for: snapshot)))
            if clearOutputs {
                NotebookEditingReducer.clearOutputs(&notebook)
            }
            data = try codec.encode(notebook)
        case .python, .markdown, .text:
            data = try Data(contentsOf: localURL(for: snapshot))
        }
        try data.write(to: destinationURL, options: .atomic)
    }

    private func ensureLayout() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("Documents", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("Autosaves", isDirectory: true), withIntermediateDirectories: true)
    }

    private func loadRegistry() throws -> [DocumentSnapshot] {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return [] }
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode([DocumentSnapshot].self, from: data)
    }

    private func persist(snapshot: DocumentSnapshot, replacing id: UUID?) throws {
        var registry = try loadRegistry()
        if let id, let index = registry.firstIndex(where: { $0.id == id }) {
            registry[index] = snapshot
        } else {
            registry.append(snapshot)
        }
        let data = try JSONEncoder.pretty.encode(registry.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt }))
        try data.write(to: metadataURL, options: .atomic)
    }

    private func makeSnapshot(
        id: UUID = UUID(),
        baseName: String,
        kind: DocumentKind,
        prefersExternalSync: Bool,
        externalBookmarkKey: String?,
        createdAt: Date = Date()
    ) throws -> DocumentSnapshot {
        let safeName = try uniqueSanitizedFileName(baseName, kind: kind, excluding: id)
        let filename = "\(safeName).\(kind.fileExtension)"
        return DocumentSnapshot(
            id: id,
            displayName: safeName,
            kind: kind,
            relativePath: filename,
            createdAt: createdAt,
            lastOpenedAt: Date(),
            externalBookmarkKey: externalBookmarkKey,
            prefersExternalSync: prefersExternalSync
        )
    }

    private func localURL(for snapshot: DocumentSnapshot) -> URL {
        rootURL.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(snapshot.relativePath)
    }

    private func autosaveURL(for snapshot: DocumentSnapshot) -> URL {
        rootURL.appendingPathComponent("Autosaves", isDirectory: true).appendingPathComponent(snapshot.relativePath)
    }

    private func snapshot(for id: UUID) throws -> DocumentSnapshot {
        guard let snapshot = try loadRegistry().first(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return snapshot
    }

    private func withUpdatedOpenDate(_ snapshot: DocumentSnapshot) -> DocumentSnapshot {
        var copy = snapshot
        copy.lastOpenedAt = Date()
        return copy
    }

    private func removeAutosave(for snapshot: DocumentSnapshot) throws {
        let url = autosaveURL(for: snapshot)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func syncToExternalIfNeeded(data: Data, snapshot: DocumentSnapshot) throws {
        guard snapshot.prefersExternalSync,
              let key = snapshot.externalBookmarkKey,
              let externalURL = bookmarkStore.resolvedURL(for: key) else {
            return
        }
        let startedAccess = externalURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                externalURL.stopAccessingSecurityScopedResource()
            }
        }
        try data.write(to: externalURL, options: .atomic)
    }

    private func documentKind(for url: URL) throws -> DocumentKind {
        switch url.pathExtension.lowercased() {
        case "ipynb": .notebook
        case "py": .python
        case "md": .markdown
        case "txt": .text
        default: throw CocoaError(.fileReadUnknown)
        }
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.components(separatedBy: invalid).joined(separator: "-")
        return collapsed.isEmpty ? "Untitled" : collapsed
    }

    private func uniqueSanitizedFileName(_ value: String, kind: DocumentKind, excluding id: UUID) throws -> String {
        let registry = try loadRegistry()
        let base = sanitizedFileName(value)
        var candidate = base
        var counter = 2
        while registry.contains(where: { $0.id != id && $0.relativePath == "\(candidate).\(kind.fileExtension)" }) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
