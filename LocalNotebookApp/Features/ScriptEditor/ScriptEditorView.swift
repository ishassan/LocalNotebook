import SwiftUI

struct ScriptEditorView: View {
    @Bindable var store: DocumentEditorStore
    @Environment(AppSessionStore.self) private var appSession
    @State private var exportDocument: ExportFileDocument?
    @State private var exportShown = false

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
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                CodeTextView(text: Binding(get: { store.textContent }, set: { store.updateText($0) }), fontSize: appSession.settings.codeFontSize)
                    .frame(minHeight: 260)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                if let outputCell = store.notebook?.cells.first, !outputCell.outputs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(outputCell.outputs, id: \.id) { output in
                            OutputRenderer(output: output)
                        }
                    }
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding()
        }
        .background(NotebookTheme.warmBackground.ignoresSafeArea())
        .navigationTitle(store.title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Save") {
                    Task { await store.save() }
                }
                .accessibilityIdentifier("save-document")
                Button("Export") {
                    exportDocument = try? store.exportDocumentData()
                    exportShown = exportDocument != nil
                }
            }
        }
        .fileExporter(
            isPresented: $exportShown,
            document: exportDocument,
            contentType: store.snapshot?.kind.utType ?? .plainText,
            defaultFilename: store.snapshot?.displayName ?? "script"
        ) { _ in }
    }
}
