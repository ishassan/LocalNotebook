import SwiftUI

struct DocumentSceneView: View {
    let documentID: UUID

    @Environment(AppSessionStore.self) private var appSession
    @State private var editorStore: DocumentEditorStore?

    var body: some View {
        Group {
            if let editorStore {
                switch editorStore.kind {
                case .notebook:
                    NotebookEditorView(store: editorStore)
                case .python:
                    ScriptEditorView(store: editorStore)
                case .markdown, .text:
                    TextDocumentEditorView(store: editorStore)
                case nil:
                    ProgressView()
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard editorStore == nil else { return }
            let store = DocumentEditorStore(documentID: documentID, appSession: appSession)
            editorStore = store
            await store.load()
        }
    }
}
