import SwiftUI

struct RootTabView: View {
    @Environment(AppSessionStore.self) private var appSession

    var body: some View {
        TabView(selection: Binding(get: { appSession.selectedTab }, set: { appSession.selectedTab = $0 })) {
            NavigationStack {
                FilesView()
            }
            .tabItem {
                Label("Files", systemImage: "folder")
            }
            .tag(0)

            NavigationStack {
                RecentsView()
            }
            .tabItem {
                Label("Recents", systemImage: "clock.arrow.circlepath")
            }
            .tag(1)

            NavigationStack {
                RunningSessionsView()
            }
            .tabItem {
                Label("Sessions", systemImage: "play.circle")
            }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(3)
        }
        .overlay(alignment: .bottom) {
            if let lastError = appSession.lastError {
                Text(lastError)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }
}
