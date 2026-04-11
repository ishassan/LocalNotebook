import Foundation

actor PythonSessionActor {
    private let sessionID: UUID
    private nonisolated(unsafe) static var didInitialize = false

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func execute(code: String, workingDirectory: URL?) throws -> KernelExecutionResult {
        try Self.initializeIfNeeded()
        let response = try PythonBridge.executeCode(
            code,
            sessionID: sessionID.uuidString,
            workingDirectory: workingDirectory?.path
        )
        return try Self.parseExecutionResult(response)
    }

    func restart() throws {
        try Self.initializeIfNeeded()
        _ = try PythonBridge.restartSession(sessionID.uuidString)
    }

    func interrupt() {
        PythonBridge.interrupt()
    }

    private static func initializeIfNeeded() throws {
        guard !didInitialize else { return }
        guard let resourcePath = Bundle.main.resourcePath else {
            throw AppError.runtimeUnavailable("App bundle resource path is unavailable.")
        }
        try PythonBridge.initializeIfNeeded(resourcePath)
        didInitialize = true
    }

    private static func parseExecutionResult(_ response: [String: Any]) throws -> KernelExecutionResult {
        let executionCount: Int?
        if let count = response["execution_count"] as? Int {
            executionCount = count
        } else if let count = response["execution_count"] as? NSNumber {
            executionCount = count.intValue
        } else {
            executionCount = nil
        }

        let outputsAny = response["outputs"] as? [[String: Any]] ?? []
        let outputs = try outputsAny.map { object in
            try NotebookOutput(jsonObject: object.mapValues(JSONValue.init(any:)))
        }

        return KernelExecutionResult(executionCount: executionCount, outputs: outputs)
    }
}
