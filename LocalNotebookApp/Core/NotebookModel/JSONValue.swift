import Foundation

enum JSONValue: Hashable, Sendable, Codable {
    case string(String)
    case number(Double)
    case int(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(any value: Any) throws {
        switch value {
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if floor(number.doubleValue) == number.doubleValue {
                self = .int(number.intValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let array as [Any]:
            self = .array(try array.map(JSONValue.init(any:)))
        case let object as [String: Any]:
            self = .object(try object.mapValues(JSONValue.init(any:)))
        case _ as NSNull:
            self = .null
        default:
            throw NSError(domain: "JSONValue", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported JSON value: \(type(of: value))"])
        }
    }

    var anyValue: Any {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            value
        case .int(let value):
            value
        case .bool(let value):
            value
        case .object(let value):
            value.mapValues(\.anyValue)
        case .array(let value):
            value.map(\.anyValue)
        case .null:
            NSNull()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
