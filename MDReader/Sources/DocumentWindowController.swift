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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
