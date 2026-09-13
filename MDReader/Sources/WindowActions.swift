import AppKit

enum WindowActions {
    static var documentWindows: [NSWindow] {
        NSApp.windows.filter { $0.windowController is DocumentWindowController && $0.isVisible }
    }

    /// Gathers all document windows as tabs of the frontmost one (like Finder's Merge All Windows).
    static func mergeAll() {
        let windows = documentWindows
        guard windows.count > 1 else { return }
        // Prefer the key window as the host so the user's current document stays selected.
        let host = windows.first(where: { $0.isKeyWindow }) ?? windows[0]
        for window in windows where window !== host && window.tabGroup !== host.tabGroup {
            host.addTabbedWindow(window, ordered: .above)
        }
        host.makeKeyAndOrderFront(nil)
    }

    static func closeAll() {
        NSDocumentController.shared.closeAllDocuments(withDelegate: nil, didCloseAllSelector: nil, contextInfo: nil)
    }
}
