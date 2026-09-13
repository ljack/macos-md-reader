import XCTest
@testable import MDReader

final class FrontMatterTests: XCTestCase {
    func testSplitsYAMLBlock() {
        let (fm, body) = FrontMatter.split("---\ntitle: Hi\ntags: a, b\n---\n# Body")
        XCTAssertEqual(fm?.pairs.map(\.key), ["title", "tags"])
        XCTAssertEqual(fm?.pairs.first?.value, "Hi")
        XCTAssertEqual(body, "# Body")
    }

    func testStripsQuotes() {
        let (fm, _) = FrontMatter.split("---\ntitle: \"Quoted\"\n---\n")
        XCTAssertEqual(fm?.pairs.first?.value, "Quoted")
    }

    func testNoFrontMatterPassesThrough() {
        let text = "# Just markdown\n---\nnot front matter"
        let (fm, body) = FrontMatter.split(text)
        XCTAssertNil(fm)
        XCTAssertEqual(body, text)
    }

    func testUnterminatedBlockIsNotFrontMatter() {
        let text = "---\ntitle: x\nno end"
        XCTAssertNil(FrontMatter.split(text).0)
    }

    func testHTMLIsEscaped() {
        let (fm, _) = FrontMatter.split("---\ntitle: <b>x</b>\n---\n")
        XCTAssertTrue(fm!.html.contains("&lt;b&gt;x&lt;/b&gt;"))
    }
}
