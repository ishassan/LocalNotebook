import Foundation

enum NotebookCodecError: LocalizedError {
    case invalidJSON
    case invalidRootObject

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "The notebook file is not valid JSON."
        case .invalidRootObject:
            "The notebook root must be a JSON object."
        }
    }
}

struct NotebookCodec: Sendable {
    func decode(_ data: Data) throws -> NotebookDocument {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw NotebookCodecError.invalidRootObject
        }
        let root = try dictionary.mapValues(JSONValue.init(any:))
        var remainder = root

        let nbformat = remainder.removeValue(forKey: "nbformat")?.intValue ?? 4
        let nbformatMinor = remainder.removeValue(forKey: "nbformat_minor")?.intValue ?? 5
        let metadata = remainder.removeValue(forKey: "metadata")?.objectValue ?? [:]
        let cells: [NotebookCell] = remainder.removeValue(forKey: "cells")?.arrayValue?.compactMap { value -> NotebookCell? in
            guard let object = value.objectValue else { return nil }
            return try? NotebookCell(jsonObject: object)
        } ?? []

        return NotebookDocument(
            nbformat: nbformat,
            nbformatMinor: nbformatMinor,
            metadata: metadata,
            cells: cells,
            additionalFields: remainder
        )
    }

    func encode(_ notebook: NotebookDocument) throws -> Data {
        let object = notebook.jsonObject.mapValues(\.anyValue)
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

private extension JSONValue {
    var intValue: Int? {
        switch self {
        case .int(let value):
            value
        case .number(let value):
            Int(value)
        default:
            nil
        }
    }
}
