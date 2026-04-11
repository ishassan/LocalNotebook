import SwiftUI

struct PackagesView: View {
    @Environment(AppSessionStore.self) private var appSession

    @State private var searchText = ""
    @State private var selectedSegment: PythonPackage.Segment = .all

    private var filteredPackages: [PythonPackage] {
        PythonPackageCatalog.bundled
            .filter { package in
                switch selectedSegment {
                case .all:
                    true
                case .pinned:
                    appSession.settings.pinnedPackageNames.contains(package.name)
                case .user:
                    package.isUserVisible
                }
            }
            .filter { package in
                guard !searchText.isEmpty else { return true }
                return package.name.localizedCaseInsensitiveContains(searchText)
                    || package.summary.localizedCaseInsensitiveContains(searchText)
            }
    }

    var body: some View {
        VStack(spacing: 16) {
            searchField
            segmentPicker
            packageList
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(NotebookTheme.background(for: .dark).ignoresSafeArea())
        .navigationTitle("Packages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search Packages", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var segmentPicker: some View {
        Picker("Packages", selection: $selectedSegment) {
            ForEach(PythonPackage.Segment.allCases) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
    }

    private var packageList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredPackages) { package in
                    PackageRow(
                        package: package,
                        isPinned: appSession.settings.pinnedPackageNames.contains(package.name)
                    ) {
                        togglePinned(package)
                    }
                }
            }
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
        }
        .overlay {
            if filteredPackages.isEmpty {
                ContentUnavailableView(
                    "No Packages Found",
                    systemImage: "cube.transparent",
                    description: Text("Try a different package filter or search term.")
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private func togglePinned(_ package: PythonPackage) {
        if appSession.settings.pinnedPackageNames.contains(package.name) {
            appSession.settings.pinnedPackageNames.remove(package.name)
        } else {
            appSession.settings.pinnedPackageNames.insert(package.name)
        }
    }
}

private struct PackageRow: View {
    let package: PythonPackage
    let isPinned: Bool
    let onPinToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cube.box.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.84, green: 0.67, blue: 0.43))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(package.version)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Button(action: onPinToggle) {
                        Image(systemName: isPinned ? "star.fill" : "star")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isPinned ? NotebookTheme.accent : Color.white.opacity(0.52))
                    }
                    .buttonStyle(.plain)
                }

                Text(package.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.leading, 40)
        }
    }
}
