import XCTest
import WebKit
@testable import MDReader

/// Drives the real pipeline: Markdown text → MarkdownDocument → PreviewViewController (its
/// WKWebView, delegates and LinkPolicy) with the side effects replaced by a recorder.
@MainActor
final class PreviewIntegrationTests: XCTestCase {
    private var dir: URL!
    private var document: MarkdownDocument!
    private var controller: PreviewViewController!
    private var window: NSWindow!
    private var recorded: [LinkPolicy.Action] = []

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# other\n".utf8).write(to: dir.appendingPathComponent("other.md"))
    }

    override func tearDownWithError() throws {
        window?.contentView = nil
        controller = nil
        document?.close()
        try? FileManager.default.removeItem(at: dir)
    }

    private func open(markdown: String) throws {
        let file = dir.appendingPathComponent("doc.md")
        try Data(markdown.utf8).write(to: file)
        document = MarkdownDocument()
        try document.read(from: Data(markdown.utf8), ofType: "net.daringfireball.markdown")
        document.fileURL = file
        controller = PreviewViewController(document: document)
        recorded = []
        controller.actionHandler = { [weak self] in self?.recorded.append($0) }
        let loaded = expectation(description: "page loaded")
        controller.onPageLoaded = { loaded.fulfill() }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        wait(for: [loaded], timeout: 10)
    }

    private func eval(_ js: String) throws -> Any? {
        var out: Any?
        var err: Error?
        let done = expectation(description: "js")
        controller.webView.evaluateJavaScript(js) { v, e in out = v; err = e; done.fulfill() }
        wait(for: [done], timeout: 10)
        if let err { throw err }
        return out
    }

    private func settle(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    func testHostileMarkdownDoesNothingOnItsOwn() throws {
        try open(markdown: """
        # Hostile

        <script>window.__pwned = 'inline'</script>
        <img src="x.png" onerror="window.__pwned = 'onerror'">
        <meta http-equiv="refresh" content="0;url=https://evil.example/">
        <base href="https://evil.example/">
        <link rel="preconnect" href="https://evil.example/">
        <form action="https://evil.example/" method="post"><button id="b">go</button></form>
        <object data="mdres:///etc/hosts"></object><embed src="mdres:///etc/hosts">

        [js](javascript:window.__pwned='href') [rel](other.md)
        """)
        settle(1.5)
        XCTAssertEqual(recorded, [], "nothing may happen without a click")
        XCTAssertEqual(controller.webView.url?.scheme, "mdres")
        XCTAssertEqual(try eval("String(window.__pwned)") as? String, "undefined")
        // Structural tags were neutralised by the renderer, not just blocked by CSP.
        XCTAssertEqual(try eval("document.querySelectorAll('meta[http-equiv=refresh], base, link, object, embed').length") as? Int, 0)
        // base-uri 'none' + no <base>: relative link still resolves to the document directory.
        let href = try eval("document.querySelector('a[href$=\"other.md\"]').href") as? String ?? ""
        XCTAssertTrue(href.hasPrefix("mdres://"), href)
        _ = try eval("document.getElementById('b').click()")
        settle(0.5)
        XCTAssertEqual(recorded, [], "form submission must not reach any handler")
    }

    func testLinkClickGoesThroughPolicyExactlyOnce() throws {
        try open(markdown: "[web](https://example.com/page) [md](other.md) [sh](run.command) [blank](https://example.org/){target=_blank}\n\n<a id=\"nw\" href=\"https://example.net/\" target=\"_blank\">nw</a>")
        _ = try eval("document.querySelector('a[href=\"https://example.com/page\"]').click()")
        settle(0.5)
        XCTAssertEqual(recorded, [.openExternal(URL(string: "https://example.com/page")!)])
        XCTAssertEqual(controller.webView.url?.scheme, "mdres", "preview must not navigate")

        recorded = []
        _ = try eval("document.querySelector('a[href=\"other.md\"]').click()")
        settle(0.5)
        XCTAssertEqual(recorded, [.openMarkdown(dir.appendingPathComponent("other.md"))])

        recorded = []
        _ = try eval("document.getElementById('nw').click()")
        settle(0.5)
        XCTAssertEqual(recorded.count, 1, "target=_blank must act exactly once, not once per delegate")
        XCTAssertEqual(recorded.first, .openExternal(URL(string: "https://example.net/")!))
    }

    func testProgrammaticWindowOpenIsNotAClick() throws {
        try open(markdown: "hello")
        _ = try eval("window.open('https://example.com/popup'); 1")
        settle(0.5)
        XCTAssertFalse(recorded.contains(.openExternal(URL(string: "https://example.com/popup")!)), "\(recorded)")
        XCTAssertFalse(recorded.contains(where: { if case .openExternal = $0 { return true } else { return false } }))
    }

    func testOversizedDocumentIsRefused() {
        let big = Data(count: MarkdownDocument.maxDocumentBytes + 1)
        let doc = MarkdownDocument()
        XCTAssertThrowsError(try doc.read(from: big, ofType: "net.daringfireball.markdown"))
        XCTAssertNoThrow(try doc.read(from: Data("ok".utf8), ofType: "net.daringfireball.markdown"))
    }
}
