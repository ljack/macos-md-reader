import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItemController: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
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
