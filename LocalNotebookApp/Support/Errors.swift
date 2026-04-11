import Foundation

enum AppError: LocalizedError {
    case unsupportedDocumentType
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDocumentType:
            "That document type is not supported."
        case .runtimeUnavailable(let message):
            message
        }
    }
}
