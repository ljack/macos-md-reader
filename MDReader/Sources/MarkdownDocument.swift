import AppKit
import UniformTypeIdentifiers

/// Read-only document. Never marks itself edited, never saves.
final class MarkdownDocument: NSDocument {
    private(set) var text: String = ""
    private var watcher: FileWatcher?

    override class var autosavesInPlace: Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    // MARK: Reading

    override func read(from data: Data, ofType typeName: String) throws {
        text = Self.decode(data)
    }

    private static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        var converted: NSString?
        _ = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        return (converted as String?) ?? String(decoding: data, as: UTF8.self)
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    // MARK: Live reload

    override var fileURL: URL? {
        didSet {
            startWatching()
            if let url = fileURL { RecentFilesStore.record(url) }
        }
    }

    private func startWatching() {
        watcher = nil
        guard let url = fileURL else { return }
        watcher = FileWatcher(url: url) { [weak self] in
            self?.reloadFromDisk(force: false)
        }
    }

    /// Re-reads the file. Returns true when content changed (or `force`).
    @discardableResult
    func reloadFromDisk(force: Bool) -> Bool {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return false }
        let fresh = Self.decode(data)
        guard force || fresh != text else { return false }
        text = fresh
        if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            fileModificationDate = date
        }
        notifyViews(fullReload: force)
        return true
    }

    // NSDocument reverts automatically after coordinated writes; keep the view in sync.
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        notifyViews(fullReload: false)
    }

    private func notifyViews(fullReload: Bool) {
        for wc in windowControllers {
            (wc as? DocumentWindowController)?.previewViewController.contentDidChange(fullReload: fullReload)
        }
    }

    // MARK: Actions

    @objc func revealInFinder(_ sender: Any?) {
        guard let url = fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func openFolderInFinder(_ sender: Any?) {
        guard let dir = fileURL?.deletingLastPathComponent() else { return }
        NSWorkspace.shared.open(dir)
    }

    @objc func openInTerminal(_ sender: Any?) {
        openDirectory(inAppWithBundleID: "com.apple.Terminal")
    }

    @objc func openInITerm(_ sender: Any?) {
        openDirectory(inAppWithBundleID: "com.googlecode.iterm2")
    }

    static var iTermURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2")
    }

    /// Terminal and iTerm2 both open a new window cd'd to a directory handed to them.
    private func openDirectory(inAppWithBundleID bundleID: String) {
        guard let dir = fileURL?.deletingLastPathComponent(),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.open([dir], withApplicationAt: app, configuration: .init()) { _, error in
            if let error { DispatchQueue.main.async { NSAlert(error: error).runModal() } }
        }
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let wc = windowControllers.first as? DocumentWindowController else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        }
        let info = NSPrintInfo(dictionary: printSettings)
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        let op = wc.previewViewController.webView.printOperation(with: info)
        op.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        return op
    }
}
