import Foundation

struct LocalPythonKernel: KernelClient {
    let sessionID: UUID
    private let actor: PythonSessionActor

    init(sessionID: UUID) {
        self.sessionID = sessionID
        self.actor = PythonSessionActor(sessionID: sessionID)
    }

    func execute(code: String, workingDirectory: URL?) async throws -> KernelExecutionResult {
        try await actor.execute(code: code, workingDirectory: workingDirectory)
    }

    func restart() async throws {
        try await actor.restart()
    }

    func interrupt() async {
        await actor.interrupt()
    }
}
