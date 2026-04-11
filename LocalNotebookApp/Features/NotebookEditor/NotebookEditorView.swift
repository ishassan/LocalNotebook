import SwiftUI

struct NotebookEditorView: View {
    @Bindable var store: DocumentEditorStore
    @Environment(AppSessionStore.self) private var appSession
    @Environment(\.colorScheme) private var colorScheme

    @State private var renamePromptShown = false
    @State private var renameText = ""
    @State private var exportDocument: ExportFileDocument?
    @State private var exportShown = false
    @State private var selectedCellID: String?
    @State private var editingCellID: String?

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusHeader
                    primaryActionStrip
                    ForEach(Array((store.notebook?.cells ?? []).enumerated()), id: \.element.id) { index, cell in
                        notebookCellView(cell: cell, index: index, scrollProxy: scrollProxy)
                    }
                    addCellButton
                }
                .padding()
            }
        }
        .background(NotebookTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle(store.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Save") {
                    Task { await store.save() }
                }
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
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    store.appendCell(type: .code)
                } label: {
                    Label("Code", systemImage: "plus.square.on.square")
                }
                Button {
                    store.appendCell(type: .markdown)
                } label: {
                    Label("Markdown", systemImage: "text.badge.plus")
                }
                Spacer()
                Button {
                    Task { await store.runAll() }
                } label: {
                    Label("Run All", systemImage: "play.fill")
                }
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

    private var anchorTargets: [String: String] {
        (store.notebook?.cells ?? []).reduce(into: [String: String]()) { result, cell in
            for anchorID in MarkdownHTMLRenderer.anchorIDs(in: cell.source.joined) {
                result[anchorID] = cell.id
            }
        }
    }

    private func notebookCellView(cell: NotebookCell, index: Int, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                cellActionMenu(cell: cell, index: index)
            }

            cellEditorView(cell: cell, index: index, scrollProxy: scrollProxy)

            if !cell.outputs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cell.outputs, id: \.id) { output in
                        OutputRenderer(output: output)
                    }
                }
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                selectCell(cell)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                beginEditing(cell)
            }
        )
        .overlay(alignment: .leading) {
            if selectedCellID == cell.id {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 4)
                    .padding(.vertical, 6)
                    .shadow(color: .white.opacity(0.18), radius: 8, x: 0, y: 0)
            }
        }
        .id(cell.id)
    }

    @ViewBuilder
    private func cellEditorView(cell: NotebookCell, index: Int, scrollProxy: ScrollViewProxy) -> some View {
        switch cell.cellType {
        case .code:
            codeCellView(cell: cell, index: index)
        case .markdown:
            if editingCellID == cell.id {
                TextEditor(text: cellSourceBinding(for: cell.id, fallbackIndex: index))
                    .frame(minHeight: 100)
                    .font(.system(size: appSession.settings.notebookTextSize))
            } else {
                MarkdownPreviewView(
                    markdown: cell.source.joined,
                    baseFontSize: appSession.settings.notebookTextSize,
                    onOpenAnchor: { anchorID in
                        scrollToAnchor(anchorID, using: scrollProxy)
                    }
                )
            }
        case .raw:
            TextEditor(text: cellSourceBinding(for: cell.id, fallbackIndex: index))
                .frame(minHeight: 100)
                .font(.system(size: appSession.settings.notebookTextSize))
        }
    }

    @ViewBuilder
    private func codeCellView(cell: NotebookCell, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In [\(cell.executionCount.map(String.init) ?? " ")]:")
                .font(.custom("Menlo-Regular", size: max(14, appSession.settings.codeFontSize - 1)))
                .foregroundStyle(.secondary)

            Group {
                if editingCellID == cell.id {
                    CodeTextView(
                        text: cellSourceBinding(for: cell.id, fallbackIndex: index),
                        fontSize: appSession.settings.codeFontSize,
                        colorScheme: colorScheme
                    )
                } else {
                    CodeDisplayView(
                        text: cell.source.joined,
                        fontSize: appSession.settings.codeFontSize,
                        colorScheme: colorScheme
                    )
                }
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )
        }
    }

    private func cellSourceBinding(for cellID: String, fallbackIndex index: Int) -> Binding<String> {
        Binding(
            get: { store.notebook?.cells[index].source.joined ?? "" },
            set: { store.updateCellSource(cellID: cellID, source: $0) }
        )
    }

    private func scrollToAnchor(_ anchorID: String, using scrollProxy: ScrollViewProxy) {
        guard let targetCellID = anchorTargets[anchorID] else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            scrollProxy.scrollTo(targetCellID, anchor: .top)
        }
    }

    private func selectCell(_ cell: NotebookCell) {
        if editingCellID != cell.id {
            finishEditingCurrentCell()
        }
        selectedCellID = cell.id
    }

    private func beginEditing(_ cell: NotebookCell) {
        selectedCellID = cell.id
        editingCellID = cell.id
        if cell.cellType == .markdown {
            store.editMarkdown(cell.id)
        }
    }

    private func finishEditingCurrentCell() {
        guard let editingCellID else { return }
        if let cell = store.notebook?.cells.first(where: { $0.id == editingCellID }),
           cell.cellType == .markdown {
            store.previewMarkdown(editingCellID)
        }
        self.editingCellID = nil
    }

    private var addCellButton: some View {
        Button {
            store.appendCell(type: .code)
        } label: {
            Label("Add Cell", systemImage: "plus")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 4)
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
        .background(NotebookTheme.panelFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var primaryActionStrip: some View {
        HStack(spacing: 12) {
            Button("Save") {
                Task { await store.save() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("save-document")

            Button("Run All") {
                Task { await store.runAll() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("run-all")

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
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("notebook-menu")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cellActionMenu(cell: NotebookCell, index: Int) -> some View {
        Menu {
            Menu("Change Type") {
                switch cell.cellType {
                case .code:
                    Button("Markdown") { store.setCellType(.markdown, cellID: cell.id) }
                case .markdown:
                    Button("Code") { store.setCellType(.code, cellID: cell.id) }
                case .raw:
                    Button("Code") { store.setCellType(.code, cellID: cell.id) }
                    Button("Markdown") { store.setCellType(.markdown, cellID: cell.id) }
                }
            }
            Menu("Insert Cell Before") {
                Button("Code") { store.insertCell(type: .code, before: cell.id) }
                Button("Markdown") { store.insertCell(type: .markdown, before: cell.id) }
            }
            Menu("Insert Cell After") {
                Button("Code") { store.insertCell(type: .code, after: cell.id) }
                Button("Markdown") { store.insertCell(type: .markdown, after: cell.id) }
            }
            Button("Run Cell") { Task { await store.runCell(cell.id) } }
            if cell.cellType == .code {
                Button("Run Above") { Task { await store.runAbove(cell.id) } }
                Button("Run All Below") { Task { await store.runAllBelow(cell.id) } }
            }
            if cell.cellType == .markdown {
                Button(store.renderedMarkdownCellIDs.contains(cell.id) ? "Edit Markdown" : "Preview Markdown") {
                    if store.renderedMarkdownCellIDs.contains(cell.id) {
                        store.editMarkdown(cell.id)
                    } else {
                        store.previewMarkdown(cell.id)
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
