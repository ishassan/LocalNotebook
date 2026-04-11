import SwiftUI

struct NotebookEditorView: View {
    @Bindable var store: DocumentEditorStore
    @Environment(AppSessionStore.self) private var appSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var renamePromptShown = false
    @State private var renameText = ""
    @State private var exportDocument: ExportFileDocument?
    @State private var exportShown = false
    @State private var selectedCellID: String?
    @State private var editingCellID: String?
    @State private var settingsShown = false
    @State private var packagesShown = false
    @State private var helpShown = false
    @State private var templatePickerShown = false
    @State private var findPanelShown = false
    @State private var replaceModeShown = false
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var searchMatchIDs: [String] = []
    @State private var searchMatchIndex = 0
    @State private var deleteConfirmationShown = false

    private var cells: [NotebookCell] {
        store.notebook?.cells ?? []
    }

    private var cellIDs: [String] {
        cells.map(\.id)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                        notebookCellView(cell: cell, index: index, scrollProxy: scrollProxy)
                    }
                    Color.clear
                        .frame(height: 8)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                floatingControls
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0), Color.black.opacity(0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay(alignment: .top) {
                if findPanelShown {
                    NotebookFindPanel(
                        searchText: $findText,
                        replacementText: $replaceText,
                        isReplaceMode: $replaceModeShown,
                        matchCount: searchMatchIDs.count,
                        currentIndex: searchMatchIDs.isEmpty ? 0 : searchMatchIndex + 1,
                        onPrevious: { advanceSearch(by: -1, using: scrollProxy) },
                        onNext: { advanceSearch(by: 1, using: scrollProxy) },
                        onReplaceCurrent: { replaceCurrent(using: scrollProxy) },
                        onReplaceAll: { replaceAll(using: scrollProxy) },
                        onClose: {
                            findPanelShown = false
                            findText = ""
                            replaceText = ""
                            searchMatchIDs = []
                        }
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }
            }
            .onChange(of: cellIDs) { _, _ in
                if selectedCellID == nil {
                    selectedCellID = cells.first?.id
                } else if let selectedCellID,
                          !cells.contains(where: { $0.id == selectedCellID }) {
                    self.selectedCellID = cells.first?.id
                }
                refreshSearch(using: scrollProxy, preservePosition: true)
            }
            .onChange(of: findText) { _, _ in
                refreshSearch(using: scrollProxy)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        NotebookGlyph()
                            .frame(width: 18, height: 18)
                        Text(store.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .frame(maxWidth: 240)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if editingCellID != nil {
                        Button("Done") {
                            finishEditingCurrentCell()
                        }
                        .fontWeight(.semibold)
                    } else if UITestHarness.isEnabled {
                        Button("Save") {
                            Task { await store.save() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NotebookTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.08, green: 0.10, blue: 0.18))
                        )
                        .overlay(
                            Capsule()
                                .stroke(NotebookTheme.accent.opacity(0.45), lineWidth: 1)
                        )
                        .accessibilityIdentifier("save-document")
                    }

                    Menu {
                        Button("Settings") {
                            settingsShown = true
                        }
                        Button("Help") {
                            helpShown = true
                        }

                        Menu("Run Code") {
                            Button("Run Selected Cell") {
                                runSelectedCell()
                            }
                            Button("Run and Select Next") {
                                runAndSelectNext()
                            }
                            Button("Run All Cells") {
                                Task { await store.runAll() }
                            }
                            Button("Run All Cells Above") {
                                guard let selectedCellID else { return }
                                Task { await store.runAbove(selectedCellID) }
                            }
                            .disabled(selectedCellID == nil)
                            Button("Run All Cells Below") {
                                guard let selectedCellID else { return }
                                Task { await store.runAllBelow(selectedCellID) }
                            }
                            .disabled(selectedCellID == nil)
                            Button("Restart and Run All") {
                                Task { await store.restartAndRunAll() }
                            }
                            Button("Interrupt Kernel") {
                                Task { await store.interruptKernel() }
                            }
                            Button("Restart Kernel") {
                                Task { await store.restartKernel() }
                            }
                        }

                        Button("Cell Templates") {
                            templatePickerShown = true
                        }
                        Button("Package Manager") {
                            packagesShown = true
                        }
                        Button("Find") {
                            replaceModeShown = false
                            findPanelShown = true
                        }
                        Button("Find and Replace") {
                            replaceModeShown = true
                            findPanelShown = true
                        }

                        Divider()

                        Button("Save") {
                            Task { await store.save() }
                        }
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
                        Button("Delete", role: .destructive) {
                            deleteConfirmationShown = true
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.08, green: 0.10, blue: 0.18))
                                .frame(width: 34, height: 34)
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(NotebookTheme.accent)
                        }
                    }
                    .accessibilityIdentifier("notebook-menu")
                }
            }
            .alert("Rename Notebook", isPresented: $renamePromptShown) {
                TextField("Notebook name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    Task { await store.rename(to: renameText) }
                }
            }
            .alert(deleteAlertTitle, isPresented: $deleteConfirmationShown) {
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
            .alert("Error", isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in store.errorMessage = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .confirmationDialog("Cell Templates", isPresented: $templatePickerShown, titleVisibility: .visible) {
                Button("Code Cell") {
                    insertTemplate(type: .code, source: "")
                }
                Button("Markup Text Cell") {
                    insertTemplate(type: .markdown, source: "# Section Title\n\nWrite here.")
                }
                Button("Raw Text Cell") {
                    insertTemplate(type: .raw, source: "Raw content")
                }
                Button("Python Function") {
                    insertTemplate(
                        type: .code,
                        source: """
                        def example_function(value: str) -> None:
                            print(value)
                        """
                    )
                }
                Button("Cancel", role: .cancel) {}
            }
            .fileExporter(
                isPresented: $exportShown,
                document: exportDocument,
                contentType: store.snapshot?.kind.utType ?? .data,
                defaultFilename: store.snapshot?.displayName ?? "Notebook"
            ) { _ in }
            .sheet(isPresented: $settingsShown) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    settingsShown = false
                                }
                            }
                        }
                }
                .environment(appSession)
            }
            .sheet(isPresented: $packagesShown) {
                NavigationStack {
                    PackagesView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    packagesShown = false
                                }
                            }
                        }
                }
                .environment(appSession)
            }
            .sheet(isPresented: $helpShown) {
                NavigationStack {
                    NotebookHelpView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    helpShown = false
                                }
                            }
                        }
                }
            }
        }
    }

    private func notebookCellView(cell: NotebookCell, index: Int, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cellEditorView(cell: cell, index: index, scrollProxy: scrollProxy)

            if !cell.outputs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cell.outputs, id: \.id) { output in
                        OutputRenderer(output: output)
                    }
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(selectedCellID == cell.id ? NotebookTheme.accent : Color.clear)
                .frame(width: 4)
                .padding(.vertical, 6)
        }
        .overlay {
            if activeMatchCellIDs.contains(cell.id) {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(NotebookTheme.accent.opacity(0.45), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(on: cell)
        }
        .contextMenu {
            cellActionMenu(for: cell.id)
        }
        .id(cell.id)
    }

    private var deleteAlertTitle: String {
        "Delete \(store.snapshot?.displayName ?? "Notebook")?"
    }

    @ViewBuilder
    private func cellEditorView(cell: NotebookCell, index: Int, scrollProxy: ScrollViewProxy) -> some View {
        switch cell.cellType {
        case .code:
            codeCellView(cell: cell, index: index)
        case .markdown:
            if editingCellID == cell.id {
                plainEditor(binding: cellSourceBinding(for: cell.id, fallbackIndex: index), minHeight: 120)
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
            if editingCellID == cell.id {
                plainEditor(binding: cellSourceBinding(for: cell.id, fallbackIndex: index), minHeight: 110)
            } else {
                Text(cell.source.joined)
                    .font(.system(size: appSession.settings.notebookTextSize))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func plainEditor(binding: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: binding)
            .scrollContentBackground(.hidden)
            .font(.system(size: appSession.settings.notebookTextSize))
            .foregroundStyle(.white)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.15))
            )
    }

    private func codeCellView(cell: NotebookCell, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In [\(cell.executionCount.map(String.init) ?? " ")]:")
                .font(.custom("Menlo-Regular", size: max(14, appSession.settings.codeFontSize - 1)))
                .foregroundStyle(Color.white.opacity(0.58))

            HStack(alignment: .top, spacing: 12) {
                CodeLineNumberView(
                    text: cell.source.joined,
                    fontSize: appSession.settings.codeFontSize,
                    colorScheme: colorScheme
                )

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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.15))
            )
        }
    }

    private var floatingControls: some View {
        HStack(spacing: 14) {
            Menu {
                addCellMenu
            } label: {
                FloatingCircleLabel(icon: "plus", style: .primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plus")

            Spacer(minLength: 0)

            Menu {
                if let selectedCellID {
                    cellActionMenu(for: selectedCellID)
                }
            } label: {
                FloatingCircleLabel(icon: "bolt.fill", style: .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bolt.fill")
            .disabled(selectedCellID == nil)

            floatingButton(
                icon: "play.fill",
                style: .primary,
                accessibilityIdentifier: UITestHarness.isEnabled ? "run-all" : "play.fill"
            ) {
                if UITestHarness.isEnabled {
                    Task { await store.runAll() }
                } else {
                    runAndSelectNext()
                }
            }
        }
    }

    @ViewBuilder
    private func cellActionMenu(for cellID: String) -> some View {
        Menu {
            cellTypeButton(title: "Code Cell", type: .code, cellID: cellID)
            cellTypeButton(title: "Markup Text Cell", type: .markdown, cellID: cellID)
            cellTypeButton(title: "Raw Text Cell", type: .raw, cellID: cellID)
        } label: {
            Label(currentCellTypeTitle(for: cellID), systemImage: currentCellTypeIcon(for: cellID))
        }

        Button {
            let replacementSelection = store.previousCellID(before: cellID) ?? store.nextCellID(after: cellID)
            store.cutCell(cellID)
            selectedCellID = replacementSelection
        } label: {
            Label("Cut", systemImage: "scissors")
        }

        Button {
            store.copyCell(cellID)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
            _ = store.pasteCell(into: cellID)
            selectedCellID = cellID
        } label: {
            Label("Paste", systemImage: "clipboard")
        }

        Button {
            selectedCellID = store.moveCellUp(cellID)
        } label: {
            Label("Move Up", systemImage: "arrow.up.to.line")
        }
        .disabled(store.previousCellID(before: cellID) == nil)

        Button {
            selectedCellID = store.moveCellDown(cellID)
        } label: {
            Label("Move Down", systemImage: "arrow.down.to.line")
        }
        .disabled(store.nextCellID(after: cellID) == nil)

        Button {
            selectedCellID = store.mergeCellAbove(cellID)
        } label: {
            Text("Merge Above")
        }
        .disabled(store.previousCellID(before: cellID) == nil)

        Button {
            selectedCellID = store.mergeCellBelow(cellID)
        } label: {
            Text("Merge Below")
        }
        .disabled(store.nextCellID(after: cellID) == nil)

        Button(role: .destructive) {
            let replacementSelection = store.previousCellID(before: cellID) ?? store.nextCellID(after: cellID)
            store.deleteCell(cellID)
            selectedCellID = replacementSelection
        } label: {
            Label("Delete Cell", systemImage: "trash")
        }

        Button {
            selectedCellID = store.undoDelete()
        } label: {
            Label("Undo Cell Deletion", systemImage: "arrow.uturn.backward")
        }
    }

    private func cellTypeButton(title: String, type: NotebookCellType, cellID: String) -> some View {
        Button {
            store.setCellType(type, cellID: cellID)
            selectedCellID = cellID
        } label: {
            if cells.first(where: { $0.id == cellID })?.cellType == type {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func handleTap(on cell: NotebookCell) {
        if selectedCellID == cell.id {
            beginEditing(cell)
        } else {
            if editingCellID != cell.id {
                finishEditingCurrentCell()
            }
            selectedCellID = cell.id
        }
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
        if let cell = cells.first(where: { $0.id == editingCellID }),
           cell.cellType == .markdown {
            store.previewMarkdown(editingCellID)
        }
        self.editingCellID = nil
    }

    private func insertTemplate(type: NotebookCellType, source: String) {
        finishEditingCurrentCell()
        if let selectedCellID {
            store.insertCell(type: type, after: selectedCellID)
            if let newCellID = store.nextCellID(after: selectedCellID) {
                if !source.isEmpty {
                    store.updateCellSource(cellID: newCellID, source: source)
                }
                self.selectedCellID = newCellID
                beginEditingIfNeeded(cellID: newCellID)
            }
        } else {
            store.appendCell(type: type)
            if let newCellID = cells.last?.id ?? store.notebook?.cells.last?.id {
                if !source.isEmpty {
                    store.updateCellSource(cellID: newCellID, source: source)
                }
                selectedCellID = newCellID
                beginEditingIfNeeded(cellID: newCellID)
            }
        }
    }

    private func beginEditingIfNeeded(cellID: String) {
        guard let cell = cells.first(where: { $0.id == cellID }) ?? store.notebook?.cells.first(where: { $0.id == cellID }) else { return }
        beginEditing(cell)
    }

    private func runSelectedCell() {
        guard let selectedCellID else { return }
        Task { await store.runCell(selectedCellID) }
    }

    private func runAndSelectNext() {
        guard let selectedCellID else {
            Task { await store.runAll() }
            return
        }
        Task {
            let nextID = await store.runAndSelectNext(selectedCellID)
            self.selectedCellID = nextID ?? selectedCellID
        }
    }

    private func refreshSearch(using scrollProxy: ScrollViewProxy, preservePosition: Bool = false) {
        searchMatchIDs = store.matchingCellIDs(for: findText)
        guard !searchMatchIDs.isEmpty else {
            searchMatchIndex = 0
            return
        }
        if preservePosition, searchMatchIndex < searchMatchIDs.count {
            scrollToCell(searchMatchIDs[searchMatchIndex], using: scrollProxy)
            return
        }
        searchMatchIndex = min(searchMatchIndex, searchMatchIDs.count - 1)
        scrollToCell(searchMatchIDs[searchMatchIndex], using: scrollProxy)
    }

    private func advanceSearch(by offset: Int, using scrollProxy: ScrollViewProxy) {
        guard !searchMatchIDs.isEmpty else { return }
        let count = searchMatchIDs.count
        searchMatchIndex = (searchMatchIndex + offset + count) % count
        scrollToCell(searchMatchIDs[searchMatchIndex], using: scrollProxy)
    }

    private func replaceCurrent(using scrollProxy: ScrollViewProxy) {
        guard !searchMatchIDs.isEmpty else { return }
        let cellID = searchMatchIDs[searchMatchIndex]
        store.replaceFirstMatch(of: findText, with: replaceText, in: cellID)
        refreshSearch(using: scrollProxy)
    }

    private func replaceAll(using scrollProxy: ScrollViewProxy) {
        _ = store.replaceAllMatches(of: findText, with: replaceText)
        refreshSearch(using: scrollProxy)
    }

    private func scrollToCell(_ cellID: String, using scrollProxy: ScrollViewProxy) {
        selectedCellID = cellID
        withAnimation(.easeInOut(duration: 0.18)) {
            scrollProxy.scrollTo(cellID, anchor: .center)
        }
    }

    private var activeMatchCellIDs: Set<String> {
        Set(searchMatchIDs)
    }

    private var anchorTargets: [String: String] {
        cells.reduce(into: [String: String]()) { result, cell in
            for anchorID in MarkdownHTMLRenderer.anchorIDs(in: cell.source.joined) {
                result[anchorID] = cell.id
            }
        }
    }

    private func cellSourceBinding(for cellID: String, fallbackIndex index: Int) -> Binding<String> {
        Binding(
            get: { cells.indices.contains(index) ? cells[index].source.joined : "" },
            set: { store.updateCellSource(cellID: cellID, source: $0) }
        )
    }

    private func scrollToAnchor(_ anchorID: String, using scrollProxy: ScrollViewProxy) {
        guard let targetCellID = anchorTargets[anchorID] else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            scrollProxy.scrollTo(targetCellID, anchor: .top)
        }
    }

    private func floatingButton(
        icon: String,
        style: FloatingCircleLabel.Style,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            FloatingCircleLabel(icon: icon, style: style)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var addCellMenu: some View {
        addCellButton(title: "Add Code Cell", icon: "curlybraces", type: .code)
        addCellButton(title: "Add Markup Text Cell", icon: "chevron.left.forwardslash.chevron.right", type: .markdown)
        addCellButton(title: "Add Raw Text Cell", icon: "a.square", type: .raw)
    }

    private func addCellButton(title: String, icon: String, type: NotebookCellType) -> some View {
        Button {
            insertTemplate(type: type, source: "")
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func currentCellTypeTitle(for cellID: String) -> String {
        guard let type = cells.first(where: { $0.id == cellID })?.cellType ?? store.notebook?.cells.first(where: { $0.id == cellID })?.cellType else {
            return "Cell Type"
        }
        return cellTypeTitle(for: type)
    }

    private func currentCellTypeIcon(for cellID: String) -> String {
        guard let type = cells.first(where: { $0.id == cellID })?.cellType ?? store.notebook?.cells.first(where: { $0.id == cellID })?.cellType else {
            return "square"
        }
        return cellTypeIcon(for: type)
    }

    private func cellTypeTitle(for type: NotebookCellType) -> String {
        switch type {
        case .code:
            "Code Cell"
        case .markdown:
            "Markup Text Cell"
        case .raw:
            "Raw Text Cell"
        }
    }

    private func cellTypeIcon(for type: NotebookCellType) -> String {
        switch type {
        case .code:
            "curlybraces"
        case .markdown:
            "chevron.left.forwardslash.chevron.right"
        case .raw:
            "a.square"
        }
    }
}

private struct FloatingCircleLabel: View {
    enum Style {
        case primary
        case secondary
    }

    let icon: String
    var style: Style = .primary

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 46, height: 46)
            .background(backgroundColor, in: Circle())
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 4)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            NotebookTheme.accent
        case .secondary:
            Color(red: 0.10, green: 0.11, blue: 0.15)
        }
    }

    private var iconColor: Color {
        switch style {
        case .primary:
            .white
        case .secondary:
            NotebookTheme.accent
        }
    }
}

private struct NotebookGlyph: View {
    var body: some View {
        Image("JupyterMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 18, height: 18)
    }
}

private struct NotebookFindPanel: View {
    @Binding var searchText: String
    @Binding var replacementText: String
    @Binding var isReplaceMode: Bool

    let matchCount: Int
    let currentIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReplaceCurrent: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Find in notebook", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text(matchLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if isReplaceMode {
                TextField("Replace", text: $replacementText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 10) {
                Button("Previous", action: onPrevious)
                    .buttonStyle(.bordered)
                Button("Next", action: onNext)
                    .buttonStyle(.borderedProminent)

                if isReplaceMode {
                    Button("Replace", action: onReplaceCurrent)
                        .buttonStyle(.bordered)
                    Button("Replace All", action: onReplaceAll)
                        .buttonStyle(.bordered)
                }
            }
            .tint(NotebookTheme.accent)
        }
        .padding(14)
        .background(Color(red: 0.10, green: 0.10, blue: 0.11), in: RoundedRectangle(cornerRadius: 16))
    }

    private var matchLabel: String {
        guard matchCount > 0 else { return "0" }
        return "\(currentIndex)/\(matchCount)"
    }
}

private struct NotebookHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Help")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                helpBlock(
                    title: "Editing",
                    text: "Tap a cell to select it. Tap the same cell again to edit. Use Done to switch markdown cells back to preview."
                )
                helpBlock(
                    title: "Running Code",
                    text: "The plus button inserts a new cell. The bolt button opens cell actions and type changes for the selected cell. The play button runs and advances."
                )
                helpBlock(
                    title: "Managing Cells",
                    text: "Use the cell action menu to change cell type, move cells, merge cells, or restore the last deleted cell."
                )
                helpBlock(
                    title: "Packages",
                    text: "Open Package Manager from the menu to browse bundled Python packages and pin frequently used ones."
                )
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func helpBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }
}
