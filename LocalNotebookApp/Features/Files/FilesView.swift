import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @Environment(AppSessionStore.self) private var appSession

    @State private var importerShown = false
    @State private var selectedDocumentIDs: Set<UUID> = []
    @State private var deleteConfirmationShown = false

    private var isSelectionMode: Bool {
        !selectedDocumentIDs.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                browseHeader
                quickActionGrid
                documentSection(title: "Local Documents", documents: appSession.documents)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(NotebookTheme.background(for: .dark).ignoresSafeArea())
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if isSelectionMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        selectedDocumentIDs.removeAll()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", role: .destructive) {
                        deleteConfirmationShown = true
                    }
                }
            }
        }
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
        .alert(deleteAlertTitle, isPresented: $deleteConfirmationShown) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteSelectedDocuments() }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var browseHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local notebooks, scripts, and notes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                statusPill(title: "\(appSession.documents.count)", subtitle: "documents")
                statusPill(title: "\(appSession.recentsStore.documents.count)", subtitle: "recent")
            }
        }
    }

    private var quickActionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                actionCard(
                    title: "New Notebook",
                    subtitle: "Start with a markdown intro and code cell.",
                    systemImage: "plus.rectangle.on.folder.fill"
                ) {
                    Task { _ = await appSession.createNotebook() }
                }

                actionCard(
                    title: "New Script",
                    subtitle: "Create a Python file in app storage.",
                    systemImage: "curlybraces.square.fill"
                ) {
                    Task { _ = await appSession.createTextDocument(kind: .python) }
                }

                actionCard(
                    title: "Import File",
                    subtitle: "Bring in notebooks, Python, Markdown, or text.",
                    systemImage: "square.and.arrow.down.fill"
                ) {
                    importerShown = true
                }

                actionCard(
                    title: "Open Settings",
                    subtitle: "Adjust fonts, autosave, and export behavior.",
                    systemImage: "gearshape.fill"
                ) {
                    appSession.selectedTab = AppTab.settings.rawValue
                }
            }

            if UITestHarness.isEnabled {
                Button {
                    Task { await importFixture(named: "UITestNotebook", ext: "ipynb") }
                } label: {
                    Label("Import Sample Notebook", systemImage: "testtube.2")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(NotebookTheme.panelFill(for: .dark), in: RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityIdentifier("import-sample-notebook")
            }
        }
    }

    private func documentSection(title: String, documents: [DocumentSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                if isSelectionMode {
                    Text("\(selectedDocumentIDs.count) selected")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(NotebookTheme.accent)
                }
            }

            if documents.isEmpty {
                ContentUnavailableView(
                    "No Files Yet",
                    systemImage: "folder.badge.plus",
                    description: Text("Create a notebook or import one from Files.")
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(NotebookTheme.panelFill(for: .dark), in: RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(spacing: 12) {
                    ForEach(documents) { snapshot in
                        DocumentCard(
                            snapshot: snapshot,
                            isSelecting: isSelectionMode,
                            isSelected: selectedDocumentIDs.contains(snapshot.id)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                        .onTapGesture {
                            handleDocumentTap(snapshot)
                        }
                        .onLongPressGesture {
                            beginSelection(with: snapshot.id)
                        }
                        .accessibilityIdentifier("document-\(snapshot.displayName)")
                    }
                }
            }
        }
    }

    private func actionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(NotebookTheme.accent)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private func statusPill(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(subtitle.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    private func importFixture(named: String, ext: String) async {
        guard let url = Bundle.main.url(forResource: named, withExtension: ext, subdirectory: "SampleNotebooks") else { return }
        _ = await appSession.importDocument(from: url)
    }

    private var deleteAlertTitle: String {
        selectedDocumentIDs.count == 1 ? "Delete Selected File?" : "Delete \(selectedDocumentIDs.count) Selected Files?"
    }

    private func handleDocumentTap(_ snapshot: DocumentSnapshot) {
        if isSelectionMode {
            toggleSelection(for: snapshot.id)
        } else {
            appSession.filesNavigationPath.append(snapshot.id)
        }
    }

    private func beginSelection(with documentID: UUID) {
        selectedDocumentIDs.insert(documentID)
    }

    private func toggleSelection(for documentID: UUID) {
        if selectedDocumentIDs.contains(documentID) {
            selectedDocumentIDs.remove(documentID)
        } else {
            selectedDocumentIDs.insert(documentID)
        }
    }

    private func deleteSelectedDocuments() async {
        let deleted = await appSession.deleteDocuments(ids: selectedDocumentIDs)
        if deleted {
            selectedDocumentIDs.removeAll()
        }
    }
}

struct DocumentCard: View {
    let snapshot: DocumentSnapshot
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? NotebookTheme.accent : Color.white.opacity(0.28))
            }

            Image(systemName: snapshot.kind.iconName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(NotebookTheme.accent)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(snapshot.kind.title.uppercased())
                    Text(snapshot.lastOpenedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isSelected ? NotebookTheme.accent.opacity(0.18) : Color.white.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? NotebookTheme.accent.opacity(0.75) : .clear, lineWidth: 1)
        }
    }
}
