import Foundation

actor AutosaveCoordinator {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func schedule(id: UUID, delay: Duration = .seconds(1), operation: @escaping @Sendable () async -> Void) {
        tasks[id]?.cancel()
        tasks[id] = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    func cancel(id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
    }
}
