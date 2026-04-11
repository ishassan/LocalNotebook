import Foundation

protocol KernelClient: Sendable {
    var sessionID: UUID { get }
    func execute(code: String, workingDirectory: URL?) async throws -> KernelExecutionResult
    func restart() async throws
    func interrupt() async
}
