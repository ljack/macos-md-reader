import AppKit

final class DocumentWindowController: NSWindowController {
    let previewViewController: PreviewViewController

    init(document: MarkdownDocument) {
        previewViewController = PreviewViewController(document: document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true)
        window.contentViewController = previewViewController
        window.minSize = NSSize(width: 380, height: 260)
        window.backgroundColor = .textBackgroundColor
        window.isReleasedWhenClosed = false
        window.tabbingMode = .automatic
        window.tabbingIdentifier = "MDReaderDocument"
        super.init(window: window)
        shouldCascadeWindows = true
        windowFrameAutosaveName = "MDReaderDocumentWindow"

        let toolbar = NSToolbar(identifier: "MDReaderToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    private var feedbackSheet: FeedbackSheet?

    @objc func sendFeedback(_ sender: Any?) {
        presentFeedback(kind: .feedback)
    }

    @objc func reportBug(_ sender: Any?) { presentFeedback(kind: .bug) }
    @objc func suggestIdea(_ sender: Any?) { presentFeedback(kind: .idea) }

    private func presentFeedback(kind: FeedbackKind) {
        guard let window, feedbackSheet == nil else { return }
        let sheet = FeedbackSheet(documentURL: (document as? MarkdownDocument)?.fileURL, initialKind: kind)
        feedbackSheet = sheet
        window.beginSheet(sheet.window!) { [weak self] _ in self?.feedbackSheet = nil }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Toolbar

extension DocumentWindowController: NSToolbarDelegate {
    private static let feedbackItem = NSToolbarItem.Identifier("feedback")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.feedbackItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.feedbackItem else { return nil }
        let menu = NSMenu()
        for kind in FeedbackKind.allCases {
            let selector: Selector
            switch kind {
            case .bug: selector = #selector(reportBug(_:))
            case .feedback: selector = #selector(sendFeedback(_:))
            case .idea: selector = #selector(suggestIdea(_:))
            }
            let item = NSMenuItem(title: "\(kind.title)…", action: selector, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind.title)
            item.target = self
            menu.addItem(item)
        }
        let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Feedback"
        item.paletteLabel = "Feedback"
        item.toolTip = "Report a bug, send feedback, or record an idea on GitHub"
        item.image = NSImage(systemSymbolName: "bubble.left.and.exclamationmark.bubble.right",
                             accessibilityDescription: "Feedback")
        item.menu = menu
        item.showsIndicator = true
        return item
    }
}
