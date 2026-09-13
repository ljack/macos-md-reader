import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItemController: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // File ▸ Open Recent is AppKit's own submenu; lift its default cap of 10 entries.
        UserDefaults.standard.register(defaults: ["NSRecentDocumentsLimit": 100])
        NSApp.mainMenu = MenuBuilder.makeMainMenu()
        // Warm the parser + template cache before the first document arrives.
        MarkdownRenderer.warmUp()
        HTMLTemplate.warmUp()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            DefaultHandler.offerToBecomeDefaultIfNeeded()
        }
    }

    // Launched with no file: show the open panel instead of an empty window.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    // Stay resident so re-opening files is instant.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Collects every document window into one tabbed window.
    @objc func mergeAllWindows(_ sender: Any?) {
        WindowActions.mergeAll()
    }

    @objc func closeAllWindows(_ sender: Any?) {
        WindowActions.closeAll()
    }

    // MARK: About / provenance

    @objc func showAbout(_ sender: Any?) {
        let info = BuildInfo.current
        let credits = NSMutableAttributedString()
        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        credits.append(NSAttributedString(string: "Build ", attributes: small))
        var link = small
        link[.link] = info.commitURL
        credits.append(NSAttributedString(string: info.commit, attributes: link))
        credits.append(NSAttributedString(string: " on \(info.branch)\n\(info.buildDate)\n", attributes: small))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: info.version,
            .version: info.build,
            .credits: credits,
        ])
    }

    @objc func copyBuildInfo(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BuildInfo.current.summary, forType: .string)
    }

    @objc func openRepository(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/\(GitHubFeedback.owner)/\(GitHubFeedback.repo)")!)
    }

    @objc func toggleStatusItem(_ sender: Any?) {
        statusItemController?.toggleVisibility(sender)
        (sender as? NSMenuItem)?.state = StatusItemController.isEnabled ? .on : .off
    }

    @objc func makeDefaultViewer(_ sender: Any?) {
        DefaultHandler.makeDefault { error in
            if let error {
                NSAlert(error: error).runModal()
            }
        }
    }
}
