import Foundation

final class SecurityScopedBookmarkStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey = "securityScopedBookmarks"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func saveBookmark(for key: String, url: URL) throws {
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        var all = userDefaults.dictionary(forKey: storageKey) as? [String: Data] ?? [:]
        all[key] = bookmark
        userDefaults.set(all, forKey: storageKey)
    }

    func resolvedURL(for key: String) -> URL? {
        guard let all = userDefaults.dictionary(forKey: storageKey) as? [String: Data],
              let data = all[key] else {
            return nil
        }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
}
