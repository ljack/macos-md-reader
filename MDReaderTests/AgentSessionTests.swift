import XCTest
@testable import MDReader

final class AgentSessionTests: XCTestCase {
    private func session(_ host: AgentSession.Host = .teerminal, id: String = "x", dir: String,
                         activity: Date? = nil, active: Bool = false) -> AgentSession {
        AgentSession(host: host, id: id, directory: dir, title: "", lastActivity: activity, isActive: active)
    }

    func testPicksDeepestDirectoryContainingTheFile() {
        let repo = session(id: "repo", dir: "/Users/j/_dev/app")
        let sub = session(id: "sub", dir: "/Users/j/_dev/app/docs")
        let other = session(id: "other", dir: "/Users/j/_dev/other")
        let hit = AgentSession.best(for: "/Users/j/_dev/app/docs/README.md", among: [other, repo, sub])
        XCTAssertEqual(hit?.id, "sub")
    }

    func testPrefixMustBeAWholePathComponent() {
        let s = session(dir: "/Users/j/_dev/app")
        XCTAssertNil(AgentSession.best(for: "/Users/j/_dev/app2/README.md", among: [s]))
        XCTAssertNil(AgentSession.best(for: "/Users/j/_dev/README.md", among: [s]))
    }

    func testSameDirectoryPrefersMostRecentActivityThenActive() {
        let old = session(id: "old", dir: "/r", activity: Date(timeIntervalSince1970: 100))
        let new = session(id: "new", dir: "/r", activity: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(AgentSession.best(for: "/r/a.md", among: [new, old])?.id, "new")
        let idle = session(id: "idle", dir: "/r")
        let active = session(id: "active", dir: "/r", active: true)
        XCTAssertEqual(AgentSession.best(for: "/r/a.md", among: [idle, active])?.id, "active")
    }

    func testParsesTeerminalManifestAndDropsDeadSessions() {
        let json = """
        [{"sessionId":"7156933A-4588-4BDB-A42C-0FA9F335C70A","workspaceDir":"/Users/j/_dev/teerminal",
          "workspaceName":"teerminal","presetSlug":"claude","status":"waiting",
          "startedAt":"2026-09-15T20:00:00Z","lastActivityAt":"2026-09-15T21:30:00Z","pid":1,"containment":null},
         {"sessionId":"B","workspaceDir":"/tmp/x","workspaceName":"x","presetSlug":"codex","status":"exited",
          "startedAt":"2026-09-15T20:00:00Z","lastActivityAt":"2026-09-15T20:01:00Z","pid":2,"containment":null}]
        """
        let sessions = TeerminalManifest.parse(Data(json.utf8))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "7156933A-4588-4BDB-A42C-0FA9F335C70A")
        XCTAssertEqual(sessions[0].directory, "/Users/j/_dev/teerminal")
        XCTAssertEqual(sessions[0].title, "claude in teerminal")
        XCTAssertTrue(sessions[0].isActive)
        XCTAssertEqual(sessions[0].lastActivity, ISO8601DateFormatter().date(from: "2026-09-15T21:30:00Z"))
        XCTAssertEqual(TeerminalManifest.parse(Data("[]".utf8)), [])
        XCTAssertEqual(TeerminalManifest.parse(Data("garbage".utf8)), [])
    }

    func testDeepLinksAreEscaped() {
        XCTAssertEqual(TeerminalManifest.focusURL(sessionID: "ABC")?.absoluteString, "teerminal://focus?session=ABC")
        let url = TeerminalManifest.openURL(directory: "/Users/j/My Docs/repo", preset: "codex")
        XCTAssertEqual(url?.absoluteString, "teerminal://open?dir=/Users/j/My%20Docs/repo&preset=codex")
        let noPreset = TeerminalManifest.openURL(directory: "/r", preset: "")
        XCTAssertEqual(noPreset?.absoluteString, "teerminal://open?dir=/r")
    }

    func testScriptRowsBecomeSessionsPerWorkingDirectory() {
        // A tty that does not exist yields no directories, so the row is dropped rather than misattributed.
        XCTAssertEqual(TerminalScripting.sessions(host: .iterm2, fromRows: "id1\t/dev/ttys999\tname\n"), [])
        XCTAssertEqual(TerminalScripting.sessions(host: .iterm2, fromRows: "broken-row\n"), [])
    }

    func testOwnTTYResolvesToACurrentDirectory() throws {
        // The test host has a controlling tty when run from a terminal; under CI / Xcode it has none.
        guard let tty = TerminalScripting.ttyPath(ofPID: getpid()) else { throw XCTSkip("no controlling tty") }
        let dirs = TerminalScripting.workingDirectories(onTTY: tty)
        XCTAssertTrue(dirs.contains(FileManager.default.currentDirectoryPath), "\(tty): \(dirs)")
    }

    func testQuotingForAppleScriptAndShell() {
        XCTAssertEqual(TerminalScripting.escaped(#"say "hi" \ there"#), #"say \"hi\" \\ there"#)
        XCTAssertEqual(TerminalScripting.shellQuoted("/Users/j/it's here"), #"'/Users/j/it'\''s here'"#)
    }
}
