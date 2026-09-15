import AppKit

/// Menu bar icon: quick access to the last 100 Markdown files plus Finder / Terminal shortcuts
/// for the frontmost document.
final class StatusItemController: NSObject, NSMenuDelegate {
    static let showKey = "showStatusItem"
    private static let inlineLimit = 25

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: showKey) as? Bool ?? true
    }

    override init() {
        super.init()
        menu.delegate = self
        applyPreference()
    }

    // MARK: Show / hide

    func applyPreference() {
        if Self.isEnabled { install() } else { remove() }
    }

    @objc func toggleVisibility(_ sender: Any?) {
        UserDefaults.standard.set(!Self.isEnabled, forKey: Self.showKey)
        applyPreference()
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "MD Reader")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "MD Reader — recent Markdown files"
        item.menu = menu
        statusItem = item
    }

    private func remove() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let recents = RecentFilesStore.existingURLs
        if recents.isEmpty {
            let empty = menu.addItem(withTitle: "No Recent Files", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        } else {
            for url in recents.prefix(Self.inlineLimit) { addFileItems(for: url, to: menu) }
            if recents.count > Self.inlineLimit {
                let more = menu.addItem(withTitle: "More…", action: nil, keyEquivalent: "")
                let moreMenu = NSMenu(title: "More")
                for url in recents.dropFirst(Self.inlineLimit) { addFileItems(for: url, to: moreMenu) }
                more.submenu = moreMenu
            }
        }

        menu.addItem(.separator())
        let open = menu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "")
        open.target = self
        let clear = menu.addItem(withTitle: "Clear Recent", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !recents.isEmpty

        if let document = NSDocumentController.shared.currentDocument as? MarkdownDocument,
           let fileURL = document.fileURL {
            menu.addItem(.separator())
            let header = menu.addItem(withTitle: fileURL.lastPathComponent, action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.image = MenuIcons.icon(forFile: fileURL.path)
            addDocumentAction("Reveal in Finder", #selector(MarkdownDocument.revealInFinder(_:)), document, menu)
            addDocumentAction("Open Folder in Finder", #selector(MarkdownDocument.openFolderInFinder(_:)), document, menu)
            addDocumentAction("Open in Terminal", #selector(MarkdownDocument.openInTerminal(_:)), document, menu)
            if MarkdownDocument.iTermURL != nil {
                addDocumentAction("Open in iTerm2", #selector(MarkdownDocument.openInITerm(_:)), document, menu)
            }
            addDocumentAction("Go to Terminal Session", #selector(MarkdownDocument.goToTerminalSession(_:)), document, menu)
        }

        menu.addItem(.separator())
        let merge = menu.addItem(withTitle: "Merge All Windows", action: #selector(AppDelegate.mergeAllWindows(_:)), keyEquivalent: "")
        merge.target = NSApp.delegate
        merge.isEnabled = WindowActions.documentWindows.count > 1
        let closeAll = menu.addItem(withTitle: "Close All Windows", action: #selector(AppDelegate.closeAllWindows(_:)), keyEquivalent: "")
        closeAll.target = NSApp.delegate
        closeAll.isEnabled = !WindowActions.documentWindows.isEmpty

        menu.addItem(.separator())
        let toggle = menu.addItem(withTitle: "Show in Menu Bar", action: #selector(toggleVisibility(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.state = Self.isEnabled ? .on : .off
        let quit = menu.addItem(withTitle: "Quit MD Reader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
    }

    private func addDocumentAction(_ title: String, _ selector: Selector, _ document: MarkdownDocument, _ menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: "")
        item.target = document
    }

    /// Primary item opens the file; ⌥-alternate reveals it in Finder.
    private func addFileItems(for url: URL, to menu: NSMenu) {
        let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        let icon = MenuIcons.icon(forFile: url.path)

        let open = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = url
        open.image = icon
        open.toolTip = url.path
        open.attributedTitle = Self.attributedTitle(name: url.lastPathComponent, folder: folder)
        menu.addItem(open)

        let reveal = NSMenuItem(title: "Reveal “\(url.lastPathComponent)” in Finder",
                                action: #selector(revealRecent(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = url
        reveal.image = icon
        reveal.isAlternate = true
        reveal.keyEquivalentModifierMask = .option
        menu.addItem(reveal)
    }

    private static func attributedTitle(name: String, folder: String) -> NSAttributedString {
        let title = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ])
        title.append(NSAttributedString(string: "  \(folder)", attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

    // MARK: Actions

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSAlert(error: error).runModal() }
        }
    }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openDocument(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSDocumentController.shared.openDocument(nil)
    }

    @objc private func clearRecent(_ sender: Any?) {
        RecentFilesStore.clear()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
}
