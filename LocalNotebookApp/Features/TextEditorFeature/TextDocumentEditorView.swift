import SwiftUI

struct TextDocumentEditorView: View {
    @Bindable var store: DocumentEditorStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: ExportFileDocument?
    @State private var exportShown = false
    @State private var deleteConfirmationShown = false

    var body: some View {
        VStack(spacing: 16) {
            TextEditor(text: Binding(get: { store.textContent }, set: { store.updateText($0) }))
                .font(.body)
                .padding(12)
                .background(NotebookTheme.panelFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 18))
        }
        .padding()
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
        .alert("Delete \(store.snapshot?.displayName ?? "Document")?", isPresented: $deleteConfirmationShown) {
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
            defaultFilename: store.snapshot?.displayName ?? "text"
        ) { _ in }
    }
}
