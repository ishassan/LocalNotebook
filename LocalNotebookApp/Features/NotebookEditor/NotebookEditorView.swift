import SwiftUI

struct NotebookEditorView: View {
    @Bindable var store: DocumentEditorStore
    @Environment(AppSessionStore.self) private var appSession

    @State private var previewedMarkdownCellIDs = Set<String>()
    @State private var renamePromptShown = false
    @State private var renameText = ""
    @State private var exportDocument: ExportFileDocument?
    @State private var exportShown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusHeader
                ForEach(Array((store.notebook?.cells ?? []).enumerated()), id: \.element.id) { index, cell in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(cell.cellType.rawValue.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            cellActionMenu(cell: cell, index: index)
                        }

                        switch cell.cellType {
                        case .code:
                            CodeTextView(
                                text: Binding(
                                    get: { store.notebook?.cells[index].source.joined ?? "" },
                                    set: { store.updateCellSource(cellID: cell.id, source: $0) }
                                ),
                                fontSize: appSession.settings.codeFontSize
                            )
                            .frame(minHeight: 120)
                        case .markdown:
                            if previewedMarkdownCellIDs.contains(cell.id) {
                                MarkdownPreviewView(markdown: cell.source.joined)
                            } else {
                                TextEditor(text: Binding(
                                    get: { store.notebook?.cells[index].source.joined ?? "" },
                                    set: { store.updateCellSource(cellID: cell.id, source: $0) }
                                ))
                                .frame(minHeight: 100)
                                .font(.system(size: appSession.settings.notebookTextSize))
                            }
                        case .raw:
                            TextEditor(text: Binding(
                                get: { store.notebook?.cells[index].source.joined ?? "" },
                                set: { store.updateCellSource(cellID: cell.id, source: $0) }
                            ))
                            .frame(minHeight: 100)
                            .font(.system(size: appSession.settings.notebookTextSize))
                        }

                        if !cell.outputs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(cell.outputs, id: \.id) { output in
                                    OutputRenderer(output: output)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: NotebookTheme.cardCornerRadius))
                }
            }
            .padding()
        }
        .background(NotebookTheme.warmBackground.ignoresSafeArea())
        .navigationTitle(store.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Save") {
                    Task { await store.save() }
                }
                .accessibilityIdentifier("save-document")
                Menu {
                    Button("Rename") {
                        renameText = store.title
                        renamePromptShown = true
                    }
                    Button("Duplicate") {
                        Task { _ = await store.duplicate() }
                    }
                    Button("Export") {
                        exportDocument = try? store.exportDocumentData()
                        exportShown = exportDocument != nil
                    }
                    Button("Clear Outputs") {
                        store.clearOutputs()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("notebook-menu")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    store.addCell(type: .code, after: store.notebook?.cells.indices.last)
                } label: {
                    Label("Code", systemImage: "plus.square.on.square")
                }
                Button {
                    store.addCell(type: .markdown, after: store.notebook?.cells.indices.last)
                } label: {
                    Label("Markdown", systemImage: "text.badge.plus")
                }
                Spacer()
                Button {
                    Task { await store.runAll() }
                } label: {
                    Label("Run All", systemImage: "play.fill")
                }
                .accessibilityIdentifier("run-all")
            }
        }
        .alert("Rename Notebook", isPresented: $renamePromptShown) {
            TextField("Notebook name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                Task { await store.rename(to: renameText) }
            }
        }
        .alert("Error", isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in store.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .fileExporter(
            isPresented: $exportShown,
            document: exportDocument,
            contentType: store.snapshot?.kind.utType ?? .data,
            defaultFilename: store.snapshot?.displayName ?? "Notebook"
        ) { _ in }
    }

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(store.kernelState == .busy ? Color.orange : (store.kernelState == .unavailable ? Color.red : NotebookTheme.accent))
                .frame(width: 10, height: 10)
            Text(store.statusMessage)
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                Task { await store.restartKernel() }
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            Button {
                Task { await store.interruptKernel() }
            } label: {
                Label("Interrupt", systemImage: "stop.fill")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func cellActionMenu(cell: NotebookCell, index: Int) -> some View {
        Menu {
            if cell.cellType == .code {
                Button("Run Cell") { Task { await store.runCell(cell.id) } }
                Button("Run Above") { Task { await store.runAbove(cell.id) } }
                Button("Run All Below") { Task { await store.runAllBelow(cell.id) } }
            }
            if cell.cellType == .markdown {
                Button(previewedMarkdownCellIDs.contains(cell.id) ? "Edit Markdown" : "Preview Markdown") {
                    if previewedMarkdownCellIDs.contains(cell.id) {
                        previewedMarkdownCellIDs.remove(cell.id)
                    } else {
                        previewedMarkdownCellIDs.insert(cell.id)
                    }
                }
            }
            Button("Duplicate Cell") { store.duplicateCell(cell.id) }
            Button("Delete Cell", role: .destructive) { store.deleteCell(cell.id) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .padding(8)
        }
    }
}
