import SwiftUI

@main
struct LocalNotebookAppMain: App {
    @State private var container = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(container.appSession)
                .preferredColorScheme(container.appSession.settings.preferredColorScheme)
                .task {
                    if UITestHarness.shouldResetStorage {
                        try? FileManager.default.removeItem(at: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("LocalNotebook"))
                    }
                    await container.appSession.refresh()
                }
                .onOpenURL { url in
                    Task {
                        _ = await container.appSession.importDocument(from: url, openAfterImport: true)
                    }
                }
        }
    }
}
