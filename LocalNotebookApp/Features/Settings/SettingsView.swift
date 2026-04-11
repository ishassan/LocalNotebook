import SwiftUI

struct SettingsView: View {
    @Environment(AppSessionStore.self) private var appSession

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(get: { appSession.settings.theme }, set: { appSession.settings.theme = $0 })) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue.capitalized).tag(theme)
                    }
                }
                LabeledContent("Code Font") {
                    Text("\(Int(appSession.settings.codeFontSize)) pt")
                }
                Slider(value: Binding(get: { appSession.settings.codeFontSize }, set: { appSession.settings.codeFontSize = $0 }), in: 12...22, step: 1)
                LabeledContent("Notebook Text") {
                    Text("\(Int(appSession.settings.notebookTextSize)) pt")
                }
                Slider(value: Binding(get: { appSession.settings.notebookTextSize }, set: { appSession.settings.notebookTextSize = $0 }), in: 12...24, step: 1)
            }

            Section("Storage") {
                Toggle("Autosave", isOn: Binding(get: { appSession.settings.autosaveEnabled }, set: { appSession.settings.autosaveEnabled = $0 }))
                Toggle("Open imported files as copy", isOn: Binding(get: { appSession.settings.openImportedFilesAsCopy }, set: { appSession.settings.openImportedFilesAsCopy = $0 }))
                Toggle("Clear outputs on duplicate", isOn: Binding(get: { appSession.settings.clearOutputsOnDuplicate }, set: { appSession.settings.clearOutputsOnDuplicate = $0 }))
                Toggle("Clear outputs on export", isOn: Binding(get: { appSession.settings.clearOutputsOnExport }, set: { appSession.settings.clearOutputsOnExport = $0 }))
            }
        }
        .navigationTitle("Settings")
    }
}
