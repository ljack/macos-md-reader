import AppKit

enum MenuBuilder {
    private static let openWithMenuDelegate = OpenWithMenuDelegate()

    static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        // MARK: App
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MD Reader", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Copy Build Info", action: #selector(AppDelegate.copyBuildInfo(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Make Default Markdown Viewer…",
                        action: #selector(AppDelegate.makeDefaultViewer(_:)), keyEquivalent: "")
        let showStatus = appMenu.addItem(withTitle: "Show in Menu Bar",
                                         action: #selector(AppDelegate.toggleStatusItem(_:)), keyEquivalent: "")
        showStatus.state = StatusItemController.isEnabled ? .on : .off
        appMenu.addItem(.separator())
        let services = appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu()
        NSApp.servicesMenu = services.submenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MD Reader", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MD Reader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, title: "MD Reader"))

        // MARK: File
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        // AppKit inserts its own "Open Recent" submenu after "Open…" automatically.
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let closeAll = file.addItem(withTitle: "Close All Windows", action: #selector(AppDelegate.closeAllWindows(_:)), keyEquivalent: "W")
        closeAll.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(.separator())
        file.addItem(withTitle: "Reveal in Finder", action: #selector(MarkdownDocument.revealInFinder(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Open Folder in Finder", action: #selector(MarkdownDocument.openFolderInFinder(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Open in Terminal", action: #selector(MarkdownDocument.openInTerminal(_:)), keyEquivalent: "")
        if MarkdownDocument.iTermURL != nil {
            file.addItem(withTitle: "Open in iTerm2", action: #selector(MarkdownDocument.openInITerm(_:)), keyEquivalent: "")
        }
        let openWith = file.addItem(withTitle: "Open With", action: nil, keyEquivalent: "")
        let openWithMenu = NSMenu(title: "Open With")
        openWithMenu.delegate = openWithMenuDelegate
        openWith.submenu = openWithMenu
        file.addItem(.separator())
        file.addItem(withTitle: "Print…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")
        main.addItem(submenu(file, title: "File"))

        // MARK: Edit
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Find…", action: #selector(PreviewViewController.showFind(_:)), keyEquivalent: "f")
        edit.addItem(withTitle: "Find Next", action: #selector(PreviewViewController.findNext(_:)), keyEquivalent: "g")
        let findPrev = edit.addItem(withTitle: "Find Previous",
                                    action: #selector(PreviewViewController.findPrevious(_:)), keyEquivalent: "g")
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        main.addItem(submenu(edit, title: "Edit"))

        // MARK: View
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Reload", action: #selector(PreviewViewController.reloadDocument(_:)), keyEquivalent: "r")
        view.addItem(.separator())
        view.addItem(withTitle: "Actual Size", action: #selector(PreviewViewController.actualSize(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "Zoom In", action: #selector(PreviewViewController.zoomIn(_:)), keyEquivalent: "=")
        view.addItem(withTitle: "Zoom Out", action: #selector(PreviewViewController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(.separator())
        let fullScreen = view.addItem(withTitle: "Enter Full Screen",
                                      action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        main.addItem(submenu(view, title: "View"))

        // MARK: Window
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        let prevTab = window.addItem(withTitle: "Show Previous Tab",
                                     action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "\t")
        prevTab.keyEquivalentModifierMask = [.control, .shift]
        let nextTab = window.addItem(withTitle: "Show Next Tab",
                                     action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "\t")
        nextTab.keyEquivalentModifierMask = [.control]
        window.addItem(withTitle: "Move Tab to New Window", action: #selector(NSWindow.moveTabToNewWindow(_:)), keyEquivalent: "")
        let merge = window.addItem(withTitle: "Merge All Windows", action: #selector(AppDelegate.mergeAllWindows(_:)), keyEquivalent: "m")
        merge.keyEquivalentModifierMask = [.command, .option]
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        main.addItem(submenu(window, title: "Window"))
        NSApp.windowsMenu = window

        // MARK: Help
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Send Feedback…", action: #selector(DocumentWindowController.sendFeedback(_:)), keyEquivalent: "")
        help.addItem(withTitle: "Report a Bug…", action: #selector(DocumentWindowController.reportBug(_:)), keyEquivalent: "")
        help.addItem(withTitle: "Suggest an Idea…", action: #selector(DocumentWindowController.suggestIdea(_:)), keyEquivalent: "")
        help.addItem(.separator())
        help.addItem(withTitle: "MD Reader on GitHub", action: #selector(AppDelegate.openRepository(_:)), keyEquivalent: "")
        main.addItem(submenu(help, title: "Help"))
        NSApp.helpMenu = help

        return main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

// MARK: - Open With

final class OpenWithMenuDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let fileURL = (NSDocumentController.shared.currentDocument as? MarkdownDocument)?.fileURL else {
            menu.addItem(withTitle: "No Document", action: nil, keyEquivalent: "")
            return
        }
        let me = Bundle.main.bundleURL.standardizedFileURL
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
            .filter { $0.standardizedFileURL != me }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        if apps.isEmpty {
            menu.addItem(withTitle: "No Applications", action: nil, keyEquivalent: "")
            return
        }
        for app in apps {
            let name = (app.deletingPathExtension().lastPathComponent)
            let item = NSMenuItem(title: name, action: #selector(openWith(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [fileURL, app]
            item.image = MenuIcons.icon(forFile: app.path)
            menu.addItem(item)
        }
    }

    @objc private func openWith(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [URL], pair.count == 2 else { return }
        NSWorkspace.shared.open([pair[0]], withApplicationAt: pair[1], configuration: .init()) { _, error in
            if let error { DispatchQueue.main.async { NSAlert(error: error).runModal() } }
        }
    }
}

enum MenuIcons {
    static func icon(forFile path: String) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
