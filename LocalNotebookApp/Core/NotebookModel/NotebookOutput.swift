import Foundation

struct NotebookOutput: Identifiable, Hashable, Sendable {
    let id: UUID
    var outputType: String
    var name: String?
    var text: MultilineTextValue?
    var executionCount: Int?
    var data: [String: JSONValue]
    var metadata: [String: JSONValue]
    var ename: String?
    var evalue: String?
    var traceback: [String]
    var additionalFields: [String: JSONValue]

    init(
        id: UUID = UUID(),
        outputType: String,
        name: String? = nil,
        text: MultilineTextValue? = nil,
        executionCount: Int? = nil,
        data: [String: JSONValue] = [:],
        metadata: [String: JSONValue] = [:],
        ename: String? = nil,
        evalue: String? = nil,
        traceback: [String] = [],
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.outputType = outputType
        self.name = name
        self.text = text
        self.executionCount = executionCount
        self.data = data
        self.metadata = metadata
        self.ename = ename
        self.evalue = evalue
        self.traceback = traceback
        self.additionalFields = additionalFields
    }

    init(jsonObject: [String: JSONValue]) {
        let outputType = jsonObject["output_type"]?.stringValue ?? "display_data"
        var remainder = jsonObject
        remainder.removeValue(forKey: "output_type")
        let name = remainder.removeValue(forKey: "name")?.stringValue
        let text = MultilineTextValue(jsonValue: remainder.removeValue(forKey: "text"))
        let executionCount: Int?
        if case .int(let value)? = remainder.removeValue(forKey: "execution_count") {
            executionCount = value
        } else if case .number(let value)? = remainder.removeValue(forKey: "execution_count") {
            executionCount = Int(value)
        } else {
            executionCount = nil
        }
        let data = remainder.removeValue(forKey: "data")?.objectValue ?? [:]
        let metadata = remainder.removeValue(forKey: "metadata")?.objectValue ?? [:]
        let ename = remainder.removeValue(forKey: "ename")?.stringValue
        let evalue = remainder.removeValue(forKey: "evalue")?.stringValue
        let traceback = remainder.removeValue(forKey: "traceback")?.arrayValue?.compactMap(\.stringValue) ?? []

        self.init(
            outputType: outputType,
            name: name,
            text: jsonObject["text"] != nil ? text : nil,
            executionCount: executionCount,
            data: data,
            metadata: metadata,
            ename: ename,
            evalue: evalue,
            traceback: traceback,
            additionalFields: remainder
        )
    }

    var jsonObject: [String: JSONValue] {
        var object: [String: JSONValue] = ["output_type": .string(outputType)]
        if let name {
            object["name"] = .string(name)
        }
        if let text {
            object["text"] = text.jsonValue
        }
        if let executionCount {
            object["execution_count"] = .int(executionCount)
        }
        if !data.isEmpty {
            object["data"] = .object(data)
        }
        if !metadata.isEmpty {
            object["metadata"] = .object(metadata)
        }
        if let ename {
            object["ename"] = .string(ename)
        }
        if let evalue {
            object["evalue"] = .string(evalue)
        }
        if !traceback.isEmpty {
            object["traceback"] = .array(traceback.map(JSONValue.string))
        }
        additionalFields.forEach { object[$0.key] = $0.value }
        return object
    }
}
