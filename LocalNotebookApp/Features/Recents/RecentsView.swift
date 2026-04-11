import SwiftUI

struct RecentsView: View {
    @Environment(AppSessionStore.self) private var appSession

    var body: some View {
        List {
            if appSession.recentsStore.documents.isEmpty {
                Text("Recent notebooks and scripts will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appSession.recentsStore.documents) { snapshot in
                    NavigationLink(snapshot.displayName) {
                        DocumentSceneView(documentID: snapshot.id)
                    }
                }
            }
        }
        .navigationTitle("Recents")
        .task {
            await appSession.refresh()
        }
    }
}
