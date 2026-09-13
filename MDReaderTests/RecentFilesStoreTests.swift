import XCTest
@testable import MDReader

final class RecentFilesStoreTests: XCTestCase {
    private var suite: UserDefaults!
    private let suiteName = "MDReaderTests.recent"

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: suiteName)
        suite.removePersistentDomain(forName: suiteName)
        RecentFilesStore.defaults = suite
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        RecentFilesStore.defaults = .standard
        super.tearDown()
    }

    func testRecordMovesToFrontAndDedupes() {
        RecentFilesStore.record(URL(fileURLWithPath: "/tmp/a.md"))
        RecentFilesStore.record(URL(fileURLWithPath: "/tmp/b.md"))
        RecentFilesStore.record(URL(fileURLWithPath: "/tmp/a.md"))
        XCTAssertEqual(RecentFilesStore.urls.map(\.path), ["/tmp/a.md", "/tmp/b.md"])
    }

    func testCapsAtMaxCount() {
        for i in 0..<(RecentFilesStore.maxCount + 20) {
            RecentFilesStore.record(URL(fileURLWithPath: "/tmp/\(i).md"))
        }
        XCTAssertEqual(RecentFilesStore.urls.count, RecentFilesStore.maxCount)
        XCTAssertEqual(RecentFilesStore.urls.first?.lastPathComponent, "\(RecentFilesStore.maxCount + 19).md")
    }

    func testExistingURLsFiltersMissingFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let real = dir.appendingPathComponent("real.md")
        try "x".write(to: real, atomically: true, encoding: .utf8)
        RecentFilesStore.record(real)
        RecentFilesStore.record(dir.appendingPathComponent("ghost.md"))
        XCTAssertEqual(RecentFilesStore.existingURLs.map(\.lastPathComponent), ["real.md"])
    }

    func testClear() {
        RecentFilesStore.record(URL(fileURLWithPath: "/tmp/a.md"))
        RecentFilesStore.clear()
        XCTAssertTrue(RecentFilesStore.urls.isEmpty)
    }
}
