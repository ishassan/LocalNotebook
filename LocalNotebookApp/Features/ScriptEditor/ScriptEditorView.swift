import SwiftUI

struct ScriptEditorView: View {
    @Bindable var store: DocumentEditorStore
    @Environment(AppSessionStore.self) private var appSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: ExportFileDocument?
    @State private var exportShown = false
    @State private var deleteConfirmationShown = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Circle()
                        .fill(store.kernelState == .busy ? Color.orange : NotebookTheme.accent)
                        .frame(width: 10, height: 10)
                    Text(store.statusMessage)
                    Spacer()
                    Button("Run") {
                        Task { await store.runScript() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("run-script")
                }
                .padding(16)
                .background(NotebookTheme.panelFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))

                CodeEditorSurface(
                    text: Binding(get: { store.textContent }, set: { store.updateText($0) }),
                    fontSize: appSession.settings.codeFontSize,
                    colorScheme: colorScheme
                )
                .frame(minHeight: 260)

                if let outputCell = store.notebook?.cells.first, !outputCell.outputs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(outputCell.outputs, id: \.id) { output in
                            OutputRenderer(output: output)
                        }
                    }
                    .padding(16)
                    .background(NotebookTheme.panelFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding()
        }
        .background(NotebookTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle(store.title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Save") {
                    Task { await store.save() }
                }
                .accessibilityIdentifier("save-document")
                Menu {
                    Button("Export") {
                        exportDocument = try? store.exportDocumentData()
                        exportShown = exportDocument != nil
                    }
                    Button("Delete", role: .destructive) {
                        deleteConfirmationShown = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete \(store.snapshot?.displayName ?? "Script")?", isPresented: $deleteConfirmationShown) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    if await store.deleteDocument() {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .fileExporter(
            isPresented: $exportShown,
            document: exportDocument,
            contentType: store.snapshot?.kind.utType ?? .plainText,
            defaultFilename: store.snapshot?.displayName ?? "script"
        ) { _ in }
    }
}
