import XCTest
@testable import MDReader

final class LinkPolicyTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LinkPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func file(_ name: String, executable: Bool = false) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return url
    }

    /// What the page was loaded with: `mdres:///<dir>/`.
    private var base: URL { PreviewWebView.baseURL(forDirectory: dir)! }
    private func click(_ url: URL) -> LinkPolicy.Action { LinkPolicy.action(for: url, isLinkClick: true, base: base) }
    /// A relative href as WebKit resolves it inside the page.
    private func href(_ relative: String) -> URL { URL(string: relative, relativeTo: base)!.absoluteURL }

    // MARK: Base URL

    func testBaseURLUsesResourceScheme() {
        XCTAssertEqual(base.scheme, "mdres")
        XCTAssertTrue(base.absoluteString.hasSuffix("/"))
        XCTAssertEqual(PreviewWebView.fileURL(for: href("pic.png"))?.path, dir.appendingPathComponent("pic.png").path)
        XCTAssertEqual(PreviewWebView.fileURL(for: href("../up.png"))?.path, dir.deletingLastPathComponent().appendingPathComponent("up.png").path)
        XCTAssertNil(PreviewWebView.fileURL(for: URL(string: "https://x/y.png")!))
        XCTAssertNil(PreviewWebView.baseURL(forDirectory: nil))
    }

    // MARK: Initial load and anchors

    func testInitialLoadOfBaseDirectoryIsAllowed() {
        XCTAssertEqual(LinkPolicy.action(for: base, isLinkClick: false, base: base), .allowInPage)
        XCTAssertEqual(LinkPolicy.action(for: URL(string: "about:blank")!, isLinkClick: false, base: nil), .allowInPage)
    }

    func testInPageAnchorClickIsAllowed() {
        XCTAssertEqual(click(href("#section-2")), .allowInPage)
    }

    func testNonClickNavigationsAreBlocked() {
        // <meta http-equiv="refresh">, form posts, JS location changes.
        XCTAssertEqual(LinkPolicy.action(for: URL(string: "https://evil.example/")!, isLinkClick: false, base: base), .block)
        XCTAssertEqual(LinkPolicy.action(for: URL(fileURLWithPath: "/etc/passwd"), isLinkClick: false, base: base), .block)
        XCTAssertEqual(LinkPolicy.action(for: href("other.md"), isLinkClick: false, base: base), .block)
        // A file: URL with the same path is not the page (the page is mdres:).
        XCTAssertEqual(LinkPolicy.action(for: dir, isLinkClick: false, base: base), .block)
    }

    // MARK: Relative links resolve through the resource scheme

    func testRelativeMarkdownLinkOpensAsDocument() throws {
        let md = try file("other.md")
        XCTAssertEqual(click(href("other.md")), .openMarkdown(md))
        XCTAssertEqual(click(href("../\(dir.lastPathComponent)/other.md")), .openMarkdown(md))
    }

    func testRelativeImageLinkOpensFile() throws {
        let png = try file("pic.png")
        XCTAssertEqual(click(href("pic.png")), .openFile(png))
    }

    func testRelativeScriptLinkIsOnlyRevealed() throws {
        let sh = try file("run.command")
        XCTAssertEqual(click(href("run.command")), .revealFile(sh))
    }

    // MARK: External schemes

    func testWebAndMailLinksOpenExternally() {
        let https = URL(string: "https://example.com/a?b=c")!
        XCTAssertEqual(click(https), .openExternal(https))
        let mail = URL(string: "mailto:a@example.com")!
        XCTAssertEqual(click(mail), .openExternal(mail))
    }

    func testOtherSchemesAreBlocked() {
        for s in ["javascript:alert(1)", "x-apple.systempreferences:com.apple.preference.security",
                  "ssh://host", "tel:+358", "vscode://file/etc/passwd", "data:text/html,hi", "ftp://x/y"] {
            XCTAssertEqual(click(URL(string: s)!), .block, s)
        }
    }

    // MARK: Files

    func testMarkdownOpensAsDocument() throws {
        let md = try file("other.md")
        XCTAssertEqual(click(md), .openMarkdown(md))
        let missing = dir.appendingPathComponent("missing.markdown")
        XCTAssertEqual(click(missing), .openMarkdown(missing))
    }

    func testBenignDocumentsOpenInDefaultApp() throws {
        for name in ["pic.png", "doc.pdf", "clip.mp4", "notes.json", "page.html"] {
            let url = try file(name)
            XCTAssertEqual(click(url), .openFile(url), name)
        }
        XCTAssertEqual(click(dir), .openFile(dir))
    }

    func testLaunchableFilesAreOnlyRevealed() throws {
        for name in ["run.command", "run.sh", "tool.py", "Thing.app", "x.scpt", "site.webloc",
                     "bundle.jar", "arc.zip", "disk.dmg", "pkg.pkg", "flow.workflow", "term.terminal",
                     // text/XML-conforming types whose handler launches or installs something
                     "launch.jnlp", "profile.mobileconfig", "link.url", "link.inetloc", "cert.cer",
                     "id.p12", "s.shortcut", "a.action", "x.savedSearch", "RUN.COMMAND", "e.js"] {
            let url = try file(name)
            XCTAssertEqual(click(url), .revealFile(url), name)
        }
    }

    func testExecutableBitIsOnlyRevealedEvenWithBenignExtension() throws {
        let url = try file("readme.txt.png", executable: true)
        XCTAssertEqual(click(url), .revealFile(url))
    }

    func testSymlinkIsOnlyRevealed() throws {
        let target = try file("target.png")
        let link = dir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(click(link), .revealFile(link))
    }

    func testUnknownExtensionIsOnlyRevealed() throws {
        let url = try file("mystery.qqqzzz")
        XCTAssertEqual(click(url), .revealFile(url))
    }
}
