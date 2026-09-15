import XCTest
@testable import MDReader

final class MarkdownRendererTests: XCTestCase {
    private func html(_ md: String) -> String { MarkdownRenderer.render(md).html }

    func testHeadingAndParagraph() {
        let out = html("# Title\n\nHello *world*.")
        XCTAssertTrue(out.contains("<h1>Title</h1>"))
        XCTAssertTrue(out.contains("<em>world</em>"))
    }

    func testGFMTable() {
        let out = html("| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertTrue(out.contains("<table>"))
        XCTAssertTrue(out.contains("<th>a</th>"))
        XCTAssertTrue(out.contains("<td>2</td>"))
    }

    func testTaskList() {
        let out = html("- [x] done\n- [ ] todo")
        XCTAssertTrue(out.contains("type=\"checkbox\""))
        XCTAssertTrue(out.contains("checked"))
    }

    func testStrikethroughAndAutolink() {
        let out = html("~~gone~~ https://example.com")
        XCTAssertTrue(out.contains("<del>gone</del>"))
        XCTAssertTrue(out.contains("<a href=\"https://example.com\">"))
    }

    func testFootnotes() {
        let out = html("Text[^1].\n\n[^1]: Note.")
        XCTAssertTrue(out.contains("footnote"))
    }

    func testFencedCodeKeepsLanguageClass() {
        let out = html("```swift\nlet x = 1\n```")
        XCTAssertTrue(out.contains("<code class=\"language-swift\">"))
    }

    func testRawHTMLAllowedButScriptFiltered() {
        let out = html("<b>bold</b>\n\n<script>alert(1)</script>")
        XCTAssertTrue(out.contains("<b>bold</b>"))
        XCTAssertFalse(out.contains("<script>"), "tagfilter must neutralise <script>")
    }

    func testEmptyInput() {
        XCTAssertEqual(html(""), "")
    }

    func testPerformanceLargeDocument() {
        let doc = String(repeating: "## Section\n\nSome *text* with `code` and a [link](x).\n\n- a\n- b\n\n", count: 2000)
        measure { _ = MarkdownRenderer.render(doc) }
    }

    func testStructuralTagsAreNeutralised() {
        let out = html("""
        <link rel="preconnect" href="https://x/">
        <META http-equiv="refresh" content="0;url=https://x/">
        <base href="https://x/">
        <object data="a"></object><embed src="b"><applet code="c"></applet>
        <p>kept <b>bold</b> <kbd>k</kbd> <details><summary>s</summary>d</details></p>
        """)
        for tag in ["<link", "<META", "<meta", "<base", "<object", "</object", "<embed", "<applet"] {
            XCTAssertFalse(out.contains(tag), "\(tag) must be escaped in: \(out)")
        }
        XCTAssertTrue(out.contains("&lt;link rel="))
        XCTAssertTrue(out.contains("<b>bold</b>"))
        XCTAssertTrue(out.contains("<kbd>k</kbd>"))
        XCTAssertTrue(out.contains("<details>"))
        // Not fooled by look-alikes.
        XCTAssertTrue(html("<linkage>x</linkage> <metadata>y</metadata> <basement>z</basement>").contains("<linkage>"))
    }

    func testTagfilterStillEscapesScriptAndStyle() {
        let out = html("<script>1</script><style>a{}</style><iframe src=x></iframe>")
        XCTAssertFalse(out.contains("<script"))
        XCTAssertFalse(out.contains("<style"))
        XCTAssertFalse(out.contains("<iframe"))
    }
}
