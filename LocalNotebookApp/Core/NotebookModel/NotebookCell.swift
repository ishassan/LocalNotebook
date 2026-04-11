import Foundation

enum NotebookCellType: String, Codable, CaseIterable, Sendable {
    case code
    case markdown
    case raw
}

struct NotebookCell: Identifiable, Hashable, Sendable {
    let id: String
    var cellType: NotebookCellType
    var source: MultilineTextValue
    var metadata: [String: JSONValue]
    var attachments: [String: [String: String]]
    var executionCount: Int?
    var outputs: [NotebookOutput]
    var additionalFields: [String: JSONValue]

    init(
        id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "_"),
        cellType: NotebookCellType,
        source: MultilineTextValue = .string(""),
        metadata: [String: JSONValue] = [:],
        attachments: [String: [String: String]] = [:],
        executionCount: Int? = nil,
        outputs: [NotebookOutput] = [],
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.cellType = cellType
        self.source = source
        self.metadata = metadata
        self.attachments = attachments
        self.executionCount = executionCount
        self.outputs = outputs
        self.additionalFields = additionalFields
    }

    init(jsonObject: [String: JSONValue]) throws {
        var remainder = jsonObject
        let typeRaw = remainder.removeValue(forKey: "cell_type")?.stringValue ?? "raw"
        let id = remainder.removeValue(forKey: "id")?.stringValue ?? UUID().uuidString.replacingOccurrences(of: "-", with: "_")
        let cellType = NotebookCellType(rawValue: typeRaw) ?? .raw
        let source = MultilineTextValue(jsonValue: remainder.removeValue(forKey: "source"))
        let metadata = remainder.removeValue(forKey: "metadata")?.objectValue ?? [:]
        let executionCount: Int?
        if case .int(let value)? = remainder.removeValue(forKey: "execution_count") {
            executionCount = value
        } else if case .number(let value)? = remainder.removeValue(forKey: "execution_count") {
            executionCount = Int(value)
        } else {
            executionCount = nil
        }
        let outputs = remainder.removeValue(forKey: "outputs")?.arrayValue?.compactMap { value in
            value.objectValue.map(NotebookOutput.init(jsonObject:))
        } ?? []
        let attachmentDict = remainder.removeValue(forKey: "attachments")?.objectValue ?? [:]
        let attachments = attachmentDict.reduce(into: [String: [String: String]]()) { result, entry in
            guard let mimeBundle = entry.value.objectValue else { return }
            result[entry.key] = mimeBundle.reduce(into: [:]) { partial, mimeEntry in
                partial[mimeEntry.key] = mimeEntry.value.stringValue ?? ""
            }
        }

        self.init(
            id: id,
            cellType: cellType,
            source: source,
            metadata: metadata,
            attachments: attachments,
            executionCount: executionCount,
            outputs: outputs,
            additionalFields: remainder
        )
    }

    var jsonObject: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "cell_type": .string(cellType.rawValue),
            "metadata": .object(metadata),
            "source": source.jsonValue,
            "id": .string(id)
        ]
        if cellType == .code {
            object["outputs"] = .array(outputs.map { .object($0.jsonObject) })
            object["execution_count"] = executionCount.map(JSONValue.int) ?? .null
        }
        if !attachments.isEmpty {
            object["attachments"] = .object(attachments.mapValues { bundle in
                .object(bundle.mapValues(JSONValue.string))
            })
        }
        additionalFields.forEach { object[$0.key] = $0.value }
        return object
    }
}
