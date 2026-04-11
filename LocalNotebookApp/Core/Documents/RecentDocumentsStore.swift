import Foundation
import Observation

@MainActor
@Observable
final class RecentDocumentsStore {
    private(set) var documents: [DocumentSnapshot] = []

    func update(from allDocuments: [DocumentSnapshot], limit: Int = 12) {
        documents = Array(allDocuments.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt }).prefix(limit))
    }
}
