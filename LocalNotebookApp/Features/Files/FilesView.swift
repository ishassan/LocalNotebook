import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @Environment(AppSessionStore.self) private var appSession

    @State private var importerShown = false

    var body: some View {
        List {
            Section("Quick Actions") {
                Button {
                    Task { _ = await appSession.createNotebook() }
                } label: {
                    Label("New Notebook", systemImage: "plus.rectangle.on.folder")
                }
                Button {
                    Task { _ = await appSession.createTextDocument(kind: .python) }
                } label: {
                    Label("New Python Script", systemImage: "curlybraces.square")
                }
                Button {
                    importerShown = true
                } label: {
                    Label("Import from Files", systemImage: "square.and.arrow.down")
                }
                if UITestHarness.isEnabled {
                    Button {
                        Task { await importFixture(named: "UITestNotebook", ext: "ipynb") }
                    } label: {
                        Label("Import Sample Notebook", systemImage: "testtube.2")
                    }
                    .accessibilityIdentifier("import-sample-notebook")
                }
            }

            Section("Local Documents") {
                if appSession.documents.isEmpty {
                    Text("No local documents yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appSession.documents) { snapshot in
                        NavigationLink(value: snapshot.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.displayName)
                                Text(snapshot.kind.rawValue.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("document-\(snapshot.displayName)")
                    }
                }
            }
        }
        .navigationTitle("Files")
        .listStyle(.insetGrouped)
        .refreshable {
            await appSession.refresh()
        }
        .task {
            await appSession.refresh()
        }
        .fileImporter(
            isPresented: $importerShown,
            allowedContentTypes: [.json, .plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "py") ?? .plainText]
        ) { result in
            if case .success(let url) = result {
                Task { _ = await appSession.importDocument(from: url) }
            }
        }
    }

    private func importFixture(named: String, ext: String) async {
        guard let url = Bundle.main.url(forResource: named, withExtension: ext, subdirectory: "SampleNotebooks") else { return }
        _ = await appSession.importDocument(from: url)
    }
}
