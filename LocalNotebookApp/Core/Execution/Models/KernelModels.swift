import Foundation

enum KernelState: String, Sendable {
    case idle
    case busy
    case unavailable
}

struct KernelExecutionResult: Sendable, Equatable {
    var executionCount: Int?
    var outputs: [NotebookOutput]
}
