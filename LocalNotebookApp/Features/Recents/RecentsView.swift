import SwiftUI

struct RecentsView: View {
    @Environment(AppSessionStore.self) private var appSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Jump back into recently opened work.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if appSession.recentsStore.documents.isEmpty {
                    ContentUnavailableView(
                        "No Recent Files",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Open a notebook or script from Browse to populate this list.")
                    )
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    .background(NotebookTheme.panelFill(for: .dark), in: RoundedRectangle(cornerRadius: 22))
                } else {
                    VStack(spacing: 12) {
                        ForEach(appSession.recentsStore.documents) { snapshot in
                            NavigationLink {
                                DocumentSceneView(documentID: snapshot.id)
                            } label: {
                                DocumentCard(snapshot: snapshot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(NotebookTheme.background(for: .dark).ignoresSafeArea())
        .navigationTitle("Recents")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await appSession.refresh()
        }
    }
}
