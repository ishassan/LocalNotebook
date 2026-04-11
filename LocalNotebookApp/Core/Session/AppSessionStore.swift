import Foundation
import Observation

@MainActor
@Observable
final class AppSessionStore {
    let repository: DocumentRepository
    let settings: SettingsStore
    let recentsStore: RecentDocumentsStore
    let autosaveCoordinator: AutosaveCoordinator

    var documents: [DocumentSnapshot] = []
    var selectedTab: Int = 0
    var lastError: String?
    var runningSessions: [RunningSessionSummary] = []

    init(
        repository: DocumentRepository = DocumentRepository(),
        settings: SettingsStore? = nil,
        recentsStore: RecentDocumentsStore? = nil,
        autosaveCoordinator: AutosaveCoordinator = AutosaveCoordinator()
    ) {
        self.repository = repository
        self.settings = settings ?? SettingsStore()
        self.recentsStore = recentsStore ?? RecentDocumentsStore()
        self.autosaveCoordinator = autosaveCoordinator
    }

    func refresh() async {
        do {
            documents = try await repository.listDocuments()
            recentsStore.update(from: documents)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createNotebook() async -> DocumentSnapshot? {
        do {
            let snapshot = try await repository.createNotebook(named: "Untitled Notebook")
            await refresh()
            return snapshot
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func createTextDocument(kind: DocumentKind) async -> DocumentSnapshot? {
        do {
            let name = switch kind {
            case .python: "script"
            case .markdown: "note"
            case .text: "text"
            case .notebook: "Untitled Notebook"
            }
            let snapshot = try await repository.createTextDocument(named: name, kind: kind)
            await refresh()
            return snapshot
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func importDocument(from url: URL) async -> DocumentSnapshot? {
        do {
            let strategy: ImportStrategy = settings.openImportedFilesAsCopy ? .copyIntoAppStorage : .keepExternalBookmark
            let snapshot = try await repository.importDocument(from: url, strategy: strategy)
            await refresh()
            return snapshot
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func registerSession(documentID: UUID, title: String, kind: DocumentKind, state: KernelState) {
        let summary = RunningSessionSummary(documentID: documentID, title: title, kind: kind, state: state, updatedAt: Date())
        if let index = runningSessions.firstIndex(where: { $0.documentID == documentID }) {
            runningSessions[index] = summary
        } else {
            runningSessions.append(summary)
        }
        runningSessions.sort(by: { $0.updatedAt > $1.updatedAt })
    }

    func removeSession(documentID: UUID) {
        runningSessions.removeAll { $0.documentID == documentID }
    }
}

struct RunningSessionSummary: Identifiable, Hashable, Sendable {
    let documentID: UUID
    var title: String
    var kind: DocumentKind
    var state: KernelState
    var updatedAt: Date

    var id: UUID { documentID }
}
