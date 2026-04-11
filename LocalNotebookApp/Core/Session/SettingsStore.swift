import Foundation
import Observation
import SwiftUI

enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

extension SettingsStore {
    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    var theme: AppTheme {
        didSet { persist() }
    }
    var codeFontSize: Double {
        didSet { persist() }
    }
    var notebookTextSize: Double {
        didSet { persist() }
    }
    var autosaveEnabled: Bool {
        didSet { persist() }
    }
    var openImportedFilesAsCopy: Bool {
        didSet { persist() }
    }
    var clearOutputsOnDuplicate: Bool {
        didSet { persist() }
    }
    var clearOutputsOnExport: Bool {
        didSet { persist() }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "settingsStore"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            theme = persisted.theme
            codeFontSize = persisted.codeFontSize
            notebookTextSize = persisted.notebookTextSize
            autosaveEnabled = persisted.autosaveEnabled
            openImportedFilesAsCopy = persisted.openImportedFilesAsCopy
            clearOutputsOnDuplicate = persisted.clearOutputsOnDuplicate
            clearOutputsOnExport = persisted.clearOutputsOnExport
        } else {
            theme = .system
            codeFontSize = 15
            notebookTextSize = 16
            autosaveEnabled = true
            openImportedFilesAsCopy = true
            clearOutputsOnDuplicate = false
            clearOutputsOnExport = false
        }
    }

    private func persist() {
        let persisted = Persisted(
            theme: theme,
            codeFontSize: codeFontSize,
            notebookTextSize: notebookTextSize,
            autosaveEnabled: autosaveEnabled,
            openImportedFilesAsCopy: openImportedFilesAsCopy,
            clearOutputsOnDuplicate: clearOutputsOnDuplicate,
            clearOutputsOnExport: clearOutputsOnExport
        )
        userDefaults.set(try? JSONEncoder().encode(persisted), forKey: storageKey)
    }

    private struct Persisted: Codable {
        var theme: AppTheme
        var codeFontSize: Double
        var notebookTextSize: Double
        var autosaveEnabled: Bool
        var openImportedFilesAsCopy: Bool
        var clearOutputsOnDuplicate: Bool
        var clearOutputsOnExport: Bool
    }
}
