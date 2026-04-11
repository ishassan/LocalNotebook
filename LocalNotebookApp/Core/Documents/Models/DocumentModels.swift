import Foundation
import UniformTypeIdentifiers

enum DocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case notebook
    case python
    case markdown
    case text

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .notebook: "ipynb"
        case .python: "py"
        case .markdown: "md"
        case .text: "txt"
        }
    }

    var utType: UTType {
        switch self {
        case .notebook:
            UTType.json
        case .python:
            UTType(filenameExtension: "py") ?? .plainText
        case .markdown:
            UTType(filenameExtension: "md") ?? .plainText
        case .text:
            .plainText
        }
    }
}

enum ImportStrategy: String, Codable, CaseIterable, Sendable {
    case copyIntoAppStorage
    case keepExternalBookmark
}

struct DocumentSnapshot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var displayName: String
    var kind: DocumentKind
    var relativePath: String
    var createdAt: Date
    var lastOpenedAt: Date
    var externalBookmarkKey: String?
    var prefersExternalSync: Bool
}

enum OpenedDocumentContent: Sendable {
    case notebook(NotebookDocument)
    case text(String)
}

struct OpenedDocument: Sendable {
    var snapshot: DocumentSnapshot
    var content: OpenedDocumentContent
    var source: URL
}
