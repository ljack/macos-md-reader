import XCTest
import WebKit
@testable import MDReader

/// Loads real pages into a WKWebView built like the preview and checks that untrusted
/// document HTML cannot run script or read files, while the app's own script and
/// relative images keep working.
final class WebViewHardeningTests: XCTestCase {
    private final class Delegate: NSObject, WKNavigationDelegate {
        var onFinish: (() -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?() }
    }

    private var dir: URL!
    private var webView: WKWebView!
    private var delegate: Delegate!
    private var window: NSWindow!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("WebViewHardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.onePixelPNG.write(to: dir.appendingPathComponent("pixel.png"))
        try Data("secret\n".utf8).write(to: dir.appendingPathComponent("secret.txt"))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: PreviewWebView.makeConfiguration())
        delegate = Delegate()
        webView.navigationDelegate = delegate
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
    }

    override func tearDownWithError() throws {
        window.contentView = nil
        webView = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func load(body: String, in directory: URL? = nil) {
        let done = expectation(description: "page loaded")
        delegate.onFinish = { done.fulfill() }
        webView.loadHTMLString(HTMLTemplate.page(body: body), baseURL: PreviewWebView.baseURL(forDirectory: directory ?? dir))
        wait(for: [done], timeout: 10)
    }

    private func eval(_ js: String) throws -> Any? {
        var out: Any?
        var err: Error?
        let done = expectation(description: "js")
        webView.evaluateJavaScript(js) { value, error in out = value; err = error; done.fulfill() }
        wait(for: [done], timeout: 10)
        if let err { throw err }
        return out
    }

    private func settle(_ seconds: TimeInterval = 0.5) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testOwnScriptRunsAndRelativeImageLoads() throws {
        load(body: "<p>hi</p><img id=\"i\" src=\"pixel.png\">")
        XCTAssertEqual(try eval("typeof window.__md.update") as? String, "function")
        XCTAssertEqual(try imageWidth("i"), 1, "relative image next to the document must load (base \(dir.path))")
    }

    /// Same check from ordinary user directories, not just the temp dir the web process can
    /// read on its own. Documents live in places like these; the resource handler must serve them.
    func testRelativeImageLoadsFromVariousBaseDirectories() throws {
        let tmp = FileManager.default.temporaryDirectory
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let products = Bundle.main.bundleURL.deletingLastPathComponent()
        let bases: [(String, URL)] = [
            ("temporaryDirectory", tmp),
            ("temporaryDirectory resolved", tmp.resolvingSymlinksInPath()),
            ("cachesDirectory", caches),
            ("build products directory", products),
        ]
        var failures: [String] = []
        for (name, root) in bases {
            let base = root.appendingPathComponent("MDReaderImageTest-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: base) }
            try Self.onePixelPNG.write(to: base.appendingPathComponent("pixel.png"))
            load(body: "<img id=\"i\" src=\"pixel.png\">", in: base)
            let width = try imageWidth("i")
            let complete = try eval("document.getElementById('i').complete") as? Bool ?? false
            if width != 1 { failures.append("\(name) \(base.path): naturalWidth=\(width) complete=\(complete)") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
    }

    func testParentDirectoryImageLoads() throws {
        let sub = dir.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        load(body: "<img id=\"i\" src=\"../pixel.png\">", in: sub)
        XCTAssertEqual(try imageWidth("i"), 1, "../ relative images (README next to assets/) must load")
    }

    func testFileSchemeAndNonImageResourcesDoNotLoad() throws {
        let abs = dir.appendingPathComponent("pixel.png").path
        load(body: """
        <img id="f" src="file://\(abs)">
        <img id="t" src="secret.txt">
        <img id="h" src="mdres:///etc/hosts">
        <img id="ok" src="mdres://\(abs)">
        """)
        XCTAssertEqual(try imageWidth("ok"), 1)
        settle(0.5)
        for id in ["f", "t", "h"] {
            XCTAssertEqual(try eval("document.getElementById('\(id)').naturalWidth") as? Int, 0, id)
        }
    }

    func testResourceHandlerServability() throws {
        XCTAssertTrue(DocumentResourceHandler.isServable(dir.appendingPathComponent("pixel.png")))
        XCTAssertFalse(DocumentResourceHandler.isServable(dir.appendingPathComponent("secret.txt")))
        XCTAssertFalse(DocumentResourceHandler.isServable(dir))
        XCTAssertFalse(DocumentResourceHandler.isServable(URL(fileURLWithPath: "/etc/hosts")))
        XCTAssertFalse(DocumentResourceHandler.isServable(URL(fileURLWithPath: "/bin/ls")))
        XCTAssertFalse(DocumentResourceHandler.isServable(dir.appendingPathComponent("nope.png")))
    }

    func testRangeParsing() {
        XCTAssertEqual(DocumentResourceHandler.parseRange("bytes=0-9", total: 100)?.0, 0)
        XCTAssertEqual(DocumentResourceHandler.parseRange("bytes=0-9", total: 100)?.1, 9)
        XCTAssertEqual(DocumentResourceHandler.parseRange("bytes=90-", total: 100)?.1, 99)
        XCTAssertEqual(DocumentResourceHandler.parseRange("bytes=-10", total: 100)?.0, 90)
        XCTAssertEqual(DocumentResourceHandler.parseRange("bytes=0-500", total: 100)?.1, 99)
        XCTAssertNil(DocumentResourceHandler.parseRange("bytes=200-", total: 100))
        XCTAssertNil(DocumentResourceHandler.parseRange("bytes=5-2", total: 100))
        XCTAssertNil(DocumentResourceHandler.parseRange("bytes=0-1,3-4", total: 100))
        XCTAssertNil(DocumentResourceHandler.parseRange("items=0-1", total: 100))
    }

    private func imageWidth(_ id: String) throws -> Int {
        var width = 0
        for _ in 0..<32 {
            width = (try eval("document.getElementById('\(id)').naturalWidth") as? Int) ?? 0
            if width > 0 { break }
            settle(0.25)
        }
        return width
    }

    func testDocumentScriptsDoNotRun() throws {
        load(body: """
        <script>window.__pwned = 'inline'</script>
        <img src="nope.png" onerror="window.__pwned = 'onerror'">
        <svg onload="window.__pwned = 'svg'"></svg>
        <a id="js" href="javascript:window.__pwned='href'">x</a>
        <details open ontoggle="window.__pwned = 'ontoggle'">d</details>
        """)
        settle(0.5)
        _ = try eval("document.getElementById('js').click()")
        settle(0.3)
        XCTAssertEqual(try eval("String(window.__pwned)") as? String, "undefined")
    }

    func testFetchOfLocalFileIsBlocked() throws {
        load(body: "<p>x</p>")
        let js = """
        (async () => { try { const r = await fetch('secret.txt'); return 'fetched:' + await r.text(); }
                       catch (e) { return 'blocked'; } })()
        """
        var result: Any?
        let done = expectation(description: "fetch")
        webView.callAsyncJavaScript("return await (\(js));", arguments: [:], in: nil, in: .page) { r in
            if case .success(let v) = r { result = v } else { result = "blocked" }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(result as? String, "blocked")
    }

    func testDocumentCannotReadRootFile() throws {
        load(body: "<iframe id=\"f\" src=\"file:///etc/hosts\"></iframe><object data=\"file:///etc/hosts\"></object>")
        settle(0.5)
        let frames = try eval("document.getElementById('f').contentDocument ? document.getElementById('f').contentDocument.body.innerText.length : 0") as? Int
        XCTAssertEqual(frames, 0, "frames are blocked by CSP")
    }

    func testMetaRefreshAndBaseAreNeutralised() throws {
        load(body: "<base href=\"https://evil.example/\"><meta http-equiv=\"refresh\" content=\"0;url=https://evil.example/\"><a id=\"a\" href=\"x.md\">x</a>")
        settle(1.0)
        // base-uri 'none': relative link still resolves against the document directory.
        let href = try eval("document.getElementById('a').href") as? String ?? ""
        XCTAssertTrue(href.hasPrefix("mdres://"), href)
        // meta refresh needs the navigation delegate (LinkPolicy) to be blocked; here we only
        // assert the page did not navigate away on its own inside the test host.
        XCTAssertEqual(webView.url?.scheme, "mdres", String(describing: webView.url))
    }

    func testCSPHeaderPresentWithFreshNonce() {
        let a = HTMLTemplate.page(body: "")
        let b = HTMLTemplate.page(body: "")
        XCTAssertTrue(a.contains("http-equiv=\"Content-Security-Policy\""))
        XCTAssertTrue(a.contains("script-src 'nonce-"))
        XCTAssertFalse(a.contains("unsafe-eval"))
        let nonce = { (s: String) -> Substring in
            let r = s.range(of: "'nonce-")!
            return s[r.upperBound...].prefix(while: { $0 != "'" })
        }
        XCTAssertNotEqual(nonce(a), nonce(b))
        XCTAssertGreaterThanOrEqual(nonce(a).count, 22)
    }

    func testRemoteImagesCanBeSwitchedOff() {
        let on = HTMLTemplate.contentSecurityPolicy(nonce: "n", allowRemote: true)
        let off = HTMLTemplate.contentSecurityPolicy(nonce: "n", allowRemote: false)
        XCTAssertTrue(on.contains("img-src mdres: data: blob: https: http:"))
        XCTAssertTrue(off.contains("img-src mdres: data: blob:;"))
        XCTAssertFalse(off.contains("http"))
        XCTAssertFalse(on.contains("file:"), "the web process must have no file: access")
        XCTAssertTrue(HTMLTemplate.page(body: "", allowRemote: false).contains("img-src mdres: data: blob:;"))
    }

    func testRemoteImagesDefaultOn() {
        UserDefaults.standard.removeObject(forKey: "loadRemoteImages")
        XCTAssertTrue(RemoteContent.isEnabled)
        RemoteContent.isEnabled = false
        XCTAssertFalse(RemoteContent.isEnabled)
        XCTAssertFalse(HTMLTemplate.contentSecurityPolicy(nonce: "n").contains("https:"))
        UserDefaults.standard.removeObject(forKey: "loadRemoteImages")
    }

    func testRemoteImageBlockedWhenOff() throws {
        RemoteContent.isEnabled = false
        defer { UserDefaults.standard.removeObject(forKey: "loadRemoteImages") }
        load(body: "<img id=\"r\" src=\"https://127.0.0.1:1/never.png\"><img id=\"l\" src=\"pixel.png\">")
        settle(0.5)
        // CSP-blocked images report complete with zero size immediately; the local one still loads.
        XCTAssertEqual(try eval("document.getElementById('r').naturalWidth") as? Int, 0)
        XCTAssertEqual(try imageWidth("l"), 1, "local image must still load (base \(dir.path))")
    }

    /// 1×1 transparent PNG.
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
}
