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

    private func load(body: String) {
        let done = expectation(description: "page loaded")
        delegate.onFinish = { done.fulfill() }
        webView.loadHTMLString(HTMLTemplate.page(body: body), baseURL: dir)
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
        var width = 0
        for _ in 0..<20 {
            width = (try eval("document.getElementById('i').naturalWidth") as? Int) ?? 0
            if width > 0 { break }
            settle(0.25)
        }
        XCTAssertEqual(width, 1, "relative image next to the document must load")
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
        XCTAssertTrue(href.hasPrefix("file://"), href)
        // meta refresh needs the navigation delegate (LinkPolicy) to be blocked; here we only
        // assert the page did not navigate away on its own inside the test host.
        XCTAssertTrue((webView.url?.isFileURL ?? true), String(describing: webView.url))
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
        XCTAssertTrue(on.contains("img-src file: data: blob: https: http:"))
        XCTAssertTrue(off.contains("img-src file: data: blob:;"))
        XCTAssertFalse(off.contains("http"))
        XCTAssertTrue(HTMLTemplate.page(body: "", allowRemote: false).contains("img-src file: data: blob:;"))
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
        var width = 0
        for _ in 0..<20 {
            width = (try eval("document.getElementById('l').naturalWidth") as? Int) ?? 0
            if width > 0 { break }
            settle(0.25)
        }
        XCTAssertEqual(width, 1)
    }

    /// 1×1 transparent PNG.
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
}
