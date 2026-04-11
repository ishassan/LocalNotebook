import SwiftUI

struct RootTabView: View {
    @Environment(AppSessionStore.self) private var appSession

    var body: some View {
        TabView(selection: Binding(get: { appSession.selectedTab }, set: { appSession.selectedTab = $0 })) {
            NavigationStack(path: Binding(get: { appSession.filesNavigationPath }, set: { appSession.filesNavigationPath = $0 })) {
                FilesView()
                    .navigationDestination(for: UUID.self) { documentID in
                        DocumentSceneView(documentID: documentID)
                    }
            }
            .tabItem {
                Label("Browse", systemImage: "folder")
            }
            .tag(AppTab.browse.rawValue)

            NavigationStack {
                RecentsView()
            }
            .tabItem {
                Label("Recents", systemImage: "clock")
            }
            .tag(AppTab.recents.rawValue)

            NavigationStack {
                PackagesView()
            }
            .tabItem {
                Label("Packages", systemImage: "cube.box")
            }
            .tag(AppTab.packages.rawValue)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings.rawValue)
        }
        .tint(NotebookTheme.accent)
        .toolbarBackground(Color.black.opacity(0.96), for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .overlay(alignment: .top) {
            if let lastError = appSession.lastError {
                Text(lastError)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.22, green: 0.08, blue: 0.08), in: Capsule())
                    .padding(.top, 10)
            }
        }
    }
}
