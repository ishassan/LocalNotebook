import Foundation

actor UITestKernelClient: KernelClient {
    let sessionID: UUID

    private var executionCount = 0
    private var integers: [String: Int] = [:]

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func execute(code: String, workingDirectory: URL?) async throws -> KernelExecutionResult {
        executionCount += 1

        var outputs: [NotebookOutput] = []
        let lines = code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("print("), let printed = extractPrintArgument(from: trimmed) {
                outputs.append(.init(outputType: "stream", name: "stdout", text: .string(printed + "\n")))
            } else if let assignment = parseAssignment(from: trimmed) {
                integers[assignment.name] = assignment.value
            } else if let sum = parseAddition(from: trimmed) {
                let value = (integers[sum.name] ?? 0) + sum.value
                outputs.append(.init(outputType: "display_data", data: ["text/plain": .string(String(value))]))
            } else if trimmed.contains("matplotlib") || trimmed.contains("plt.") {
                outputs.append(.init(
                    outputType: "display_data",
                    data: [
                        "image/svg+xml": .string("""
                        <svg xmlns="http://www.w3.org/2000/svg" width="300" height="180" viewBox="0 0 300 180">
                          <rect width="300" height="180" rx="18" fill="#fbfbf7"/>
                          <polyline fill="none" stroke="#0f6bb7" stroke-width="3" points="40,140 120,95 200,60 260,35"/>
                          <text x="150" y="26" text-anchor="middle" font-size="14" font-family="-apple-system,BlinkMacSystemFont,sans-serif">UI Test Plot</text>
                        </svg>
                        """),
                        "text/plain": .string("<Figure series=1>")
                    ]
                ))
            }
        }

        return KernelExecutionResult(executionCount: executionCount, outputs: outputs)
    }

    func restart() async throws {
        executionCount = 0
        integers = [:]
    }

    func interrupt() async {}

    private func extractPrintArgument(from line: String) -> String? {
        guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else {
            return nil
        }
        let raw = line[line.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private func parseAssignment(from line: String) -> (name: String, value: Int)? {
        let parts = line.components(separatedBy: "=")
        guard parts.count == 2 else { return nil }
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let value = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return (name, value)
    }

    private func parseAddition(from line: String) -> (name: String, value: Int)? {
        let parts = line.components(separatedBy: "+")
        guard parts.count == 2 else { return nil }
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let value = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return (name, value)
    }
}
