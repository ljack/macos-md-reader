import Foundation

/// Our own recent-files list. `NSDocumentController.recentDocumentURLs` is capped by the
/// system preference (~10); this keeps the last 100 plain paths (app is not sandboxed).
enum RecentFilesStore {
    static let maxCount = 100
    static let changed = Notification.Name("MDReader.recentFilesChanged")
    private static let key = "recentFilePaths"

    static var urls: [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// Entries whose files still exist on disk.
    static var existingURLs: [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func record(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > maxCount { paths.removeLast(paths.count - maxCount) }
        UserDefaults.standard.set(paths, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
