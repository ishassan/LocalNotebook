import Foundation

enum MultilineTextValue: Hashable, Sendable, Codable {
    case string(String)
    case lines([String])

    init(jsonValue: JSONValue?) {
        switch jsonValue {
        case .array(let values):
            self = .lines(values.compactMap(\.stringValue))
        case .string(let string):
            self = .string(string)
        default:
            self = .string("")
        }
    }

    var joined: String {
        switch self {
        case .string(let value):
            value
        case .lines(let value):
            value.joined()
        }
    }

    var lineArray: [String] {
        switch self {
        case .string(let value):
            value.components(separatedBy: "\n").enumerated().map { offset, part in
                offset == value.components(separatedBy: "\n").count - 1 ? part : part + "\n"
            }
        case .lines(let value):
            value
        }
    }

    var jsonValue: JSONValue {
        switch self {
        case .string(let value):
            .string(value)
        case .lines(let value):
            .array(value.map(JSONValue.string))
        }
    }
}
